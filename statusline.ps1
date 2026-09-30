# Three lines:
#   Line 1: [🧠] Model | ai-title | ✓ done/total | session-duration
#   Line 2: [⚡] Effort Tokens | 45% ████░░░░ H 2H 05m left | 23% ████░░░░ W Fri 03/20 14:00 | E $5/$50
#   Line 3: Dir | Branch changes | vX.Y.Z

# Read input from stdin
$input = @($Input) -join "`n"

if (-not $input) {
    Write-Host -NoNewline "Claude"
    exit 0
}

# ANSI escape - use [char]0x1b for PowerShell 5 compatibility ("`e" is PS7+ only)
$esc = [char]0x1b

# ANSI colors matching oh-my-posh theme
$blue   = "${esc}[38;2;0;153;255m"
$orange = "${esc}[38;2;255;176;85m"
$green  = "${esc}[38;2;0;160;0m"
$cyan   = "${esc}[38;2;46;149;153m"
$red    = "${esc}[38;2;255;85;85m"
$yellow = "${esc}[38;2;230;200;0m"
$purple = "${esc}[38;2;167;139;250m"
$white  = "${esc}[38;2;220;220;220m"
$dim    = "${esc}[2m"
$reset  = "${esc}[0m"

# Format token counts (e.g., 50k / 200k)
function Format-Tokens([long]$num) {
    if ($num -ge 1000000) {
        # Drop a trailing .0 so 1,000,000 reads "1m" rather than "1.0m"
        $val = [math]::Round($num / 1000000, 1)
        if ($val -eq [math]::Floor($val)) { return "{0:F0}m" -f $val }
        return "{0:F1}m" -f $val
    }
    elseif ($num -ge 1000) { return "{0:F0}k" -f ($num / 1000) }
    else { return "$num" }
}

# Format number with commas (e.g., 134,938)
function Format-Commas([long]$num) {
    return $num.ToString("N0")
}

# Format duration ms → human readable (e.g., 8m 13s, 2H 05m, 45s)
function Format-Duration([long]$ms) {
    $totalS = [math]::Floor($ms / 1000)
    $h = [math]::Floor($totalS / 3600)
    $m = [math]::Floor(($totalS % 3600) / 60)
    $s = $totalS % 60
    if ($h -gt 0)    { return "{0}H {1:D2}m" -f $h, $m }
    elseif ($m -gt 0) { return "{0}m {1:D2}s" -f $m, $s }
    else              { return "{0}s" -f $s }
}

# Return color escape based on usage percentage
function Get-UsageColor([int]$pct) {
    if ($pct -ge 90) { return $red }
    elseif ($pct -ge 70) { return $orange }
    elseif ($pct -ge 50) { return $yellow }
    else { return $green }
}

# Generate progress bar
function Get-ProgressBar([int]$pct, [int]$width = 10, [string]$color) {
    $filled = [math]::Floor($pct * $width / 100)
    $empty = $width - $filled
    $bar = ("█" * $filled) + ("░" * $empty)
    return "${color}${bar}${reset}"
}

# Null coalescing helper for PowerShell 5 compatibility (?? is PS7+ only)
function Coalesce($value, $default) {
    if ($null -ne $value) { return $value } else { return $default }
}

# First 16 hex chars of SHA-256 (used for per-cwd memo and per-config-dir cache keys)
function Get-ShaShort16([string]$value) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
    return $hex.Substring(0, 16)
}

# ===== Extract data from JSON =====
$data = $input | ConvertFrom-Json

$modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
$modelName = ($modelName -replace '\s*\((\d+\.?\d*[kKmM])\s+context\)', ' $1').Trim()  # "(1M context)" → "1M"
$sessionId = $data.session_id
$ccVersion = $data.version
$thinkingEnabled = ($data.thinking.enabled -eq $true)
$fastMode = ($data.fast_mode -eq $true)
$totalDurationMs = if ($data.cost.total_duration_ms) { [long]$data.cost.total_duration_ms } else { 0 }
$transcriptPath = $data.transcript_path

