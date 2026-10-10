"""The per-user runtime directory, shared by the helper and scripts/session-action."""
import os
from pathlib import Path
import stat


def runtime_base():
    if os.environ.get("XDG_RUNTIME_DIR"):
        return Path(os.environ["XDG_RUNTIME_DIR"])
    # No session runtime dir: use a /tmp folder only this user owns and can enter.
    base = Path(f"/tmp/shale-{os.getuid()}")
    try:
        base.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = base.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SystemExit(f"Unsafe runtime directory: {base}")
    return base
