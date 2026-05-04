# Claude Code Status Line

A custom status line for [Claude Code](https://claude.com/claude-code) that displays the model, current task, token usage, rate limits, git state, an optional per-session label, and an optional multi-line memo. It runs as an external shell command, so it does not slow down Claude Code or consume any extra tokens.

## Screenshot

![Status Line Screenshot](screenshot.jpg)

## What it shows

**Line 1 — Model & task**
| Segment | Description |
|---------|-------------|
| **Model** | Current model name (e.g., Opus 4.7) |
| **GSD Alert** | Optional: appears when `/gsd:update` is available or hooks are stale |
| **Task** | Current `in_progress` todo's active form (truncated to 50 chars) |

**Line 2 — Usage & limits**
| Segment | Description |
|---------|-------------|
| **Effort** | Reasoning effort level (low / med / high) |
| **Tokens** | Used / total context window tokens |
| **H** | 5-hour rate limit: percentage, progress bar, reset time |
| **W** | Weekly (7-day) rate limit: percentage, progress bar, reset time |
| **E** | Extra usage: percentage, progress bar, credits spent / limit (if enabled) |

**Line 3 — Project & label**
| Segment | Description |
|---------|-------------|
| **Dir** | Current working directory name |
| **Branch** | Git branch name and file changes (+/-) |
| **Label** | Optional per-session label set via `/setmsg` (truncated to 60 chars) |

**Line 4+ — Multi-line memo (optional)**

Each line of the per-session memo (set via `/setmemo`) becomes its own dimmed row prefixed with `│`. Capped at 20 rows × 100 chars per line for sanity.

Usage percentages are color-coded: green (<50%) → yellow (≥50%) → orange (≥70%) → red (≥90%).

## Per-session label and memo

Two slash commands attach session-scoped text to the statusline:

```
/setmsg  refactoring auth flow             ← short label after the git branch on line 3
/setmsg                                    ← clear the label

/setmemo TODO:\n- fix bug\n- update docs   ← multi-line memo below the status block
/setmemo                                   ← clear the memo
```

`/setmemo` uses `\n` as a literal line-break separator (interpreted via `printf '%b'`).

Storage:
- Labels → `~/.claude/cache/statusline-msg/<session_id>.txt`
- Memos  → `~/.claude/cache/statusline-memo/<session_id>.txt`

A SessionStart hook (`cleanup-statusline-msgs.py`) removes files older than 30 days from both directories — no manual cleanup needed.

## Requirements

### macOS / Linux
- `jq` — JSON parsing
- `python3` — for the SessionStart cleanup hook
- `curl` — for fetching usage data from the Anthropic API
- Claude Code with OAuth authentication (Pro/Max subscription)

### Windows
- PowerShell 5.1+ (included by default on Windows 10/11)
- `git` in PATH (for branch/diff info)
- Claude Code with OAuth authentication (Pro/Max subscription)

> `install.sh` and `/setmsg` are bash-only. Windows users get the core statusline via `statusline.ps1`.

## Installation

### Quick install (macOS / Linux)

```bash
./install.sh
```

The installer is **idempotent** — re-run it any time to repair or update. It:
- Copies `statusline.sh` → `~/.claude/`
- Copies `cleanup-statusline-msgs.py` → `~/.claude/scripts/`
- Copies `setmsg.md` and `setmemo.md` → `~/.claude/commands/`
- Adds `statusLine` to `~/.claude/settings.json` (only if unset)
- Registers the SessionStart cleanup hook (only if missing)

Override the install location with `CLAUDE_CONFIG_DIR=/custom/path ./install.sh`.

After installation, restart Claude Code (or open a new session).

### Manual setup — macOS / Linux

1. Copy the statusline script:

   ```bash
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Add to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh"
     }
   }
   ```

3. *(Optional, for `/setmsg` and `/setmemo`)* — install the slash commands and cleanup hook:

   ```bash
   mkdir -p ~/.claude/scripts ~/.claude/commands \
            ~/.claude/cache/statusline-msg ~/.claude/cache/statusline-memo
   cp cleanup-statusline-msgs.py ~/.claude/scripts/
   cp setmsg.md setmemo.md ~/.claude/commands/
   ```

   Then merge this into `settings.json`:

   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "python3 \"$HOME/.claude/scripts/cleanup-statusline-msgs.py\""
             }
           ]
         }
       ]
     }
   }
   ```

4. Restart Claude Code.

### Manual setup — Windows

> **Windows users should use `statusline.ps1`** instead of the bash script.

1. Copy the script:

   ```powershell
   Copy-Item statusline.ps1 "$env:USERPROFILE\.claude\statusline.ps1"
   ```

2. Add to `%USERPROFILE%\.claude\settings.json`:

   **PowerShell / CMD:**
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "powershell -NoProfile -File \"%USERPROFILE%\\.claude\\statusline.ps1\""
     }
   }
   ```

   **Git Bash / WSL bash:**
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "powershell -NoProfile -File \"$USERPROFILE\\.claude\\statusline.ps1\""
     }
   }
   ```

   > Use `%USERPROFILE%` in CMD/PowerShell or `$USERPROFILE` in bash shells. The `%VAR%` syntax does not expand in bash.

3. Restart Claude Code.

## Caching

Usage data from the Anthropic API is cached for 60 seconds at `/tmp/claude/statusline-usage-cache.json` to avoid excessive API calls. The cache is shared across all Claude Code instances.

## License

MIT

## Author

Daniel Oliveira

[![Website](https://img.shields.io/badge/Website-FF6B6B?style=for-the-badge&logo=safari&logoColor=white)](https://danielapoliveira.com/)
[![X](https://img.shields.io/badge/X-000000?style=for-the-badge&logo=x&logoColor=white)](https://x.com/daniel_not_nerd)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/daniel-ap-oliveira/)
