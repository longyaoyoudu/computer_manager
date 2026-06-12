$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMHealthReport" {
    It "应返回包含 os/cpu/memory/disk 的健康数据" {
        $r = Get-CMHealthReport
        $r | Should Not BeNullOrEmpty
        $names = $r.PSObject.Properties.Name
        ($names -contains "os") | Should Be $true
        ($names -contains "cpu") | Should Be $true
        ($names -contains "memory") | Should Be $true
        ($names -contains "disk") | Should Be $true
        ($names -contains "auto_services_stopped") | Should Be $true
    }
}

Describe "Format-CMHealthMarkdown" {
    It "应把健康报告渲染为 Markdown" {
        $r = [PSCustomObject]@{
            os = "Windows 11"
            memory = [PSCustomObject]@{ total_gb = 16; free_gb = 8 }
            disk = @(@{ drive = "C:"; free_gb = 100 })
            auto_services_stopped = @("BITS","wuauserv")
        }
        $md = Format-CMHealthMarkdown -Report $r
        $md | Should Match "Windows 11"
        $md | Should Match "BITS"
        $md | Should Match "16"
    }
}