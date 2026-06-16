$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

$root = Join-Path $env:TEMP ("cm_smoke_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root -Force | Out-Null

try {
    # 1) auto-generate config
    New-CMConfigTemplate -RootPath $root | Out-Null
    $cfg = Get-CMConfig -RootPath $root
    if (-not $cfg) { throw '生成失败' }
    Write-Host ("[1/8] config '生成' OK")

    # 2) Logger
    $logger = New-CMLogger -RootPath $root
    Write-CMLog -Logger $logger -Level "INFO" -Source "SMOKE" -Message "hello"
    $log = Get-ChildItem (Join-Path $root "logs") -Filter "*.log" | Select -First 1
    if (-not (Test-Path $log.FullName)) { throw '日志未生成' }
    Write-Host "[2/8] logger OK"

    # 3) Snapshot
    $snap = Get-CMSnapshot -Mode quick
    if (-not $snap.os) { throw "'缺少' os" }
    Write-Host "[3/8] snapshot OK"

    # 4) Parser
    $r1 = Test-CMCommandAllowed -Command "Get-Service" -SafetyConfig $null
    if (-not $r1.allowed) { throw '误拒' }
    $r2 = Test-CMCommandAllowed -Command "Invoke-Expression 'x'" -SafetyConfig $null
    if ($r2.allowed) { throw "'漏过' iex" }
    Write-Host "[4/8] parser OK"

    # 5) Dispatcher + Executor
    $r = Invoke-CMExecuteCommand -Command "Get-Service | Out-Null" -Dispatch ps
    if ($r.exitCode -ne 0) { throw "ps executor '失败'" }
    $r = Invoke-CMExecuteCommand -Command "echo hi" -Dispatch cmd
    if ($r.exitCode -ne 0 -or $r.stdout -notmatch "hi") { throw "cmd executor '失败'" }
    Write-Host "[5/8] executor OK"

    # 6) LLM parse (build the raw object step by step to avoid parser issues)
    $argsJson = '{"analysis":"a","root_cause":"r","risk_level":"low","commands":[]}'
    $toolCall = [PSCustomObject]@{ function = [PSCustomObject]@{ name = "submit_diagnosis"; arguments = $argsJson } }
    $message  = [PSCustomObject]@{ tool_calls = @($toolCall) }
    $choice   = [PSCustomObject]@{ message = $message }
    $raw      = [PSCustomObject]@{ choices = @($choice) }
    $parsed = ConvertFrom-CMLLMResponse -Raw $raw
    if ($parsed.analysis -ne "a") { throw "llm '解析失败'" }
    Write-Host ("[6/8] llm '解析' OK")

    # 7) Report
    $reportDir = Join-Path $root "reports"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    "test" | Set-Content (Join-Path $reportDir "smoke.md")
    $list = Get-CMReportSummary -RootPath $root
    if ($list.Count -ne 1) { throw "report summary '失败'" }
    Write-Host "[7/8] report OK"

    # 8) cleanup
    Remove-Item -Recurse -Force (Join-Path $root "logs"), $reportDir -ErrorAction SilentlyContinue
    Write-Host "[8/8] cleanup OK"
    Write-Host "ALL SMOKE TESTS PASSED"
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
