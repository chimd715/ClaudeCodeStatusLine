#!/usr/bin/env bash
# Install Claude Code Status Line + the claude-code-statusline plugin
# (slash commands /setmsg and /setmemo).
#
# Installs:
#   - statusline.sh                  → $CLAUDE_DIR/statusline.sh
#   - cleanup-statusline-msgs.py     → $CLAUDE_DIR/scripts/
#   - Plugin tree                    → $CLAUDE_DIR/plugins/marketplaces/claude-code-statusline/
#
# Configures (idempotently):
#   - statusLine entry in settings.json (only if unset)
#   - SessionStart cleanup hook in settings.json (only if missing)
#   - known_marketplaces.json entry for the local marketplace
#   - enabledPlugins entry in settings.json
#
# Re-running is safe — every step is a no-op when already applied.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$CLAUDE_DIR/settings.json"

PLUGIN_NAME="claude-code-statusline"
MARKETPLACE_NAME="claude-code-statusline"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE_NAME}"
MARKETPLACE_DIR="$CLAUDE_DIR/plugins/marketplaces/$MARKETPLACE_NAME"
KNOWN_MARKETPLACES="$CLAUDE_DIR/plugins/known_marketplaces.json"

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

# ---------- 2. Statusline file install ----------
mkdir -p \
    "$CLAUDE_DIR" \
    "$CLAUDE_DIR/scripts" \
    "$CLAUDE_DIR/cache/statusline-msg" \
    "$CLAUDE_DIR/cache/statusline-memo"

install -m 755 "$SRC_DIR/statusline.sh"               "$CLAUDE_DIR/statusline.sh"
install -m 755 "$SRC_DIR/cleanup-statusline-msgs.py"  "$CLAUDE_DIR/scripts/cleanup-statusline-msgs.py"
ok "Statusline files installed to $CLAUDE_DIR"

# ---------- 2b. Remove legacy install (pre-plugin layout) ----------
for legacy in "$CLAUDE_DIR/commands/setmsg.md" "$CLAUDE_DIR/commands/setmemo.md"; do
    if [ -f "$legacy" ]; then
        rm -f "$legacy"
        info "Removed legacy file: $legacy"
    fi
done

# ---------- 3. Plugin tree install ----------
mkdir -p \
    "$MARKETPLACE_DIR/.claude-plugin" \
    "$MARKETPLACE_DIR/commands" \
    "$MARKETPLACE_DIR/scripts"

install -m 644 "$SRC_DIR/.claude-plugin/plugin.json"      "$MARKETPLACE_DIR/.claude-plugin/plugin.json"
install -m 644 "$SRC_DIR/.claude-plugin/marketplace.json" "$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
install -m 644 "$SRC_DIR/commands/setmsg.md"              "$MARKETPLACE_DIR/commands/setmsg.md"
install -m 644 "$SRC_DIR/commands/setmemo.md"             "$MARKETPLACE_DIR/commands/setmemo.md"
install -m 755 "$SRC_DIR/scripts/setmsg.sh"               "$MARKETPLACE_DIR/scripts/setmsg.sh"
install -m 755 "$SRC_DIR/scripts/setmemo.sh"              "$MARKETPLACE_DIR/scripts/setmemo.sh"
ok "Plugin tree installed to $MARKETPLACE_DIR"

# ---------- 4. settings.json wiring ----------
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
    info "Created empty $SETTINGS"
fi

jq empty "$SETTINGS" 2>/dev/null || fail "$SETTINGS is not valid JSON — fix it before re-running"

STATUSLINE_CMD="$CLAUDE_DIR/statusline.sh"
HOOK_CMD="python3 \"$CLAUDE_DIR/scripts/cleanup-statusline-msgs.py\""

# 4a. statusLine — only set if absent.
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

# 4b. SessionStart cleanup hook — only add if not present.
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

# 4c. enabledPlugins entry.
if [ "$(jq --arg k "$PLUGIN_KEY" '.enabledPlugins[$k] // false' "$SETTINGS")" = "true" ]; then
    ok "Plugin $PLUGIN_KEY already enabled"
else
    tmp=$(mktemp)
    jq --arg k "$PLUGIN_KEY" '
        .enabledPlugins //= {}
        | .enabledPlugins[$k] = true
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    ok "Enabled plugin $PLUGIN_KEY"
fi

# ---------- 5. known_marketplaces.json registration ----------
mkdir -p "$(dirname "$KNOWN_MARKETPLACES")"
[ -f "$KNOWN_MARKETPLACES" ] || echo '{}' > "$KNOWN_MARKETPLACES"
jq empty "$KNOWN_MARKETPLACES" 2>/dev/null || fail "$KNOWN_MARKETPLACES is not valid JSON"

now_iso=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
tmp=$(mktemp)
jq --arg name "$MARKETPLACE_NAME" \
   --arg loc "$MARKETPLACE_DIR" \
   --arg src "$SRC_DIR" \
   --arg ts  "$now_iso" \
   '.[$name] = {
        source: {source: "local", path: $src},
        installLocation: $loc,
        lastUpdated: $ts
    }' \
    "$KNOWN_MARKETPLACES" > "$tmp" && mv "$tmp" "$KNOWN_MARKETPLACES"
ok "Registered marketplace $MARKETPLACE_NAME → $MARKETPLACE_DIR"

# ---------- 6. Smoke test ----------
echo '{}' | python3 "$CLAUDE_DIR/scripts/cleanup-statusline-msgs.py" \
    && ok "Cleanup script smoke test passed" \
    || warn "Cleanup script returned non-zero — check $CLAUDE_DIR/scripts/cleanup-statusline-msgs.py"

# ---------- 7. Done ----------
echo
printf "${green}Installation complete.${reset}\n\n"
cat <<'EOF'
Restart Claude Code (or open a new session) to pick up the statusLine config,
the SessionStart cleanup hook, and the claude-code-statusline plugin.

Usage:
  /setmsg  <message>   set a per-session label shown after the git branch
  /setmsg              clear the current session's label
  /setmemo <text>      set a multi-line memo (use \n for line breaks)
  /setmemo --session   write a session-scoped memo (overrides cwd memo)
  /setmemo             clear the current scope's memo

If the slash commands don't appear after restart, run inside Claude Code:
  /plugin marketplace add claude-code-statusline
  /plugin install claude-code-statusline@claude-code-statusline

Stale msg/memo files (>30 days old) are removed automatically on session start.
EOF
