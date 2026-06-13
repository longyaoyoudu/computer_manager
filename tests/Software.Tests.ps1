$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMInstalledSoftware" {
    It "应返回非空集合且每个元素有 name/architecture 字段" {
        $list = Get-CMInstalledSoftware
        $list | Should Not BeNullOrEmpty
        $first = $list | Select-Object -First 1
        $names = $first.PSObject.Properties.Name
        ($names -contains "name") | Should Be $true
        ($names -contains "architecture") | Should Be $true
    }
}

Describe "Format-CMUninstallString" {
    It "提取 MsiExec 静默参数" {
        $s = "MsiExec.exe /I{ABCD}"
        $r = Format-CMUninstallString -UninstallString $s
        $r.silent | Should Match "msiexec.*\/x\{ABCD\}.*\/qn"
    }

    It "提取 EXE 静默参数（带 /S）" {
        $s = '"C:\Program Files\Foo\uninst.exe" /S'
        $r = Format-CMUninstallString -UninstallString $s
        $r.cmd | Should Match "uninst\.exe"
        $r.cmd | Should Match "/S"
    }
}
