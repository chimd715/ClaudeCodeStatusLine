---
description: Set or clear the persistent statusline memo. Default scope is cwd (survives /clear). Prefix with --session to write a session-scoped memo that overrides the cwd memo while the session lives.
argument-hint: [--session] [text — multi-line ok; empty to clear current scope]
---

!`T=$(mktemp); trap 'rm -f "$T"' EXIT
cat > "$T" <<'__SETMEMO_ARG_EOF_8a3f5c__'
$ARGUMENTS
__SETMEMO_ARG_EOF_8a3f5c__
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
exec bash "$DIR/plugins/marketplaces/claude-code-statusline/scripts/setmemo.sh" "$(cat "$T")"`
