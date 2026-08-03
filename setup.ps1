#Requires -Version 5.1
<#
.SYNOPSIS
    IFE Claude Code Setup for Windows
.DESCRIPTION
    Installs dependencies and configures AWS Bedrock SSO access.
    Idempotent — safe to re-run any time; only changes what's out of date.
.NOTES
    Usage:
        irm https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/setup.ps1 | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── IFE Configuration ─────────────────────────────────────────────────────────
$SSO_START_URL  = "https://d-c3677f1bbd.awsapps.com/start"
$SSO_REGION     = "eu-north-1"
$SSO_ROLE_NAME  = "BedrockUserAccess"
$PROFILE_NAME   = "ife"
$AWS_REGION_VAL = "eu-north-1"

# ── Output helpers ────────────────────────────────────────────────────────────
function Ok($msg)     { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Skip($msg)   { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }
function Info($msg)   { Write-Host "  [...]  $msg" -ForegroundColor Cyan }
function Fail($msg)   { Write-Host "`n  [ERR]  $msg`n" -ForegroundColor Red; exit 1 }
function Header($msg) { Write-Host "`n$("─" * 54)`n  $msg`n$("─" * 54)" -ForegroundColor Blue }

# PS 5.1's Set-Content -Encoding UTF8 writes a BOM, which breaks the AWS CLI
# config parser ("Unable to parse config file"). Write plain UTF-8 instead.
function Write-Utf8NoBom($Path, $Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# ── Intro ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  IFE Claude Code Setup" -ForegroundColor White
Write-Host "  ──────────────────────────────────────────────────────"
Write-Host "  Installs dependencies and configures AWS Bedrock SSO."
Write-Host "  Idempotent — safe to re-run any time."
Write-Host "  ──────────────────────────────────────────────────────"
Write-Host ""

# ── Winget check ──────────────────────────────────────────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "winget is required but was not found.`n  Install 'App Installer' from the Microsoft Store and re-run this script."
}

# ── Phase 1: Dependencies ─────────────────────────────────────────────────────
Header "Phase 1 / 4  —  Dependencies"

# Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    Skip "Node.js already installed  ($(node --version))"
} else {
    Info "Installing Node.js..."
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
    Ok "Node.js installed"
}

# AWS CLI
if (Get-Command aws -ErrorAction SilentlyContinue) {
    Skip "AWS CLI already installed  ($(aws --version 2>&1 | Select-String 'aws-cli' | ForEach-Object { $_.Line.Split(' ')[0] }))"
} else {
    Info "Installing AWS CLI..."
    winget install --id Amazon.AWSCLI --accept-source-agreements --accept-package-agreements --silent
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
    Ok "AWS CLI installed"
}

# Claude Code
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $currentVersion = (claude --version 2>$null) -split ' ' | Select-Object -First 1
    $latestVersion = npm view @anthropic-ai/claude-code version 2>$null
    if ($latestVersion -and $currentVersion -eq $latestVersion) {
        Skip "Claude Code already up to date  (v$currentVersion)"
    } else {
        Info "Updating Claude Code ($currentVersion -> $(if ($latestVersion) { $latestVersion } else { 'latest' }))..."
        npm install -g @anthropic-ai/claude-code
        Ok "Claude Code updated"
    }
} else {
    Info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    Ok "Claude Code installed"
}

# ── Phase 2: AWS SSO Session Config ───────────────────────────────────────────
Header "Phase 2 / 4  —  AWS SSO Configuration"

$awsDir     = Join-Path $env:USERPROFILE ".aws"
$configPath = Join-Path $awsDir "config"

if (-not (Test-Path $awsDir)) {
    New-Item -ItemType Directory -Path $awsDir | Out-Null
}

# Writes/updates only the [sso-session ife] block, leaving all other
# profiles/sessions untouched. Skips the write if already up to date.
$existingContent = if (Test-Path $configPath) { Get-Content $configPath -Raw } else { "" }
if (-not $existingContent) { $existingContent = "" }

$newSsoBlock = @"
[sso-session ife]
sso_start_url = $SSO_START_URL
sso_region = $SSO_REGION
sso_registration_scopes = sso:account:access
"@.Trim()

$existingSsoMatch = [regex]::Match($existingContent, '(?s)\[sso-session ife\][^\[]*')
$existingSsoBlock = if ($existingSsoMatch.Success) { $existingSsoMatch.Value.Trim() } else { $null }

if ($existingSsoBlock -eq $newSsoBlock) {
    Skip "SSO session already up to date ($configPath)"
} else {
    $stripped = $existingContent -replace '(?s)\[sso-session ife\][^\[]*', ''
    $stripped = $stripped -replace '(\r?\n){3,}', "`n`n"
    $stripped = $stripped.Trim()
    $finalContent = (($stripped + "`n`n" + $newSsoBlock).Trim()) + "`n"
    Write-Utf8NoBom -Path $configPath -Content $finalContent
    Ok "SSO session written ($configPath)"
}

