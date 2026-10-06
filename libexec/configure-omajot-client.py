#!/usr/bin/env python3
"""Overlay the authenticated hub identity without adopting writable app config."""

import argparse
import json
import os
from pathlib import Path
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hub")
    parser.add_argument("--login", required=True)
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
    # Only Funk's previous local endpoints may migrate automatically. Never
    # silently switch another notebook or an explicitly configured identity.
    if config.get("hub") not in (
        None, "", "http://127.0.0.1:8797", "http://127.0.0.1:8799", args.hub,
    ):
        parser.error("Omajot already targets another hub; refusing to replace it")
    if config.get("hub_login") not in (None, "", args.login):
        parser.error("Omajot already trusts another identity; refusing to replace it")
    if args.check:
        return
    if config.get("hub") == args.hub and config.get("hub_login") == args.login:
        return
    config["hub"] = args.hub
    config["hub_login"] = args.login
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
    print("Configured Omajot client and hub identity (machine-local).")


if __name__ == "__main__":
    main()
