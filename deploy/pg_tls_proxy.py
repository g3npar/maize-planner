"""Local Postgres proxy that adds TLS, for databases that require it (Neon).

Jac 0.37.21's built-in Postgres client (jaclang/data/pgwire.jac) only speaks
plain TCP and drops `?sslmode=...` from JAC_DB_URL, so it can't reach Neon,
which refuses unencrypted connections. This proxy listens on localhost
without TLS and forwards each connection to the real database over TLS
(Postgres SSLRequest negotiation, certificate verification and SNI, which
Neon uses to pick the endpoint).

    python pg_tls_proxy.py local-url URL   print URL pointed at the proxy
    python pg_tls_proxy.py serve URL       run the proxy for URL

Standard library only, so it runs on the Python bundled with Jac.
"""

import asyncio
import os
import ssl
import struct
import sys
from urllib.parse import urlsplit, urlunsplit

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = int(os.environ.get("PG_PROXY_PORT", "6432"))

SSL_REQUEST = 80877103
GSSENC_REQUEST = 80877104


def local_url(url: str) -> str:
    """The same URL with host and port swapped for the proxy, query dropped."""
    parts = urlsplit(url)
    userinfo = parts.netloc.rpartition("@")[0]
    netloc = f"{userinfo}@{LISTEN_HOST}:{LISTEN_PORT}" if userinfo else f"{LISTEN_HOST}:{LISTEN_PORT}"
    return urlunsplit((parts.scheme, netloc, parts.path, "", ""))


def tls_context() -> ssl.SSLContext:
    # Jac's Python has no system CA store configured; it ships a CA bundle
    # next to the interpreter instead.
    candidates = [
        os.environ.get("SSL_CERT_FILE"),
        os.path.join(sys.prefix, "floor", "cacert.pem"),
        "/etc/ssl/certs/ca-certificates.crt",
    ]
    ctx = ssl.create_default_context()
    for path in candidates:
        if path and os.path.isfile(path):
            ctx.load_verify_locations(cafile=path)
            break
    return ctx


async def read_startup(reader: asyncio.StreamReader) -> bytes:
    """Read one length-prefixed startup-phase message from the client."""
    head = await reader.readexactly(4)
    (length,) = struct.unpack("!I", head)
    return head + await reader.readexactly(length - 4)


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        writer.close()


async def handle(client_r, client_w, host: str, port: int, ctx: ssl.SSLContext) -> None:
    upstream_w = None
    try:
        try:
            startup = await read_startup(client_r)
        except asyncio.IncompleteReadError:  # closed without a message (e.g. a port probe)
            client_w.close()
            return
        code = struct.unpack("!I", startup[4:8])[0] if len(startup) >= 8 else 0
        if code in (SSL_REQUEST, GSSENC_REQUEST):
            client_w.write(b"N")
            await client_w.drain()
            startup = await read_startup(client_r)

        upstream_r, upstream_w = await asyncio.open_connection(host, port)
        upstream_w.write(struct.pack("!II", 8, SSL_REQUEST))
        await upstream_w.drain()
        if await upstream_r.readexactly(1) != b"S":
            raise ConnectionError(f"{host} does not accept TLS")
        await upstream_w.start_tls(ctx, server_hostname=host)

        upstream_w.write(startup)
        await upstream_w.drain()
        await asyncio.gather(pipe(client_r, upstream_w), pipe(upstream_r, client_w))
    except Exception as exc:  # one bad connection must not stop the proxy
        print(f"pg_tls_proxy: {type(exc).__name__}: {exc}", file=sys.stderr, flush=True)
        client_w.close()
        if upstream_w is not None:
            upstream_w.close()


async def serve(url: str) -> None:
    parts = urlsplit(url)
    host, port = parts.hostname, parts.port or 5432
    ctx = tls_context()
    server = await asyncio.start_server(
        lambda r, w: handle(r, w, host, port, ctx), LISTEN_HOST, LISTEN_PORT
    )
    print(f"pg_tls_proxy: {LISTEN_HOST}:{LISTEN_PORT} -> {host}:{port} (TLS)", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("local-url", "serve"):
        sys.exit(__doc__)
    if sys.argv[1] == "local-url":
        print(local_url(sys.argv[2]))
    else:
        asyncio.run(serve(sys.argv[2]))
