# Three lines:
#   Line 1: [🧠] Model | ai-title | ✓ done/total | session-duration
#   Line 2: [⚡] Effort Tokens | 45% ████░░░░ H 21:00 | 23% ████░░░░ W 03/20 14:00 | E $5/$50
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
$white  = "${esc}[38;2;220;220;220m"
$dim    = "${esc}[2m"
$reset  = "${esc}[0m"

# Format token counts (e.g., 50k / 200k)
function Format-Tokens([long]$num) {
    if ($num -ge 1000000) { return "{0:F1}m" -f ($num / 1000000) }
    elseif ($num -ge 1000) { return "{0:F0}k" -f ($num / 1000) }
    else { return "$num" }
}

# Format number with commas (e.g., 134,938)
function Format-Commas([long]$num) {
    return $num.ToString("N0")
}

# Format duration ms → human readable (e.g., 8m13s, 2h05m, 45s)
function Format-Duration([long]$ms) {
    $totalS = [math]::Floor($ms / 1000)
    $h = [math]::Floor($totalS / 3600)
    $m = [math]::Floor(($totalS % 3600) / 60)
    $s = $totalS % 60
    if ($h -gt 0)    { return "{0}h{1:D2}m" -f $h, $m }
    elseif ($m -gt 0) { return "{0}m{1:D2}s" -f $m, $s }
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

# ===== Extract data from JSON =====
$data = $input | ConvertFrom-Json

$modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
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

# Check reasoning effort
$effortLevel = "medium"
if ($env:CLAUDE_CODE_EFFORT_LEVEL) {
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

# ===== AI-generated session title (from transcript) =====
$aiTitle = ""
if ($transcriptPath -and (Test-Path $transcriptPath)) {
    try {
        $lastAiTitleLine = Select-String -Path $transcriptPath -Pattern '"type":"ai-title"' -SimpleMatch |
            Select-Object -Last 1
        if ($lastAiTitleLine) {
            $obj = $lastAiTitleLine.Line | ConvertFrom-Json
            if ($obj.aiTitle) { $aiTitle = $obj.aiTitle }
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
    default  { $line2 += "${green}high${reset} " }
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

# ===== Usage limits with caching =====
$cacheDir = Join-Path $env:TEMP "claude"
$cacheFile = Join-Path $cacheDir "statusline-usage-cache.json"
$cacheMaxAge = 60  # seconds between API calls

if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

$needsRefresh = $true
$usageData = $null

# Check cache
if (Test-Path $cacheFile) {
    $cacheMtime = (Get-Item $cacheFile).LastWriteTime
    $cacheAge = ((Get-Date) - $cacheMtime).TotalSeconds
    if ($cacheAge -lt $cacheMaxAge) {
        $needsRefresh = $false
        $usageData = Get-Content $cacheFile -Raw
    }
}

# Fetch fresh data if cache is stale
if ($needsRefresh) {
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
            $usageData = $response | ConvertTo-Json -Depth 10
            $usageData | Set-Content $cacheFile -Force
        } catch {}
    }
    # Fall back to stale cache
    if (-not $usageData -and (Test-Path $cacheFile)) {
        $usageData = Get-Content $cacheFile -Raw
    }
}

# Format ISO reset time to compact local time
function Format-ResetTime([string]$isoStr, [string]$style) {
    if (-not $isoStr -or $isoStr -eq "null") { return $null }
    try {
        $dt = [DateTimeOffset]::Parse($isoStr).LocalDateTime
        switch ($style) {
            "time"     { return $dt.ToString("HH:mm") }
            "datetime" { return $dt.ToString("MM/dd HH:mm") }
            default    { return $dt.ToString("MM/dd") }
        }
    } catch { return $null }
}

$sep = " ${dim}|${reset} "

if ($usageData) {
    try {
        $usage = if ($usageData -is [string]) { $usageData | ConvertFrom-Json } else { $usageData }

        # ---- 5-hour (current) ----
        $fiveHourPct = [math]::Floor([double](Coalesce $usage.five_hour.utilization 0))
        $fiveHourResetIso = $usage.five_hour.resets_at
        $fiveHourReset = Format-ResetTime $fiveHourResetIso "time"
        $fiveHourColor = Get-UsageColor $fiveHourPct

        $fiveHourBar = Get-ProgressBar $fiveHourPct 8 $fiveHourColor
        $line2 += "${sep}${fiveHourColor}${fiveHourPct}%${reset} ${fiveHourBar} ${white}H${reset}"
        if ($fiveHourReset) { $line2 += " ${dim}${fiveHourReset}${reset}" }

        # ---- 7-day (weekly) ----
        $sevenDayPct = [math]::Floor([double](Coalesce $usage.seven_day.utilization 0))
        $sevenDayResetIso = $usage.seven_day.resets_at
        $sevenDayReset = Format-ResetTime $sevenDayResetIso "datetime"
        $sevenDayColor = Get-UsageColor $sevenDayPct

        $sevenDayBar = Get-ProgressBar $sevenDayPct 8 $sevenDayColor
        $line2 += "${sep}${sevenDayColor}${sevenDayPct}%${reset} ${sevenDayBar} ${white}W${reset}"
        if ($sevenDayReset) { $line2 += " ${dim}${sevenDayReset}${reset}" }

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
} else {
    # No valid usage data - show placeholders
    $line2 += "${sep}${dim}-% ░░░░░░░░${reset} ${white}H${reset}"
    $line2 += "${sep}${dim}-% ░░░░░░░░${reset} ${white}W${reset}"
}

# ===== Multi-line memo (set via /setmemo) =====
# Lookup order:
#   1. session-<session_id>.txt  — explicit session-scoped memo (/setmemo --session …)
#   2. cwd-<hash>.txt            — directory-scoped memo (/setmemo …), survives /clear
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
