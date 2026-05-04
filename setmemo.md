---
description: Set or clear a multi-line memo for this session (use \n for line breaks)
argument-hint: [text — \n separates lines, leave empty to clear]
---

!`mkdir -p "$HOME/.claude/cache/statusline-memo"; F="$HOME/.claude/cache/statusline-memo/${CLAUDE_SESSION_ID}.txt"; if [ -z "$ARGUMENTS" ]; then rm -f "$F" && echo "Cleared memo"; else printf '%b' "$ARGUMENTS" > "$F" && echo "Set memo ($(wc -l < "$F" | tr -d ' ') line(s))"; fi`
