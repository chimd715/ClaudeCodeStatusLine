---
description: Set or clear the custom statusline message for this session
argument-hint: [message — leave empty to clear]
---

!`F="$HOME/.claude/cache/statusline-msg/${CLAUDE_SESSION_ID}.txt"
mkdir -p "$(dirname "$F")"
T=$(mktemp)
cat > "$T" <<'__SETMSG_ARG_EOF_8a3f5c__'
$ARGUMENTS
__SETMSG_ARG_EOF_8a3f5c__
S=$(cat "$T"); rm -f "$T"
case "$S" in
  '"'*'"') S=${S#\"}; S=${S%\"} ;;
  "'"*"'") S=${S#\'}; S=${S%\'} ;;
esac
if [ -z "$S" ]; then
  rm -f "$F" && echo "Cleared statusline message"
else
  printf '%s' "$S" > "$F"
  echo "Set statusline message: $S"
fi`
