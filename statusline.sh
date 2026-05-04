#!/bin/bash
# Three lines:
#   Line 1: Model | [GSD Alert |] Current Task
#   Line 2: Effort Tokens | 45% ████░░░░ H 21:00 | 23% ████░░░░ W 03/20 14:00 | E $5/$50
#   Line 3: Dir | Branch changes

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

# ===== GSD Update Check =====
gsd_alert=""
gsd_cache_file="$claude_config_dir/cache/gsd-update-check.json"
if [ -f "$gsd_cache_file" ]; then
    update_available=$(jq -r '.update_available // false' "$gsd_cache_file" 2>/dev/null)
    stale_hooks=$(jq -r '.stale_hooks // [] | length' "$gsd_cache_file" 2>/dev/null)

    if [ "$update_available" = "true" ]; then
        gsd_alert+="${yellow}⬆ /gsd:update${reset}"
    fi
    if [ "$stale_hooks" -gt 0 ] 2>/dev/null; then
        [ -n "$gsd_alert" ] && gsd_alert+=" "
        gsd_alert+="${red}⚠ stale hooks${reset}"
    fi
fi

# ===== Current Todo Task =====
current_task=""
todos_dir="$claude_config_dir/todos"
if [ -n "$session_id" ] && [ -d "$todos_dir" ]; then
    # Find the most recent todo file for this session (agent todos)
    latest_todo=$(find "$todos_dir" -name "${session_id}-agent-*.json" -type f 2>/dev/null | \
        while read -r f; do
            echo "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) $f"
        done | sort -rn | head -1 | cut -d' ' -f2-)

    if [ -n "$latest_todo" ] && [ -f "$latest_todo" ]; then
        # Extract activeForm from in_progress task
        current_task=$(jq -r '.[] | select(.status == "in_progress") | .activeForm // empty' "$latest_todo" 2>/dev/null | head -1)
    fi
fi

# ===== Build three-line output =====
line1=""
line2=""
line3=""

# Line 1: Model | [GSD Alert |] Current Task
line1+="${dim}${model_name}${reset}"
if [ -n "$gsd_alert" ]; then
    line1+=" ${dim}|${reset} ${gsd_alert}"
fi
if [ -n "$current_task" ]; then
    # Truncate task if too long (max 50 chars)
    if [ ${#current_task} -gt 50 ]; then
        current_task="${current_task:0:47}..."
    fi
    line1+=" ${dim}|${reset} ${white}${current_task}${reset}"
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

# Line 2: Effort Tokens | H | W | Extra
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

# Output three lines
printf "%b\n%b\n%b" "$line1" "$line2" "$line3"

exit 0
