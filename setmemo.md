---
description: Set or clear a multi-line memo (default scope = cwd; pass --session to scope to this Claude session)
argument-hint: [--session] [text — paste multi-line directly, or use \n; empty to clear]
---

!`MEMO_DIR="$HOME/.claude/cache/statusline-memo"
mkdir -p "$MEMO_DIR"
T=$(mktemp)
cat > "$T" <<'__SETMEMO_ARG_EOF_8a3f5c__'
$ARGUMENTS
__SETMEMO_ARG_EOF_8a3f5c__
S=$(cat "$T"); rm -f "$T"
case "$S" in
  '"'*'"') S=${S#\"}; S=${S%\"} ;;
  "'"*"'") S=${S#\'}; S=${S%\'} ;;
esac
USE_SESSION=0
case "$S" in
  --session\ *)    USE_SESSION=1; S=${S#--session } ;;
  --session$'\n'*) USE_SESSION=1; S=${S#--session?} ;;
  --session\\n*)   USE_SESSION=1; S=${S#--session\\n} ;;
  --session)       USE_SESSION=1; S="" ;;
esac
if [ "$USE_SESSION" = "1" ]; then
  SCOPE="session"
  F="$MEMO_DIR/session-${CLAUDE_SESSION_ID}.txt"
else
  SCOPE="cwd"
  if command -v shasum >/dev/null 2>&1; then
    HASH=$(printf '%s' "$PWD" | shasum -a 256 | awk '{print $1}' | cut -c1-16)
  else
    HASH=$(printf '%s' "$PWD" | sha256sum | awk '{print $1}' | cut -c1-16)
  fi
  F="$MEMO_DIR/cwd-${HASH}.txt"
fi
if [ -z "$S" ]; then
  rm -f "$F" && echo "Cleared memo (scope: $SCOPE)"
else
  case "$S" in
    *$'\n'*) printf '%s' "$S" > "$F" ;;
    *'\n'*)  printf '%b' "$S" > "$F" ;;
    *)       printf '%s' "$S" > "$F" ;;
  esac
  echo "Set memo (scope: $SCOPE, $(awk 'END{print NR}' "$F") line(s))"
fi`