# Context window
$size = if ($data.context_window.context_window_size) { [long]$data.context_window.context_window_size } else { 200000 }
if ($size -eq 0) { $size = 200000 }

# Token usage
$inputTokens = if ($data.context_window.current_usage.input_tokens) { [long]$data.context_window.current_usage.input_tokens } else { 0 }
$cacheCreate = if ($data.context_window.current_usage.cache_creation_input_tokens) { [long]$data.context_window.current_usage.cache_creation_input_tokens } else { 0 }
$cacheRead   = if ($data.context_window.current_usage.cache_read_input_tokens) { [long]$data.context_window.current_usage.cache_read_input_tokens } else { 0 }
$current = $inputTokens + $cacheCreate + $cacheRead

$usedTokens  = Format-Tokens $current
$totalTokens = Format-Tokens $size

if ($size -gt 0) {
    $pctUsed = [math]::Floor($current * 100 / $size)
} else {
    $pctUsed = 0
}
$pctRemain = 100 - $pctUsed

$usedComma   = Format-Commas $current
$remainComma = Format-Commas ($size - $current)

# Config directory (respects CLAUDE_CONFIG_DIR override)
$claudeConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }

# Check reasoning effort (prefer the live level Claude Code passes on stdin)
$effortLevel = "medium"
if ($data.effort.level) {
    $effortLevel = $data.effort.level
} elseif ($env:CLAUDE_CODE_EFFORT_LEVEL) {
    $effortLevel = $env:CLAUDE_CODE_EFFORT_LEVEL
} else {
    $settingsPath = Join-Path $claudeConfigDir "settings.json"
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($settings.effortLevel) { $effortLevel = $settings.effortLevel }
        } catch {}
    }
}

# ===== Session title (from transcript: /rename custom-title, else ai-title) =====
$aiTitle = ""
if ($transcriptPath -and (Test-Path $transcriptPath)) {
    try {
        # Prefer the user-set /rename title (custom-title) over the auto-generated ai-title
        $lastCustomTitleLine = Select-String -Path $transcriptPath -Pattern '"type":"custom-title"' -SimpleMatch |
            Select-Object -Last 1
        if ($lastCustomTitleLine) {
            $obj = $lastCustomTitleLine.Line | ConvertFrom-Json
            if ($obj.customTitle) { $aiTitle = $obj.customTitle }
        }
        if (-not $aiTitle) {
            $lastAiTitleLine = Select-String -Path $transcriptPath -Pattern '"type":"ai-title"' -SimpleMatch |
                Select-Object -Last 1
            if ($lastAiTitleLine) {
                $obj = $lastAiTitleLine.Line | ConvertFrom-Json
                if ($obj.aiTitle) { $aiTitle = $obj.aiTitle }
            }
        }
    } catch {}
}

# ===== Todo progress (done/total from latest session todo file) =====
$todoProgress = ""
$todosDir = Join-Path $claudeConfigDir "todos"
if ($sessionId -and (Test-Path $todosDir)) {
    try {
        $todoFiles = Get-ChildItem -Path $todosDir -Filter "${sessionId}-agent-*.json" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($todoFiles) {
            $todos = @(Get-Content $todoFiles.FullName -Raw | ConvertFrom-Json)
            $todoTotal = $todos.Count
            $todoDone = @($todos | Where-Object { $_.status -eq "completed" }).Count
            if ($todoTotal -gt 0) {
                $todoProgress = "${todoDone}/${todoTotal}"
            }
        }
    } catch {}
}

# ===== Build three-line output =====
$line1 = ""
$line2 = ""
$line3 = ""

