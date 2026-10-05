#!/usr/bin/env python3
"""Overlay the desktop hub URL without adopting Omajot's writable config."""

import argparse
import json
import os
from pathlib import Path
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hub")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    if not base.is_absolute():
        parser.error("XDG_CONFIG_HOME must be absolute")
    path = base / "omajot" / "config.json"
    for parent in (base, path.parent, path):
        if parent.is_symlink():
            parser.error("refusing symlinked Omajot configuration")
    config = {}
    if path.exists():
        if not path.is_file() or path.stat().st_uid != os.getuid():
            parser.error("Omajot configuration is not a user-owned regular file")
        try:
            config = json.loads(path.read_text())
        except (OSError, ValueError):
            parser.error("Omajot configuration is unreadable or invalid JSON")
        if not isinstance(config, dict):
            parser.error("Omajot configuration must be a JSON object")
    # Only our previous desktop URL may be replaced automatically. A future
    # authenticated remote configuration needs its own explicit policy change.
    if config.get("hub") not in (None, "", "http://127.0.0.1:8797", args.hub):
        parser.error("Omajot already targets another hub; refusing to replace it")
    if args.check:
        return
    if config.get("hub") == args.hub:
        return
    config["hub"] = args.hub
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".config.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(config, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Configured Omajot CLI/TUI: {args.hub}")


if __name__ == "__main__":
    main()
