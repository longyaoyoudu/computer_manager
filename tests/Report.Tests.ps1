$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMReportSummary" {
    It "returns reports in directory sorted by time descending" {
        $tmp = Join-Path $env:TEMP ("cm_rep_" + [Guid]::NewGuid().ToString("N"))
        $repDir = Join-Path $tmp "reports"
        New-Item -ItemType Directory -Path $repDir -Force | Out-Null
        try {
            "a" | Set-Content (Join-Path $repDir "2026-06-06_100000_x.md")
            Start-Sleep -Milliseconds 1100
            "b" | Set-Content (Join-Path $repDir "2026-06-06_100001_y.md")
            $list = Get-CMReportSummary -RootPath $tmp
            $list.Count | Should Be 2
            $list[0].Name | Should Match "_y\.md$"
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "returns empty array when directory does not exist" {
        $r = Get-CMReportSummary -RootPath "C:\does\not\exist_$([Guid]::NewGuid())"
        $null -ne $r | Should Be $true
        $r.Count | Should Be 0
    }
}

Describe "Invoke-CMReportRetention" {
    It "deletes only reports older than cutoff" {
        $tmp = Join-Path $env:TEMP ("cm_rep_ret_" + [Guid]::NewGuid().ToString("N"))
        $repDir = Join-Path $tmp "reports"
        New-Item -ItemType Directory -Path $repDir -Force | Out-Null
        try {
            "old"   | Set-Content (Join-Path $repDir "old.md")
            "fresh" | Set-Content (Join-Path $repDir "fresh.md")
            # Force the old file's LastWriteTime to 40 days ago
            (Get-Item (Join-Path $repDir "old.md")).LastWriteTime = (Get-Date).AddDays(-40)
            Invoke-CMReportRetention -RootPath $tmp -Days 30
            Test-Path (Join-Path $repDir "old.md")   | Should Be $false
            Test-Path (Join-Path $repDir "fresh.md") | Should Be $true
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "is a no-op when reports directory does not exist" {
        $tmp = Join-Path $env:TEMP ("cm_rep_ret_" + [Guid]::NewGuid().ToString("N"))
        { Invoke-CMReportRetention -RootPath $tmp -Days 30 } | Should Not Throw
    }
}

Describe "Invoke-CMLogRetention" {
    It "deletes only logs older than cutoff" {
        $tmp = Join-Path $env:TEMP ("cm_log_ret_" + [Guid]::NewGuid().ToString("N"))
        $logDir = Join-Path $tmp "logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        try {
            "old"   | Set-Content (Join-Path $logDir "old.log")
            "fresh" | Set-Content (Join-Path $logDir "fresh.log")
            (Get-Item (Join-Path $logDir "old.log")).LastWriteTime = (Get-Date).AddDays(-40)
            Invoke-CMLogRetention -RootPath $tmp -Days 30
            Test-Path (Join-Path $logDir "old.log")   | Should Be $false
            Test-Path (Join-Path $logDir "fresh.log") | Should Be $true
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "is a no-op when logs directory does not exist" {
        $tmp = Join-Path $env:TEMP ("cm_log_ret_" + [Guid]::NewGuid().ToString("N"))
        { Invoke-CMLogRetention -RootPath $tmp -Days 30 } | Should Not Throw
    }
}