# Line 1: [🧠] Model | ai-title | ✓ todo | duration
if ($thinkingEnabled) { $line1 += "🧠 " }
$line1 += "${dim}${modelName}${reset}"
if ($aiTitle) {
    if ($aiTitle.Length -gt 50) {
        $aiTitle = $aiTitle.Substring(0, 47) + "..."
    }
    $line1 += " ${dim}|${reset} ${white}${aiTitle}${reset}"
}
if ($todoProgress) {
    $line1 += " ${dim}|${reset} ${cyan}✓ ${todoProgress}${reset}"
}
if ($totalDurationMs -gt 0) {
    $line1 += " ${dim}|${reset} ${dim}$(Format-Duration $totalDurationMs)${reset}"
}

# Current working directory and git info
$cwd = $data.cwd
$displayDir = ""
$gitBranch = $null
$gitStat = ""

if ($cwd) {
    $displayDir = Split-Path $cwd -Leaf
    try {
        $gitBranch = git -C $cwd rev-parse --abbrev-ref HEAD 2>$null
    } catch {}
    if ($gitBranch) {
        try {
            $numstat = git -C $cwd diff --numstat 2>$null
            if ($numstat) {
                $added = 0; $deleted = 0
                foreach ($line in $numstat) {
                    $parts = $line -split '\s+'
                    if ($parts[0] -match '^\d+$') { $added += [int]$parts[0] }
                    if ($parts[1] -match '^\d+$') { $deleted += [int]$parts[1] }
                }
                if (($added + $deleted) -gt 0) {
                    $gitStat = "+${added} -${deleted}"
                }
            }
        } catch {}
    }
}

# Line 2: [⚡] Effort Tokens | H | W | Extra
if ($fastMode) { $line2 += "⚡ " }
switch ($effortLevel) {
    "low"    { $line2 += "${dim}low${reset} " }
    "medium" { $line2 += "${orange}med${reset} " }
    "high"   { $line2 += "${green}high${reset} " }
    "xhigh"  { $line2 += "${purple}xhigh${reset} " }
    "max"    { $line2 += "${red}max${reset} " }
    default  { $line2 += "${dim}${effortLevel}${reset} " }
}
$line2 += "${orange}${usedTokens}/${totalTokens}${reset}"

# Line 3: Dir | Branch changes
if ($displayDir) {
    $line3 += "${cyan}${displayDir}${reset}"
}

if ($gitBranch) {
    if ($line3) { $line3 += " ${dim}|${reset} " }
    $line3 += "${green}${gitBranch}${reset}"
    if ($gitStat) {
        $parts = $gitStat -split ' '
        $line3 += " ${green}$($parts[0])${reset} ${red}$($parts[1])${reset}"
    }
}

# Custom per-session message (set via /setmsg slash command)
if ($sessionId) {
    $sessionMsgFile = Join-Path $claudeConfigDir "cache\statusline-msg\${sessionId}.txt"
    if (Test-Path $sessionMsgFile) {
        try {
            $sessionMsg = (Get-Content -LiteralPath $sessionMsgFile -Raw -ErrorAction Stop)
        } catch { $sessionMsg = "" }
        if ($sessionMsg) {
            if ($sessionMsg.Length -gt 60) {
                $sessionMsg = $sessionMsg.Substring(0, 57) + "..."
            }
            if ($line3) { $line3 += " ${dim}|${reset} " }
            $line3 += "${white}${sessionMsg}${reset}"
        }
    }
}

# Append Claude Code version to end of line 3
if ($ccVersion) {
    if ($line3) { $line3 += " ${dim}|${reset} " }
    $line3 += "${dim}v${ccVersion}${reset}"
}

