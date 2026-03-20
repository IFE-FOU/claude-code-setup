#Requires -Version 5.1
<#
.SYNOPSIS
    IFE Claude Code Setup for Windows
.DESCRIPTION
    Installs and configures Claude Code with AWS Bedrock SSO.
    Safe to re-run — updates existing configuration.
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
$MODEL_SONNET   = "eu.anthropic.claude-sonnet-4-6"
$MODEL_OPUS     = "eu.anthropic.claude-opus-4-6-v1"
$MODEL_HAIKU    = "eu.anthropic.claude-haiku-4-5-20251001-v1:0"

# ── Output helpers ────────────────────────────────────────────────────────────
function Ok($msg)     { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Skip($msg)   { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }
function Info($msg)   { Write-Host "  [...]  $msg" -ForegroundColor Cyan }
function Fail($msg)   { Write-Host "`n  [ERR]  $msg`n" -ForegroundColor Red; exit 1 }
function Header($msg) { Write-Host "`n$("─" * 54)`n  $msg`n$("─" * 54)" -ForegroundColor Blue }

# ── Intro ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  IFE Claude Code Setup" -ForegroundColor White
Write-Host "  ──────────────────────────────────────────────────────"
Write-Host "  Installs and configures Claude Code with AWS Bedrock."
Write-Host "  Safe to re-run — updates existing configuration."
Write-Host "  ──────────────────────────────────────────────────────"
Write-Host ""

# ── Winget check ──────────────────────────────────────────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "winget is required but was not found.`n  Install 'App Installer' from the Microsoft Store and re-run this script."
}

# ── Phase 1: Dependencies ─────────────────────────────────────────────────────
Header "Phase 1 / 5  —  Dependencies"

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

# Claude Code (always install to pick up latest version)
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Info "Updating Claude Code to latest..."
    npm install -g @anthropic-ai/claude-code
    Ok "Claude Code updated"
} else {
    Info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    Ok "Claude Code installed"
}

# ── Phase 2: AWS SSO Session Config ───────────────────────────────────────────
Header "Phase 2 / 5  —  AWS SSO Configuration"

$awsDir     = Join-Path $env:USERPROFILE ".aws"
$configPath = Join-Path $awsDir "config"

if (-not (Test-Path $awsDir)) {
    New-Item -ItemType Directory -Path $awsDir | Out-Null
}

Info "Writing AWS SSO session to $configPath..."

$existingContent = if (Test-Path $configPath) { Get-Content $configPath -Raw } else { "" }

# Remove existing ife blocks, leave all other profiles untouched
$existingContent = $existingContent -replace '(?s)\[sso-session ife\][^\[]*', ''
$existingContent = $existingContent -replace '(?s)\[profile ife\][^\[]*', ''
$existingContent = $existingContent -replace '(\r?\n){3,}', "`n`n"
$existingContent = $existingContent.Trim()

# Write only the sso-session block — profile is completed after login (Phase 3)
$sessionBlock = @"


[sso-session ife]
sso_start_url = $SSO_START_URL
sso_region = $SSO_REGION
sso_registration_scopes = sso:account:access
"@

$finalContent = ($existingContent + $sessionBlock).Trim() + "`n"
Set-Content -Path $configPath -Value $finalContent -Encoding UTF8

Ok "SSO session written ($configPath)"

# ── Phase 3: SSO Login ────────────────────────────────────────────────────────
Header "Phase 3 / 5  —  SSO Login"

Write-Host ""
Write-Host "  A browser window will open for you to log in with your" -ForegroundColor White
Write-Host "  IFE Microsoft credentials." -ForegroundColor White
Write-Host "  Return here after completing authentication in the browser."
Write-Host ""
Read-Host "  Press Enter to open the browser login"
Write-Host ""

aws sso login --sso-session $PROFILE_NAME

# Discover account ID from the SSO token cache — no hardcoded account ID needed
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

# Write the complete profile now that we have the account ID
$existingContent = Get-Content $configPath -Raw
$existingContent = $existingContent -replace '(?s)\[profile ife\][^\[]*', ''
$existingContent = $existingContent -replace '(\r?\n){3,}', "`n`n"
$existingContent = $existingContent.Trim()

$profileBlock = @"


[profile ife]
sso_session = ife
sso_account_id = $ACCOUNT_ID
sso_role_name = $SSO_ROLE_NAME
region = $AWS_REGION_VAL
output = json
"@

$finalContent = ($existingContent + $profileBlock).Trim() + "`n"
Set-Content -Path $configPath -Value $finalContent -Encoding UTF8

Ok "AWS profile written ($configPath)"

# ── Phase 4: Verification ─────────────────────────────────────────────────────
Header "Phase 4 / 5  —  Verifying Access"

try {
    $identity = aws sts get-caller-identity --profile $PROFILE_NAME | ConvertFrom-Json
    Ok "Authenticated as: $($identity.Arn)"
    Ok "Account: $($identity.Account)"
} catch {
    Fail "Authentication failed. Please re-run the script and complete the browser login."
}

# ── Phase 5: Environment Variables ────────────────────────────────────────────
Header "Phase 5 / 5  —  Environment Variables"

$envVars = [ordered]@{
    CLAUDE_CODE_USE_BEDROCK            = "1"
    AWS_PROFILE                        = $PROFILE_NAME
    AWS_REGION                         = $AWS_REGION_VAL
    ANTHROPIC_MODEL                    = $MODEL_SONNET
    ANTHROPIC_DEFAULT_SONNET_MODEL     = $MODEL_SONNET
    ANTHROPIC_DEFAULT_OPUS_MODEL       = $MODEL_OPUS
    ANTHROPIC_DEFAULT_HAIKU_MODEL      = $MODEL_HAIKU
    CLAUDE_CODE_SUBAGENT_MODEL         = $MODEL_SONNET
}

Info "Writing environment variables (User scope — persists across sessions)..."

foreach ($key in $envVars.Keys) {
    $value = $envVars[$key]
    [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    [System.Environment]::SetEnvironmentVariable($key, $value, "User")
}

Ok "Environment variables set"

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "    Setup complete!" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Start Claude Code:"
Write-Host "    claude" -ForegroundColor White
Write-Host ""
Write-Host "  Your session lasts 8 hours. To re-authenticate:"
Write-Host "    aws sso login --profile ife" -ForegroundColor White
Write-Host ""
Write-Host "  NOTE: Open a new terminal window for environment" -ForegroundColor Yellow
Write-Host "  variables to take full effect." -ForegroundColor Yellow
Write-Host ""
