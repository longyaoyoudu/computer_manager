$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path

Describe "computer_manager.ps1 dot-source 行为" {
    It "应该能 dot-source 加载而不进入主菜单" {
        $output = & {
            . $sut
            "loaded"
        } 2>&1
        ($output -join "`n") | Should Match "loaded"
    }

    It "暴露 $Script:CMVersion 全局变量" {
        . $sut
        $Script:CMVersion | Should Be '1.0.0'
    }
}

