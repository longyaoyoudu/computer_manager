$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "New-CMLogger" {
    It "创建 logger 时应建立 logs 子目录" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $logger = New-CMLogger -RootPath $tmp
            Test-Path (Join-Path $tmp "logs") | Should Be $true
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "Write-CMLog 应把消息写入日志文件" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $logger = New-CMLogger -RootPath $tmp
            Write-CMLog -Logger $logger -Level "INFO" -Source "TEST" -Message "hello world"
            $logFile = Get-ChildItem (Join-Path $tmp "logs") -Filter "*.log" | Select -First 1
            $content = Get-Content $logFile.FullName -Raw
            $content | Should Match "INFO"
            $content | Should Match "TEST"
            $content | Should Match "hello world"
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "api_key 字段在日志中应被脱敏" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $logger = New-CMLogger -RootPath $tmp
            Write-CMLog -Logger $logger -Level "INFO" -Source "TEST" -Message "key=sk-abc123def456"
            $logFile = Get-ChildItem (Join-Path $tmp "logs") -Filter "*.log" | Select -First 1
            $content = Get-Content $logFile.FullName -Raw
            $content | Should Not Match "sk-abc123def456"
            $content | Should Match "\*\*\*"
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }
}

