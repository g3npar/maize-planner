#!/bin/sh
# Container entrypoint: start the planner API server.
#
# Jac's Postgres client can't do TLS, so for a remote database (e.g. Neon) run
# deploy/pg_tls_proxy.py with Jac's bundled Python and point JAC_DB_URL at it.
# Set PG_TLS_PROXY=0 to connect directly (a database that accepts plain TCP).
set -e

if [ -n "$JAC_DB_URL" ] && [ "${PG_TLS_PROXY:-1}" != "0" ]; then
    PY=$(ls /opt/jac/state/rt/*/python/bin/python3* | head -n 1)
    PROXY=/app/deploy/pg_tls_proxy.py
    "$PY" "$PROXY" serve "$JAC_DB_URL" &
    JAC_DB_URL=$("$PY" "$PROXY" local-url "$JAC_DB_URL")
    export JAC_DB_URL
    # Wait for the proxy to listen before Jac tries to connect.
    "$PY" -c '
import os, socket, sys, time
port = int(os.environ.get("PG_PROXY_PORT", "6432"))
for _ in range(50):
    try:
        socket.create_connection(("127.0.0.1", port), 1).close()
        sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit("pg_tls_proxy did not start")
'
fi

exec jac run --serve planner --host 0.0.0.0
