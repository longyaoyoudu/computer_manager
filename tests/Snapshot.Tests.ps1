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

    It "should render object arrays as a sub-table (not '; ; ; ;')" {
        # Repro of forward/2026-06-22_143253_________.md issue 3: PSCustomObject
        # arrays previously produced empty ToString() values, which when joined
        # yielded '; ; ; ;' in the report.
        $snap = [PSCustomObject]@{
            os = "Win10"
            event_log_errors = @(
                [PSCustomObject]@{ time='2026-06-22 14:00:00'; log='Application'; source='MsiInstaller'; eventId=10005; message='MSI failed' }
                [PSCustomObject]@{ time='2026-06-22 14:01:00'; log='System'; source='Service Control Manager'; eventId=7000; message='timeout' }
            )
        }
        $md = Format-CMSnapshotMarkdown -Snapshot $snap
        # The cell must NOT be '; ; ' (or any all-empty join)
        $md | Should Not Match '\| event_log_errors \| ; '
        # Real data must appear in a sub-table beneath the main table
        $md | Should Match '### event_log_errors'
        $md | Should Match 'MSI failed'
        $md | Should Match 'MsiInstaller'
        $md | Should Match '10005'
    }

    It "should show '(无)' for empty object arrays" {
        $snap = [PSCustomObject]@{
            os = "Win10"
            event_log_errors = @()
        }
        $md = Format-CMSnapshotMarkdown -Snapshot $snap
        $md | Should Match 'event_log_errors'
        $md | Should Match '(无)'
    }

    It "should keep primitive arrays joined with '; '" {
        $snap = [PSCustomObject]@{
            os = "Win10"
            tags = @('a', 'b', 'c')
        }
        $md = Format-CMSnapshotMarkdown -Snapshot $snap
        $md | Should Match 'a; b; c'
    }
}
