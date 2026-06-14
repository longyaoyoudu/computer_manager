$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe 'Test-CMCommandAllowed' {
    It '接受简单 cmdlet' {
        $r = Test-CMCommandAllowed -Command 'Get-Service msiserver' -SafetyConfig $null
        $r.allowed | Should Be $true
    }

    It '接受 PS 单行 ; 链' {
        $r = Test-CMCommandAllowed -Command 'Set-Service X -StartupType Manual; Start-Service X' -SafetyConfig $null
        $r.allowed | Should Be $true
    }

    It '拒绝多行命令' {
        $r = Test-CMCommandAllowed -Command "Get-Service`nrm -rf C:\" -SafetyConfig $null
        $r.allowed | Should Be $false
    }

    It '拒绝 cmd 链 &' {
        $r = Test-CMCommandAllowed -Command 'dir & del /q /f C:\' -SafetyConfig $null
        $r.allowed | Should Be $false
    }

    It '拒绝 cmd 链 &&' {
        $r = Test-CMCommandAllowed -Command 'dir && del /q /f C:\' -SafetyConfig $null
        $r.allowed | Should Be $false
    }

    It '拒绝 cmd 链 ||' {
        $r = Test-CMCommandAllowed -Command 'dir || del /q /f C:\' -SafetyConfig $null
        $r.allowed | Should Be $false
    }

    It '拒绝 Invoke-Expression' {
        $r = Test-CMCommandAllowed -Command "Invoke-Expression 'calc'" -SafetyConfig @{
            allow_iex = $false
        }
        $r.allowed | Should Be $false
    }

    It '允许 iex 当 allow_iex=true' {
        $r = Test-CMCommandAllowed -Command "Invoke-Expression 'calc'" -SafetyConfig @{
            allow_iex = $true
        }
        $r.allowed | Should Be $true
    }

    It '拒绝 -EncodedCommand' {
        $r = Test-CMCommandAllowed -Command 'powershell -EncodedCommand ZQBjAGgAbwAgACQARQBuAHYA' -SafetyConfig $null
        $r.allowed | Should Be $false
    }

    It '拒绝 FromBase64String' {
        $r = Test-CMCommandAllowed -Command "[System.Convert]::FromBase64String('aGk=')" -SafetyConfig $null
        $r.allowed | Should Be $false
    }

    It 'Remove-Item 命中系统目录时标记高风险' {
        $r = Test-CMCommandAllowed -Command 'Remove-Item -Recurse -Force C:\Windows\System32\foo' -SafetyConfig $null
        $r.allowed | Should Be $true
        $r.risk | Should Be 'high'
    }
}

Describe 'Get-CMSystemDirs' {
    It '应返回系统目录前缀列表' {
        $dirs = Get-CMSystemDirs
        $dirs | Should Match 'C:\\Windows'
    }
}
