---
description: Set or clear a multi-line memo for this session (use \n for line breaks)
argument-hint: [text — paste multi-line directly, or use \n; empty to clear]
---

!`F="$HOME/.claude/cache/statusline-memo/${CLAUDE_SESSION_ID}.txt"
mkdir -p "$(dirname "$F")"
T=$(mktemp)
cat > "$T" <<'__SETMEMO_ARG_EOF_8a3f5c__'
$ARGUMENTS
__SETMEMO_ARG_EOF_8a3f5c__
S=$(cat "$T"); rm -f "$T"
case "$S" in
  '"'*'"') S=${S#\"}; S=${S%\"} ;;
  "'"*"'") S=${S#\'}; S=${S%\'} ;;
esac
if [ -z "$S" ]; then
  rm -f "$F" && echo "Cleared memo"
else
  case "$S" in
    *$'\n'*) printf '%s' "$S" > "$F" ;;
    *'\n'*)  printf '%b' "$S" > "$F" ;;
    *)       printf '%s' "$S" > "$F" ;;
  esac
  echo "Set memo ($(awk 'END{print NR}' "$F") line(s))"
fi`
