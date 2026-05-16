#!/bin/bash
# Output:
#   Line 1: [🧠] Model | ai-title | ✓ done/total | session-duration
#   Line 2: [⚡] Effort Tokens | 45% ████░░░░ H 21:00 | 23% ████░░░░ W 03/20 14:00 | E $5/$50
#   Line 3: Dir | Branch changes | [/setmsg session label] | vX.Y.Z
#   Line 4+: Optional multi-line memo set via /setmemo

set -f  # disable globbing

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ANSI colors matching oh-my-posh theme
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;160;0m'
cyan='\033[38;2;46;149;153m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
dim='\033[2m'
reset='\033[0m'

# Format token counts (e.g., 50k / 200k)
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

# Format number with commas (e.g., 134,938)
format_commas() {
    printf "%'d" "$1"
}

# Format duration ms → human readable (e.g., 8m13s, 2h05m, 45s)
format_duration() {
    local ms=$1
    local total_s=$(( ms / 1000 ))
    local h=$(( total_s / 3600 ))
    local m=$(( (total_s % 3600) / 60 ))
    local s=$(( total_s % 60 ))
    if [ "$h" -gt 0 ]; then
        printf "%dh%02dm" "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf "%dm%02ds" "$m" "$s"
    else
        printf "%ds" "$s"
    fi
}

# Return color escape based on usage percentage
# Usage: usage_color <pct>
usage_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then echo "$red"
    elif [ "$pct" -ge 70 ]; then echo "$orange"
    elif [ "$pct" -ge 50 ]; then echo "$yellow"
    else echo "$green"
    fi
}

# Generate progress bar
# Usage: progress_bar <pct> <width> <color>
progress_bar() {
    local pct=$1
    local width=${2:-10}
    local color=$3
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""

    # Build filled portion
    for ((i=0; i<filled; i++)); do bar+="█"; done
    # Build empty portion
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf "${color}${bar}${reset}"
}

# ===== Extract data from JSON =====
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
session_id=$(echo "$input" | jq -r '.session_id // empty')
cc_version=$(echo "$input" | jq -r '.version // empty')
thinking_enabled=$(echo "$input" | jq -r '.thinking.enabled // false')
fast_mode=$(echo "$input" | jq -r '.fast_mode // false')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# Context window
size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

# Token usage
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi
pct_remain=$(( 100 - pct_used ))

used_comma=$(format_commas $current)
remain_comma=$(format_commas $(( size - current )))

# Config directory (respects CLAUDE_CONFIG_DIR override)
claude_config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Check reasoning effort
settings_path="$claude_config_dir/settings.json"
effort_level="medium"
if [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ]; then
    effort_level="$CLAUDE_CODE_EFFORT_LEVEL"
elif [ -f "$settings_path" ]; then
    effort_val=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
    [ -n "$effort_val" ] && effort_level="$effort_val"
fi

# ===== AI-generated session title (from transcript) =====
ai_title=""
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    ai_title=$(grep '"type":"ai-title"' "$transcript_path" 2>/dev/null | tail -1 | \
        jq -r '.aiTitle // empty' 2>/dev/null)
fi

# ===== Todo progress (done/total from latest session todo file) =====
todo_progress=""
todos_dir="$claude_config_dir/todos"
if [ -n "$session_id" ] && [ -d "$todos_dir" ]; then
    latest_todo=$(find "$todos_dir" -name "${session_id}-agent-*.json" -type f 2>/dev/null | \
        while read -r f; do
            echo "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) $f"
        done | sort -rn | head -1 | cut -d' ' -f2-)

    if [ -n "$latest_todo" ] && [ -f "$latest_todo" ]; then
        todo_total=$(jq 'length' "$latest_todo" 2>/dev/null)
        todo_done=$(jq '[.[] | select(.status == "completed")] | length' "$latest_todo" 2>/dev/null)
        if [ -n "$todo_total" ] && [ "$todo_total" -gt 0 ] 2>/dev/null; then
            todo_progress="${todo_done}/${todo_total}"
        fi
    fi
fi

# ===== Build three-line output =====
line1=""
line2=""
line3=""

