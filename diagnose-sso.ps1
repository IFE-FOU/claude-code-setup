#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostic for AWS SSO "code isn't right" errors on Windows.
.DESCRIPTION
    Collects environment info relevant to the OIDC device-authorization flow
    failure. Run this, paste the output back.
.NOTES
    Usage:
        irm https://raw.githubusercontent.com/IFE-FOU/claude-code-setup/main/diagnose-sso.ps1 | iex
#>

Write-Host "── AWS CLI ──────────────────────────────────" -ForegroundColor Blue
aws --version

Write-Host "`n── All aws.exe on PATH (checks for conflicting installs) ──" -ForegroundColor Blue
Get-Command aws -All -ErrorAction SilentlyContinue | Select-Object Source, Version

Write-Host "`n── System clock (SSO PKCE is time-sensitive) ──" -ForegroundColor Blue
Get-Date
Write-Host "Timezone: $((Get-TimeZone).Id)"
$w32tm = w32tm /query /status 2>&1
Write-Host $w32tm

Write-Host "`n── AWS config (~/.aws/config) ──" -ForegroundColor Blue
$configPath = Join-Path $env:USERPROFILE ".aws\config"
if (Test-Path $configPath) {
    Get-Content $configPath
} else {
    Write-Host "  (missing)" -ForegroundColor Yellow
}

Write-Host "`n── SSO cache directory (~/.aws/sso/cache) ──" -ForegroundColor Blue
$cacheDir = Join-Path $env:USERPROFILE ".aws\sso\cache"
if (Test-Path $cacheDir) {
    Get-ChildItem $cacheDir | Select-Object Name, LastWriteTime, Length
} else {
    Write-Host "  (missing)" -ForegroundColor Yellow
}

Write-Host "`n── Anything listening on common local callback ports ──" -ForegroundColor Blue
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -ge 60000 -and $_.LocalPort -le 61000 } |
    Select-Object LocalAddress, LocalPort, OwningProcess

Write-Host "`n── Proxy / env vars that could intercept localhost callback ──" -ForegroundColor Blue
Get-ChildItem Env: | Where-Object { $_.Name -match 'proxy' -or $_.Name -match 'HTTP' } |
    Select-Object Name, Value

Write-Host "`n── Default browser ──" -ForegroundColor Blue
try {
    $browserProgId = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -ErrorAction Stop).ProgId
    Write-Host $browserProgId
} catch {
    Write-Host "  (could not determine)" -ForegroundColor Yellow
}

Write-Host "`nDone. Paste this whole output back." -ForegroundColor Green
