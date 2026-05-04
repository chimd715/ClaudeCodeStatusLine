---
description: Set or clear the custom statusline message for this session
argument-hint: [message — leave empty to clear]
---

!`mkdir -p "$HOME/.claude/cache/statusline-msg"; F="$HOME/.claude/cache/statusline-msg/${CLAUDE_SESSION_ID}.txt"; if [ -z "$ARGUMENTS" ]; then rm -f "$F" && echo "Cleared statusline message"; else printf '%s' "$ARGUMENTS" > "$F" && echo "Set statusline message: $ARGUMENTS"; fi`