# Line 1: [🧠] Model | ai-title | ✓ todo | duration
[ "$thinking_enabled" = "true" ] && line1+="🧠 "
line1+="${dim}${model_name}${reset}"
if [ -n "$ai_title" ]; then
    if [ ${#ai_title} -gt 50 ]; then
        ai_title="${ai_title:0:47}..."
    fi
    line1+=" ${dim}|${reset} ${white}${ai_title}${reset}"
fi
if [ -n "$todo_progress" ]; then
    line1+=" ${dim}|${reset} ${cyan}✓ ${todo_progress}${reset}"
fi
if [ "$total_duration_ms" -gt 0 ] 2>/dev/null; then
    line1+=" ${dim}|${reset} ${dim}$(format_duration "$total_duration_ms")${reset}"
fi

# Current working directory and git info
cwd=$(echo "$input" | jq -r '.cwd // empty')
display_dir=""
git_branch=""
git_stat=""

if [ -n "$cwd" ]; then
    display_dir="${cwd##*/}"
    git_branch=$(git -C "${cwd}" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$git_branch" ]; then
        git_stat=$(git -C "${cwd}" diff --numstat 2>/dev/null | awk '{a+=$1; d+=$2} END {if (a+d>0) printf "+%d -%d", a, d}')
    fi
fi

# Line 2: [⚡] Effort Tokens | H | W | Extra
[ "$fast_mode" = "true" ] && line2+="⚡ "
case "$effort_level" in
    low)    line2+="${dim}low${reset} " ;;
    medium) line2+="${orange}med${reset} " ;;
    *)      line2+="${green}high${reset} " ;;
esac
line2+="${orange}${used_tokens}/${total_tokens}${reset}"

# Line 3: Dir | Branch changes
if [ -n "$display_dir" ]; then
    line3+="${cyan}${display_dir}${reset}"
fi

if [ -n "$git_branch" ]; then
    [ -n "$line3" ] && line3+=" ${dim}|${reset} "
    line3+="${green}${git_branch}${reset}"
    if [ -n "$git_stat" ]; then
        line3+=" ${green}${git_stat%% *}${reset} ${red}${git_stat##* }${reset}"
    fi
fi

# Custom per-session message (set via /setmsg slash command)
if [ -n "$session_id" ]; then
    session_msg_file="$claude_config_dir/cache/statusline-msg/${session_id}.txt"
    if [ -f "$session_msg_file" ]; then
        session_msg=$(cat "$session_msg_file" 2>/dev/null)
        if [ -n "$session_msg" ]; then
            if [ ${#session_msg} -gt 60 ]; then
                session_msg="${session_msg:0:57}..."
            fi
            [ -n "$line3" ] && line3+=" ${dim}|${reset} "
            line3+="${white}${session_msg}${reset}"
        fi
    fi
fi

# Append Claude Code version to end of line 3
if [ -n "$cc_version" ]; then
    [ -n "$line3" ] && line3+=" ${dim}|${reset} "
    line3+="${dim}v${cc_version}${reset}"
fi

# ===== Cross-platform OAuth token resolution (from statusline.sh) =====
# Tries credential sources in order: env var → macOS Keychain → Linux creds file → GNOME Keyring
get_oauth_token() {
    local token=""

    # 1. Explicit env var override
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    # 2. macOS Keychain
    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    # 3. Linux credentials file
    local creds_file="${claude_config_dir}/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi

    # 4. GNOME Keyring via secret-tool
    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    echo ""
}

# ===== LINE 2 & 3: Usage limits with progress bars (cached) =====
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60  # seconds between API calls
mkdir -p /tmp/claude

needs_refresh=true
usage_data=""

# Check cache — shared across all Claude Code instances to avoid rate limits
if [ -f "$cache_file" ]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt "$cache_max_age" ]; then
        needs_refresh=false
    fi
    usage_data=$(cat "$cache_file" 2>/dev/null)
fi

# Fetch fresh data if cache is stale
if $needs_refresh; then
    # Touch cache immediately so other instances don't also fetch
    touch "$cache_file" 2>/dev/null

    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 10 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/2.1.34" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        # Only cache valid usage responses (not error/rate-limit JSON)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
fi

# Cross-platform ISO to epoch conversion
# Converts ISO 8601 timestamp (e.g. "2025-06-15T12:30:00Z" or "2025-06-15T12:30:00.123+00:00") to epoch seconds.
# Properly handles UTC timestamps and converts to local time.
iso_to_epoch() {
    local iso_str="$1"

    # Try GNU date first (Linux) — handles ISO 8601 format automatically
    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    # BSD date (macOS) - handle various ISO 8601 formats
    local stripped="${iso_str%%.*}"          # Remove fractional seconds (.123456)
    stripped="${stripped%%Z}"                 # Remove trailing Z
    stripped="${stripped%%+*}"               # Remove timezone offset (+00:00)
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"  # Remove negative timezone offset

    # Check if timestamp is UTC (has Z or +00:00 or -00:00)
    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        # For UTC timestamps, parse with timezone set to UTC
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# Format ISO reset time to compact local time
# Usage: format_reset_time <iso_string> <style: time|datetime|date>
format_reset_time() {
    local iso_str="$1"
    local style="$2"
    { [ -z "$iso_str" ] || [ "$iso_str" = "null" ]; } && return

    # Parse ISO datetime and convert to local time (cross-platform)
    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    # Format based on style
    # Try GNU date first (Linux), then BSD date (macOS)
    # Previous implementation piped BSD date through sed/tr, which always returned
    # exit code 0 from the last pipe stage, preventing the GNU date fallback from
    # ever executing on Linux.
    local formatted=""
    case "$style" in
        time)
            formatted=$(date -d "@$epoch" +"%H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%H:%M" 2>/dev/null)
            ;;
        datetime)
            formatted=$(date -d "@$epoch" +"%m/%d %H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%m/%d %H:%M" 2>/dev/null)
            ;;
        *)
            formatted=$(date -d "@$epoch" +"%m/%d" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%m/%d" 2>/dev/null)
            ;;
    esac
    [ -n "$formatted" ] && echo "$formatted"
}