# ===== OAuth token resolution =====
function Get-OAuthToken {
    # 1. Explicit env var override
    if ($env:CLAUDE_CODE_OAUTH_TOKEN) {
        return $env:CLAUDE_CODE_OAUTH_TOKEN
    }

    # 2. Windows Credential Manager (via cmdkey/CredentialManager)
    try {
        if (Get-Command "cmdkey.exe" -ErrorAction SilentlyContinue) {
            # Try reading from Windows Credential Manager using PowerShell
            $credPath = Join-Path $env:LOCALAPPDATA "Claude Code\credentials.json"
            if (Test-Path $credPath) {
                $creds = Get-Content $credPath -Raw | ConvertFrom-Json
                $token = $creds.claudeAiOauth.accessToken
                if ($token -and $token -ne "null") { return $token }
            }
        }
    } catch {}

    # 3. Credentials file (cross-platform fallback)
    $credsFile = Join-Path $claudeConfigDir ".credentials.json"
    if (Test-Path $credsFile) {
        try {
            $creds = Get-Content $credsFile -Raw | ConvertFrom-Json
            $token = $creds.claudeAiOauth.accessToken
            if ($token -and $token -ne "null") { return $token }
        } catch {}
    }

    return $null
}

# ===== Usage limits (line 2) =====
# Sources, in order of preference:
#   1. rate_limits in Claude Code's stdin JSON - live, needs no OAuth token or network
#   2. Whichever is newer of the last stdin snapshot and the OAuth usage API cache
# The API is still polled (throttled to cacheMaxAge) even when stdin has rate_limits,
# because extra_usage is only exposed there. Cache files are keyed by config dir so
# accounts run via different CLAUDE_CONFIG_DIRs don't overwrite each other.
$cacheDir = Join-Path $env:TEMP "claude"
$cacheKey = Get-ShaShort16 $claudeConfigDir
$cacheFile = Join-Path $cacheDir "statusline-usage-cache-${cacheKey}.json"
$builtinCacheFile = Join-Path $cacheDir "statusline-usage-builtin-${cacheKey}.json"
$cacheMaxAge = 60  # seconds between API calls

if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

# Parse a usage cache file; $null when missing, empty, or not usage-shaped
function Read-UsageFile([string]$path) {
    try {
        $u = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($u.five_hour -or $u.seven_day) { return $u }
    } catch {}
    return $null
}

$needsRefresh = $true
$usage = $null

# Check cache - shared across all Claude Code instances to avoid rate limits
if ((Test-Path $cacheFile) -and (Get-Item $cacheFile).Length -gt 0) {
    $cacheAge = ((Get-Date) - (Get-Item $cacheFile).LastWriteTime).TotalSeconds
    if ($cacheAge -lt $cacheMaxAge) { $needsRefresh = $false }
    $usage = Read-UsageFile $cacheFile
}

# Fetch fresh data if cache is stale
if ($needsRefresh) {
    # Touch cache immediately so other instances don't also fetch
    try {
        if (Test-Path $cacheFile) { (Get-Item $cacheFile).LastWriteTime = Get-Date }
        else { New-Item -ItemType File -Path $cacheFile -Force | Out-Null }
    } catch {}

    $token = Get-OAuthToken
    if ($token) {
        try {
            $headers = @{
                "Accept"         = "application/json"
                "Content-Type"   = "application/json"
                "Authorization"  = "Bearer $token"
                "anthropic-beta" = "oauth-2025-04-20"
                "User-Agent"     = "claude-code/2.1.34"
            }
            $response = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" `
                -Headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop
            # Only cache valid usage responses (not error/rate-limit JSON)
            if ($response.five_hour) {
                $response | ConvertTo-Json -Depth 10 | Set-Content $cacheFile -Force
                $usage = $response
            }
        } catch {}
    }

    # A failed fetch leaves the touched lock file empty - remove it so the next render
    # retries instead of waiting out a full cacheMaxAge window.
    if ((Test-Path $cacheFile) -and (Get-Item $cacheFile).Length -eq 0) {
        Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
    }
}

