---
description: Set or clear the custom statusline message for this session.
argument-hint: [message — leave empty to clear]
---

!`T=$(mktemp); trap 'rm -f "$T"' EXIT
cat > "$T" <<'__SETMSG_ARG_EOF_8a3f5c__'
$ARGUMENTS
__SETMSG_ARG_EOF_8a3f5c__
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
exec bash "$DIR/scripts/setmsg.sh" "$(cat "$T")"`
