#!/usr/bin/env bash
# Set or clear single-line statusline message for the current Claude session.
# Reads message from $1. Empty -> clear.
# Requires CLAUDE_SESSION_ID in env.

set -u
S="${1-}"
SID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
F="$HOME/.claude/cache/statusline-msg/${SID}.txt"
mkdir -p "$(dirname "$F")"

case "$S" in
  '"'*'"') S=${S#\"}; S=${S%\"} ;;
  "'"*"'") S=${S#\'}; S=${S%\'} ;;
esac

if [ -z "$S" ]; then
  rm -f "$F" && echo "Cleared statusline message"
else
  printf '%s' "$S" > "$F"
  echo "Set statusline message: $S"
fi