# Convert one stdin rate_limits window to the API response shape (epoch resets_at → ISO)
function Convert-RateLimitWindow($w) {
    if ($null -eq $w -or $null -eq $w.used_percentage) { return $null }
    $resetsAt = $null
    try {
        if ([long]$w.resets_at -gt 0) {
            $resetsAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$w.resets_at).ToString(
                "yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
        }
    } catch {}
    return [pscustomobject]@{ utilization = [double]$w.used_percentage; resets_at = $resetsAt }
}

# All-zero percentages with no reset times usually mean Claude Code failed to fetch its
# limits, so ignore stdin then and fall back to the caches. A genuine 0% right after a
# reset still carries resets_at and is trusted.
$rateLimits = $data.rate_limits
$effectiveBuiltin = $false
foreach ($w in @($rateLimits.five_hour, $rateLimits.seven_day)) {
    if ($null -eq $w -or $null -eq $w.used_percentage) { continue }
    try {
        if ([double]$w.used_percentage -gt 0 -or [long]$w.resets_at -gt 0) { $effectiveBuiltin = $true }
    } catch {}
}

if ($effectiveBuiltin) {
    # A window missing from stdin is filled from the API cache; extra_usage always is
    $builtinUsage = [pscustomobject]@{
        five_hour   = Coalesce (Convert-RateLimitWindow $rateLimits.five_hour) $usage.five_hour
        seven_day   = Coalesce (Convert-RateLimitWindow $rateLimits.seven_day) $usage.seven_day
        extra_usage = $usage.extra_usage
    }
    $usage = $builtinUsage
    # Snapshot for renders where stdin rate_limits come back missing or zeroed
    try { $builtinUsage | ConvertTo-Json -Depth 10 -Compress | Set-Content $builtinCacheFile -Force } catch {}
} elseif (Test-Path $builtinCacheFile) {
    if (-not $usage -or -not (Test-Path $cacheFile) -or
        (Get-Item $builtinCacheFile).LastWriteTime -gt (Get-Item $cacheFile).LastWriteTime) {
        $snapshot = Read-UsageFile $builtinCacheFile
        if ($snapshot) { $usage = $snapshot }
    }
}

# Reset time display style (set via settings.json → "env": {"STATUSLINE_RESET_STYLE": "clock"})
#   countdown (default) - within 24h of a reset, show time left ("4H 12m left");
#                         further out, fall back to the clock time (weekly: "Mon 10/05 17:59")
#   clock               - always show the clock time (5-hour: "21:00", weekly: "Mon 10/05 17:59")
$resetStyle = if ($env:STATUSLINE_RESET_STYLE) { $env:STATUSLINE_RESET_STYLE } else { "countdown" }
$countdownWindowSec = 86400

# Format seconds until reset as "4H 12m left" / "35m left"
# Minutes round up so the last partial minute still reads "1m left".
function Format-TimeLeft([long]$secs) {
    if ($secs -lt 0) { $secs = 0 }
    $totalM = [long][math]::Floor(($secs + 59) / 60)
    $h = [long][math]::Floor($totalM / 60)
    $m = $totalM % 60
    if ($h -gt 0) { return "{0}H {1:D2}m left" -f $h, $m }
    else          { return "{0}m left" -f $m }
}

# Format ISO reset time to compact local time (or time left, in countdown style)
# (PS7's ConvertFrom-Json turns ISO strings into DateTime, so accept either)
function Format-ResetTime($resetsAt, [string]$style) {
    if (-not $resetsAt -or "$resetsAt" -eq "null") { return $null }
    try {
        $resetAt = if ($resetsAt -is [datetime]) { [DateTimeOffset]$resetsAt } else { [DateTimeOffset]::Parse("$resetsAt") }
        if ($resetStyle -ne "clock") {
            $secsLeft = [long][math]::Floor(($resetAt - [DateTimeOffset]::Now).TotalSeconds)
            if ($secsLeft -lt $countdownWindowSec) { return Format-TimeLeft $secsLeft }
        }
        $dt = $resetAt.LocalDateTime
        switch ($style) {
            "time"     { return $dt.ToString("HH:mm") }
            "datetime" { return $dt.ToString("ddd MM/dd HH:mm", [System.Globalization.CultureInfo]::InvariantCulture) }
            default    { return $dt.ToString("MM/dd") }
        }
    } catch { return $null }
}