sep=" ${dim}|${reset} "

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
    # ---- 5-hour (current) ----
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
    five_hour_color=$(usage_color "$five_hour_pct")

    five_hour_bar=$(progress_bar "$five_hour_pct" 8 "$five_hour_color")
    line2+="${sep}${five_hour_color}${five_hour_pct}%${reset} ${five_hour_bar} ${white}H${reset}"
    [ -n "$five_hour_reset" ] && line2+=" ${dim}${five_hour_reset}${reset}"

    # ---- 7-day (weekly) ----
    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
    seven_day_color=$(usage_color "$seven_day_pct")

    seven_day_bar=$(progress_bar "$seven_day_pct" 8 "$seven_day_color")
    line2+="${sep}${seven_day_color}${seven_day_pct}%${reset} ${seven_day_bar} ${white}W${reset}"
    [ -n "$seven_day_reset" ] && line2+=" ${dim}${seven_day_reset}${reset}"

    # ---- Extra usage ----
    extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    if [ "$extra_enabled" = "true" ]; then
        extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
        extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
        extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
        # Validate: if values are empty or contain unexpanded variables, show simple "enabled" label
        if [ -n "$extra_used" ] && [ -n "$extra_limit" ] && [[ "$extra_used" != *'$'* ]] && [[ "$extra_limit" != *'$'* ]]; then
            extra_color=$(usage_color "$extra_pct")
            extra_bar=$(progress_bar "$extra_pct" 6 "$extra_color")
            line2+="${sep}${extra_color}${extra_pct}%${reset} ${extra_bar} ${white}E${reset} ${dim}\$${extra_used}/\$${extra_limit}${reset}"
        else
            line2+="${sep}${white}E${reset} ${green}on${reset}"
        fi
    fi
else
    # No valid usage data — show placeholders
    line2+="${sep}${dim}-% ░░░░░░░░${reset} ${white}H${reset}"
    line2+="${sep}${dim}-% ░░░░░░░░${reset} ${white}W${reset}"
fi

# ===== Multi-line memo (set via /setmemo) =====
# Each line of the memo file becomes its own statusline row, dimmed and
# capped to 100 chars wide / 20 rows tall to keep the prompt sane.
#
# Lookup order:
#   1. session-${session_id}.txt  — explicit session-scoped memo (/setmemo --session …)
#   2. cwd-${hash}.txt            — directory-scoped memo (/setmemo …), survives /clear
sha_short16() {
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}' | cut -c1-16
    elif command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}' | cut -c1-16
    fi
}

memo_lines=""
memo_file=""
if [ -n "$session_id" ]; then
    candidate="$claude_config_dir/cache/statusline-memo/session-${session_id}.txt"
    [ -f "$candidate" ] && memo_file="$candidate"
fi
if [ -z "$memo_file" ] && [ -n "$cwd" ]; then
    cwd_key=$(sha_short16 "$cwd")
    candidate="$claude_config_dir/cache/statusline-memo/cwd-${cwd_key}.txt"
    [ -f "$candidate" ] && memo_file="$candidate"
fi
if [ -n "$memo_file" ]; then
    memo_count=0
    while IFS= read -r memo_line || [ -n "$memo_line" ]; do
        memo_count=$((memo_count + 1))
        if [ "$memo_count" -gt 20 ]; then
            memo_lines+=$'\n'"${dim}│ … (memo truncated)${reset}"
            break
        fi
        if [ ${#memo_line} -gt 100 ]; then
            memo_line="${memo_line:0:97}..."
        fi
        memo_lines+=$'\n'"${dim}│ ${memo_line}${reset}"
    done < "$memo_file"
fi

# Output three lines + optional memo rows
printf "%b\n%b\n%b" "$line1" "$line2" "$line3"
[ -n "$memo_lines" ] && printf "%b" "$memo_lines"

exit 0