# ── Phase 3: SSO Login & Account Verification ─────────────────────────────────
Header "Phase 3 / 4  —  SSO Login"

$ACCOUNT_ID = $null
try {
    $identity = aws sts get-caller-identity --profile $PROFILE_NAME 2>$null | ConvertFrom-Json
    $ACCOUNT_ID = $identity.Account
    Skip "Already authenticated as: $($identity.Arn)"
} catch {
    Write-Host ""
    Write-Host "  A browser window will open for you to log in with your" -ForegroundColor White
    Write-Host "  IFE Microsoft credentials." -ForegroundColor White
    Write-Host "  Return here after completing authentication in the browser."
    Write-Host ""
    Read-Host "  Press Enter to open the browser login"
    Write-Host ""

    aws sso login --sso-session $PROFILE_NAME

    Info "Detecting your AWS account..."

    $cacheDir = Join-Path $env:USERPROFILE ".aws\sso\cache"
    $tokenFiles = Get-ChildItem -Path $cacheDir -Filter "*.json" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending

    $ACCESS_TOKEN = $null
    foreach ($file in $tokenFiles) {
        try {
            $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if ($data.accessToken) {
                $ACCESS_TOKEN = $data.accessToken
                break
            }
        } catch { }
    }

    if (-not $ACCESS_TOKEN) {
        Fail "Could not find SSO token after login. Please re-run the script."
    }

    $accountList = aws sso list-accounts `
        --access-token $ACCESS_TOKEN `
        --region $SSO_REGION | ConvertFrom-Json

    $ACCOUNT_ID = $accountList.accountList[0].accountId

    if (-not $ACCOUNT_ID) {
        Fail "No AWS accounts found for your user. Please check your access with your administrator."
    }

    Ok "Account detected: $ACCOUNT_ID"
}

# Writes/updates only the [profile ife] block. Skips the write if already
# up to date (e.g. re-running after the session above was already valid).
$existingContent = Get-Content $configPath -Raw
if (-not $existingContent) { $existingContent = "" }

$newProfileBlock = @"
[profile ife]
sso_session = ife
sso_account_id = $ACCOUNT_ID
sso_role_name = $SSO_ROLE_NAME
region = $AWS_REGION_VAL
output = json
"@.Trim()

$existingProfileMatch = [regex]::Match($existingContent, '(?s)\[profile ife\][^\[]*')
$existingProfileBlock = if ($existingProfileMatch.Success) { $existingProfileMatch.Value.Trim() } else { $null }

if ($existingProfileBlock -eq $newProfileBlock) {
    Skip "AWS profile already up to date ($configPath)"
} else {
    $stripped = $existingContent -replace '(?s)\[profile ife\][^\[]*', ''
    $stripped = $stripped -replace '(\r?\n){3,}', "`n`n"
    $stripped = $stripped.Trim()
    $finalContent = (($stripped + "`n`n" + $newProfileBlock).Trim()) + "`n"
    Write-Utf8NoBom -Path $configPath -Content $finalContent
    Ok "AWS profile written ($configPath)"
}

try {
    $identity = aws sts get-caller-identity --profile $PROFILE_NAME | ConvertFrom-Json
    Ok "Verified access — account: $($identity.Account)"
} catch {
    Fail "Authentication failed. Please re-run the script and complete the browser login."
}

# ── Phase 4: Claude Code Bedrock Setup ────────────────────────────────────────
Header "Phase 4 / 4  —  Claude Code Bedrock Setup"

Write-Host ""
Write-Host "  AWS access is ready. Claude Code configures Bedrock itself -" -ForegroundColor White
Write-Host "  it auto-detects your profile/region and lists the models" -ForegroundColor White
Write-Host "  your account can actually invoke." -ForegroundColor White
Write-Host ""
Write-Host "  Run:"
Write-Host "    claude" -ForegroundColor White
Write-Host "  then, on first launch, choose 3rd-party platform -> Amazon Bedrock" -ForegroundColor White
Write-Host "  (or run /setup-bedrock inside an existing session)." -ForegroundColor White
Write-Host "  Select the $PROFILE_NAME profile when prompted." -ForegroundColor White
Write-Host ""

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "    AWS setup complete!" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Your session lasts 8 hours. To re-authenticate later:"
Write-Host "    aws sso login --profile ife" -ForegroundColor White
Write-Host ""
Write-Host "  (or just re-run this script — it will skip everything"
Write-Host "  that's already up to date)"
Write-Host ""
