#!/usr/bin/env bash
# Set or clear the persistent statusline memo.
# Default scope: cwd (survives /clear). Use --session to write a session-scoped
# memo that overrides the cwd memo while the session lives.
# Empty content clears the chosen scope.

set -u
RAW="${1-}"

SCOPE="cwd"
case "$RAW" in
  --session)         SCOPE="session"; S="" ;;
  --session=*)       SCOPE="session"; S="${RAW#--session=}" ;;
  "--session "*)     SCOPE="session"; S="${RAW#--session }" ;;
  -s)                SCOPE="session"; S="" ;;
  "-s "*)            SCOPE="session"; S="${RAW#-s }" ;;
  *)                 S="$RAW" ;;
esac

case "$S" in
  '"'*'"') S=${S#\"}; S=${S%\"} ;;
  "'"*"'") S=${S#\'}; S=${S%\'} ;;
esac

DIR="$HOME/.claude/cache/statusline-memo"
mkdir -p "$DIR"

if [ "$SCOPE" = "session" ]; then
  SID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
  F="$DIR/session-${SID}.txt"
  LABEL="session"
else
  KEY=$(printf '%s' "$PWD" | shasum -a 256 | awk '{print $1}' | cut -c1-16)
  F="$DIR/cwd-${KEY}.txt"
  LABEL="cwd"
fi

if [ -z "$S" ]; then
  rm -f "$F" && echo "Cleared $LABEL memo"
else
  case "$S" in
    *$'\n'*) printf '%s' "$S" > "$F" ;;
    *'\n'*)  printf '%b' "$S" > "$F" ;;
    *)       printf '%s' "$S" > "$F" ;;
  esac
  echo "Set $LABEL memo ($(awk 'END{print NR}' "$F") line(s))"
fi
