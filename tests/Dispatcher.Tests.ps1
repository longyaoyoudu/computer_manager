$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMCommandDispatch" {
    It "Get-Service 走 PowerShell" {
        Get-CMCommandDispatch -Command "Get-Service msiserver" | Should Be "ps"
    }

    It "msiexec 走 PowerShell（因白名单内）" {
        Get-CMCommandDispatch -Command "msiexec /unregister" | Should Be "ps"
    }

    It "tasklist 走 cmd" {
        Get-CMCommandDispatch -Command "tasklist" | Should Be "cmd"
    }

    It "sc query 走 cmd" {
        Get-CMCommandDispatch -Command "sc query msiserver" | Should Be "cmd"
    }
}

Describe "Invoke-CMExecuteCommand" {
    It "执行 powershell cmdlet 应成功并捕获 exit 0" {
        $r = Invoke-CMExecuteCommand -Command "Get-Service msiserver | Select-Object -First 1 | Out-Null" -Dispatch "ps"
        $r.exitCode | Should Be 0
    }

    It "执行 cmd 原生命令应成功" {
        $r = Invoke-CMExecuteCommand -Command "echo hello" -Dispatch "cmd"
        $r.exitCode | Should Be 0
        $r.stdout | Should Match "hello"
    }
}
