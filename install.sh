#!/usr/bin/env bash
# Install Claude Code Status Line + per-session custom message feature.
#
# Installs:
#   - statusline.sh                  → $CLAUDE_DIR/statusline.sh
#   - cleanup-statusline-msgs.py     → $CLAUDE_DIR/scripts/
#   - setmsg.md  (slash command)     → $CLAUDE_DIR/commands/
#
# Configures (idempotently):
#   - statusLine entry in settings.json (only if unset)
#   - SessionStart cleanup hook in settings.json (only if missing)
#
# Re-running is safe — every step is a no-op when already applied.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$CLAUDE_DIR/settings.json"

green='\033[0;32m'; yellow='\033[0;33m'; red='\033[0;31m'; dim='\033[2m'; reset='\033[0m'
ok()    { printf "${green}✓${reset} %s\n" "$1"; }
info()  { printf "${dim}·${reset} %s\n" "$1"; }
warn()  { printf "${yellow}!${reset} %s\n" "$1"; }
fail()  { printf "${red}✗${reset} %s\n" "$1" >&2; exit 1; }

# ---------- 1. Prerequisite check ----------
for cmd in jq python3; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing dependency: $cmd"
done
command -v curl >/dev/null 2>&1 || warn "curl not found — usage limits (H/W/E) will not display"

# ---------- 2. Directory + file install ----------
mkdir -p \
    "$CLAUDE_DIR" \
    "$CLAUDE_DIR/scripts" \
    "$CLAUDE_DIR/commands" \
    "$CLAUDE_DIR/cache/statusline-msg"

install -m 755 "$SRC_DIR/statusline.sh"               "$CLAUDE_DIR/statusline.sh"
install -m 755 "$SRC_DIR/cleanup-statusline-msgs.py"  "$CLAUDE_DIR/scripts/cleanup-statusline-msgs.py"
install -m 644 "$SRC_DIR/setmsg.md"                   "$CLAUDE_DIR/commands/setmsg.md"
ok "Files installed to $CLAUDE_DIR"

# ---------- 3. settings.json wiring ----------
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
    info "Created empty $SETTINGS"
fi

# Validate existing JSON before mutating it.
jq empty "$SETTINGS" 2>/dev/null || fail "$SETTINGS is not valid JSON — fix it before re-running"

STATUSLINE_CMD="$CLAUDE_DIR/statusline.sh"
HOOK_CMD="python3 \"$CLAUDE_DIR/scripts/cleanup-statusline-msgs.py\""

# 3a. statusLine — only set if absent (don't clobber a custom one).
if jq -e '.statusLine.command' "$SETTINGS" >/dev/null 2>&1; then
    existing=$(jq -r '.statusLine.command' "$SETTINGS")
    if [ "$existing" = "$STATUSLINE_CMD" ]; then
        ok "statusLine already configured"
    else
        warn "statusLine points to '$existing' — leaving it. Update manually if you want this script."
    fi
else
    tmp=$(mktemp)
    jq --arg cmd "$STATUSLINE_CMD" \
        '.statusLine = {type:"command", command:$cmd}' \
        "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    ok "Configured statusLine → $STATUSLINE_CMD"
fi

# 3b. SessionStart cleanup hook — only add if not present.
already=$(jq --arg cmd "$HOOK_CMD" \
    '[.hooks.SessionStart // [] | .[] | .hooks // [] | .[] | .command] | any(. == $cmd)' \
    "$SETTINGS")

if [ "$already" = "true" ]; then
    ok "SessionStart cleanup hook already registered"
else
    tmp=$(mktemp)
    jq --arg cmd "$HOOK_CMD" '
        .hooks //= {}
        | .hooks.SessionStart //= []
        | .hooks.SessionStart += [{hooks: [{type: "command", command: $cmd}]}]
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    ok "Registered SessionStart cleanup hook"
fi

# ---------- 4. Smoke test ----------
echo '{}' | python3 "$CLAUDE_DIR/scripts/cleanup-statusline-msgs.py" \
    && ok "Cleanup script smoke test passed" \
    || warn "Cleanup script returned non-zero — check $CLAUDE_DIR/scripts/cleanup-statusline-msgs.py"

# ---------- 5. Done ----------
echo
printf "${green}Installation complete.${reset}\n\n"
cat <<'EOF'
Restart Claude Code (or open a new session) to pick up the statusLine config
and the SessionStart cleanup hook.

Usage:
  /setmsg <message>   set a per-session message shown after the git branch
  /setmsg             clear the current session's message

Stale message files (>30 days old) are removed automatically on session start.
EOF
