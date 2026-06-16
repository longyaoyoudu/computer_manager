$ErrorActionPreference = 'Stop'
Write-Host "=== 1) Pester unit tests ===" -ForegroundColor Cyan
$testsPath = (Resolve-Path "$PSScriptRoot").Path
Invoke-Pester -Path $testsPath -EnableExit:$false
Write-Host ""
Write-Host "=== 2) End-to-end smoke ===" -ForegroundColor Cyan
& "$PSScriptRoot\smoke.ps1"
Write-Host ""
Write-Host "=== ALL TESTS PASSED ===" -ForegroundColor Green
