#!/usr/bin/env python3
"""Remove statusline session message files older than 30 days.

Invoked from a Claude Code SessionStart hook. Runs silently — any output
would clutter the session start. Errors on individual files are tolerated
so a single permission issue doesn't block the rest of the cleanup.
"""
import sys
import time
from pathlib import Path

CACHE_DIR = Path.home() / ".claude" / "cache" / "statusline-msg"
MAX_AGE_SECONDS = 30 * 86400


def main() -> int:
    if not CACHE_DIR.is_dir():
        return 0
    cutoff = time.time() - MAX_AGE_SECONDS
    for entry in CACHE_DIR.iterdir():
        try:
            if entry.is_file() and entry.stat().st_mtime < cutoff:
                entry.unlink()
        except OSError:
            continue
    return 0


if __name__ == "__main__":
    sys.exit(main())