$sep = " ${dim}|${reset} "

# Append one rate-limit window ("45% ████░░░░ H 2H 05m left"), or a placeholder when
# the current source has no data for it
function Format-UsageWindow($window, [string]$label, [string]$style) {
    if ($null -eq $window -or $null -eq $window.utilization) {
        return "${sep}${dim}-% ░░░░░░░░${reset} ${white}${label}${reset}"
    }
    $pct = [math]::Floor([double]$window.utilization)
    $resetStr = Format-ResetTime $window.resets_at $style
    $color = Get-UsageColor $pct

    $bar = Get-ProgressBar $pct 8 $color
    $segment = "${sep}${color}${pct}%${reset} ${bar} ${white}${label}${reset}"
    if ($resetStr) { $segment += " ${dim}${resetStr}${reset}" }
    return $segment
}

$line2 += Format-UsageWindow $usage.five_hour "H" "time"      # 5-hour (current)
$line2 += Format-UsageWindow $usage.seven_day "W" "datetime"  # 7-day (weekly)

try {
    # ---- Extra usage ----
    $extraEnabled = $usage.extra_usage.is_enabled
    if ($extraEnabled -eq $true) {
        $extraPct = [math]::Floor([double](Coalesce $usage.extra_usage.utilization 0))
        $extraUsedRaw = $usage.extra_usage.used_credits
        $extraLimitRaw = $usage.extra_usage.monthly_limit

        if ($null -ne $extraUsedRaw -and $null -ne $extraLimitRaw) {
            $extraUsed = "{0:F2}" -f ([double]$extraUsedRaw / 100)
            $extraLimit = "{0:F2}" -f ([double]$extraLimitRaw / 100)
            $extraColor = Get-UsageColor $extraPct
            $extraBar = Get-ProgressBar $extraPct 6 $extraColor
            $line2 += "${sep}${extraColor}${extraPct}%${reset} ${extraBar} ${white}E${reset} ${dim}`$${extraUsed}/`$${extraLimit}${reset}"
        } else {
            $line2 += "${sep}${white}E${reset} ${green}on${reset}"
        }
    }
} catch {}

# ===== Multi-line memo (set via /setmemo) =====
# Lookup order:
#   1. session-<session_id>.txt  — explicit session-scoped memo (/setmemo --session …)
#   2. cwd-<hash>.txt            — directory-scoped memo (/setmemo …), survives /clear

$memoLines = ""
$memoFile = $null
if ($sessionId) {
    $candidate = Join-Path $claudeConfigDir "cache\statusline-memo\session-${sessionId}.txt"
    if (Test-Path $candidate) { $memoFile = $candidate }
}
if (-not $memoFile -and $cwd) {
    $cwdKey = Get-ShaShort16 $cwd
    $candidate = Join-Path $claudeConfigDir "cache\statusline-memo\cwd-${cwdKey}.txt"
    if (Test-Path $candidate) { $memoFile = $candidate }
}
if ($memoFile) {
    $memoCount = 0
    foreach ($memoLine in (Get-Content -LiteralPath $memoFile)) {
        $memoCount++
        if ($memoCount -gt 20) {
            $memoLines += "`n${dim}│ … (memo truncated)${reset}"
            break
        }
        if ($memoLine.Length -gt 100) {
            $memoLine = $memoLine.Substring(0, 97) + "..."
        }
        $memoLines += "`n${dim}│ ${memoLine}${reset}"
    }
}

# Output three lines + optional memo rows
Write-Host -NoNewline "${line1}`n${line2}`n${line3}"
if ($memoLines) { Write-Host -NoNewline $memoLines }
Write-Host ""

exit 0
