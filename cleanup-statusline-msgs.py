#!/usr/bin/env python3
"""Remove statusline session message and memo files older than 30 days.

Invoked from a Claude Code SessionStart hook. Runs silently — any output
would clutter the session start. Errors on individual files are tolerated
so a single permission issue doesn't block the rest of the cleanup.
"""
import sys
import time
from pathlib import Path

CACHE_DIRS = [
    Path.home() / ".claude" / "cache" / "statusline-msg",
    Path.home() / ".claude" / "cache" / "statusline-memo",
]
MAX_AGE_SECONDS = 30 * 86400


def main() -> int:
    cutoff = time.time() - MAX_AGE_SECONDS
    for cache_dir in CACHE_DIRS:
        if not cache_dir.is_dir():
            continue
        for entry in cache_dir.iterdir():
            try:
                if entry.is_file() and entry.stat().st_mtime < cutoff:
                    entry.unlink()
            except OSError:
                continue
    return 0


if __name__ == "__main__":
    sys.exit(main())
