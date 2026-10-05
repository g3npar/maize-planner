"""Put back the file times Jac's build-time compile cache expects.

The Dockerfile compiles the server ahead of time (`jac run --faux planner`)
because compiling at boot peaks above Render's 512 MB. Jac reuses that compile
only if every project file's (mtime_ns, size) matches what it recorded, and
image builds don't always keep sub-second file times, so on Render every file
looked changed and the server recompiled at boot (and ran out of memory).

The files in the image are exactly the ones that were compiled, so this sets
each one's mtime back to the recorded value when its size still matches.
Run it with Jac's bundled Python: the cache is a `marshal` file from it.
"""

import glob
import marshal
import os
import sys


def stamps(value, found):
    """Collect every {path: (mtime_ns, size)} mapping inside the cache record."""
    if isinstance(value, dict):
        for k, v in value.items():
            if (
                isinstance(k, str)
                and os.path.isabs(k)
                and isinstance(v, tuple)
                and len(v) == 2
                and all(isinstance(x, int) for x in v)
            ):
                found[k] = v
            else:
                stamps(v, found)
    elif isinstance(value, (list, tuple)):
        for v in value:
            stamps(v, found)


def main(root: str) -> None:
    found = {}
    for path in glob.glob(os.path.join(root, ".jac", "cache", "applications", "*.bin")):
        try:
            with open(path, "rb") as f:
                record = marshal.load(f)
        except Exception as exc:
            print(f"restore_mtimes: skipping {path}: {exc}", file=sys.stderr)
            continue
        stamps(record, found)
    fixed = 0
    for path, (mtime_ns, size) in found.items():
        try:
            st = os.stat(path)
            if st.st_size == size and st.st_mtime_ns != mtime_ns:
                os.utime(path, ns=(mtime_ns, mtime_ns))
                fixed += 1
        except OSError:
            pass
    print(f"restore_mtimes: {fixed} of {len(found)} file times restored", flush=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
