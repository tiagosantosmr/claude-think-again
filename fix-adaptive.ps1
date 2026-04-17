# fix-adaptive.ps1
# Patches Claude Code's cli.js to replace type:"adaptive" with forced thinking.
# Works across versions by using regex to match minified variable names.

$ErrorActionPreference = "Stop"

Write-Host "=== Claude Code Adaptive Thinking Patcher ===" -ForegroundColor Cyan
Write-Host ""

# --- Find cli.js ---
$CliJs = $null

# Method 1: via Get-Command
try {
    $claudeCmd = Get-Command claude -ErrorAction Stop
    $claudeDir = Split-Path $claudeCmd.Source -Parent
    $candidate = Join-Path $claudeDir "node_modules\@anthropic-ai\claude-code\cli.js"
    if (Test-Path $candidate) {
        $CliJs = $candidate
    }
} catch {
    # claude not in PATH, try fallbacks
}

# Method 2: common Windows install paths
if (-not $CliJs) {
    $searchPaths = @(
        "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code\cli.js"
        "$env:LOCALAPPDATA\npm\node_modules\@anthropic-ai\claude-code\cli.js"
        "$env:USERPROFILE\.claude\local\node_modules\@anthropic-ai\claude-code\cli.js"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $CliJs = $path
            break
        }
    }
}

if (-not $CliJs) {
    # Check if this is a binary install (official install script)
    $binaryInstall = $null
    try {
        $claudePath = (Get-Command claude -ErrorAction Stop).Source
        $resolved = (Get-Item $claudePath -ErrorAction Stop).Target
        if (-not $resolved) { $resolved = $claudePath }
        if ($resolved -match "\.local[\\/]share[\\/]claude" -or $resolved -match "[\\/]versions[\\/]") {
            $binaryInstall = $resolved
        }
    } catch {}

    if ($binaryInstall) {
        Write-Host "Detected binary install (official install script):" -ForegroundColor Yellow
        Write-Host "  $binaryInstall"
        Write-Host ""
        Write-Host "Binary installs ship a compiled binary, not a patchable cli.js."
        Write-Host "The cli.js patching cannot be applied to this installation."
        Write-Host ""
        Write-Host "Setting the env var instead (covers the main API path)..."

        $currentVal = [System.Environment]::GetEnvironmentVariable("CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING", "User")
        if ($currentVal -eq "1") {
            Write-Host "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING already set in user environment." -ForegroundColor Green
        } else {
            [System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING", "1", "User")
            $env:CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
            Write-Host "Set CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1 in user environment." -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "Note: The env var only covers 1 of 4 code paths." -ForegroundColor Yellow
        Write-Host "For full patching, reinstall via: npm install -g @anthropic-ai/claude-code" -ForegroundColor Yellow
        exit 0
    }

    Write-Host "ERROR: Could not find cli.js" -ForegroundColor Red
    Write-Host "Make sure Claude Code is installed and 'claude' is in your PATH."
    exit 1
}

Write-Host "Found cli.js at: $CliJs" -ForegroundColor Green

# --- Read file ---
$content = Get-Content $CliJs -Raw

# --- Count occurrences ---
$matches = [regex]::Matches($content, [regex]::Escape('{type:"adaptive"}'))
$count = $matches.Count
Write-Host "Found $count occurrence(s) of type:`"adaptive`""

if ($count -eq 0) {
    Write-Host "No adaptive thinking patterns found. Already patched or unsupported version." -ForegroundColor Yellow
    exit 0
}

# --- Backup ---
$backup = "$CliJs.bak"
Copy-Item $CliJs $backup -Force
Write-Host ""
Write-Host "[BACKUP] Original cli.js saved to:" -ForegroundColor Green
Write-Host "  $backup"
Write-Host "[BACKUP] You can restore the original at any time (see end of output)." -ForegroundColor Green
Write-Host ""

# --- Patch 1: Main API path ---
# Replace the condition before {type:"adaptive"} on the main path with !1
# Pattern: !VAR(process.env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING)&&VAR(VAR.model)
Write-Host "Patch 1: Forcing main API path to use model-specific thinking budget..."
$mainPathRegex = '![a-zA-Z0-9$_]+\(process\.env\.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING\)&&[a-zA-Z0-9$_]+\([a-zA-Z0-9$_]+\.model\)'
$content = [regex]::Replace($content, $mainPathRegex, '!1')

# --- Patch 2: All remaining {type:"adaptive"} ---
# Replace with {type:"enabled",budget_tokens:10000}
Write-Host "Patch 2: Replacing remaining adaptive patterns with enabled + fixed budget..."
$content = $content.Replace('{type:"adaptive"}', '{type:"enabled",budget_tokens:10000}')

# --- Write patched file ---
[System.IO.File]::WriteAllText($CliJs, $content)

# --- Patch 3: Set env var persistently ---
$currentVal = [System.Environment]::GetEnvironmentVariable("CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING", "User")
if ($currentVal -eq "1") {
    Write-Host "Patch 3: CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING already set in user environment."
} else {
    [System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING", "1", "User")
    $env:CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
    Write-Host "Patch 3: Set CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1 in user environment." -ForegroundColor Green
}

# --- Verify ---
$remaining = ([regex]::Matches($content, [regex]::Escape('{type:"adaptive"}'))).Count
Write-Host ""
if ($remaining -eq 0) {
    $patched = ([regex]::Matches($content, [regex]::Escape('budget_tokens:10000'))).Count
    Write-Host "SUCCESS: All adaptive thinking patterns patched." -ForegroundColor Green
    Write-Host "  $patched replacement(s) applied."
} else {
    Write-Host "WARNING: $remaining pattern(s) remain unpatched. Manual inspection needed." -ForegroundColor Red
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host "[BACKUP] Your original cli.js is backed up at:" -ForegroundColor Green
Write-Host "  $backup"
Write-Host "[BACKUP] To restore, run:" -ForegroundColor Green
Write-Host "  Copy-Item `"$backup`" `"$CliJs`" -Force" -ForegroundColor Yellow
Write-Host "===========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Auto-updates will overwrite this patch. Re-run after updating Claude Code." -ForegroundColor Yellow
Write-Host "Note: This patch has no effect on Opus 4.7, which only supports adaptive thinking." -ForegroundColor Yellow
Write-Host "      For Opus 4.7, use effort levels (low/medium/high/xhigh) to control reasoning depth." -ForegroundColor Yellow
