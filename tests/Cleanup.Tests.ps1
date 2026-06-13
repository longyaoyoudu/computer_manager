$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMCleanupTargets" {
    It "应返回至少 3 个清理目标" {
        $targets = Get-CMCleanupTargets
        $targets.Count | Should BeGreaterThan 3
        $names = $targets[0].PSObject.Properties.Name
        ($names -contains "name") | Should Be $true
        ($names -contains "path") | Should Be $true
    }
}

Describe "Get-CMCleanupSize" {
    It "应能统计一个目录的总大小（不抛错）" {
        $tmp = Join-Path $env:TEMP ("cm_cleanup_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            "hello" | Set-Content (Join-Path $tmp "a.txt")
            "world" | Set-Content (Join-Path $tmp "b.txt")
            $size = Get-CMCleanupSize -Path $tmp
            ($size -ge 10) | Should Be $true
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "路径不存在时应返回 0 不抛错" {
        $size = Get-CMCleanupSize -Path "C:\does\not\exist\zzz_$([Guid]::NewGuid())"
        $size | Should Be 0
    }
}
