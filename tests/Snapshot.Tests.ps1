$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMSnapshot" {
    It "quick 模式应返回包含 os/admin/uac/disk 等字段" {
        $snap = Get-CMSnapshot -Mode "quick"
        $snap | Should Not BeNullOrEmpty
        $names = $snap.PSObject.Properties.Name
        ($names -contains "os") | Should Be $true
        ($names -contains "admin") | Should Be $true
        ($names -contains "uac_level") | Should Be $true
        ($names -contains "disk_free_gb") | Should Be $true
    }

    It "full 模式应包含 quick 全部字段并增加更多" {
        $snap = Get-CMSnapshot -Mode "full"
        $snap | Should Not BeNullOrEmpty
        $names = $snap.PSObject.Properties.Name
        ($names -contains "os") | Should Be $true
        ($names -contains "admin") | Should Be $true
        ($names -contains "firewall") | Should Be $true
    }
}

Describe "Format-CMSnapshotMarkdown" {
    It "应把 snapshot 渲染为 Markdown 表格" {
        $snap = [PSCustomObject]@{
            os = "Windows 11 Pro 23H2"
            admin = $true
            uac_level = 5
            disk_free_gb = 42.3
        }
        $md = Format-CMSnapshotMarkdown -Snapshot $snap
        $md | Should Match "Windows 11 Pro"
        $md | Should Match "42.3"
        $md | Should Match "##"
    }
}
