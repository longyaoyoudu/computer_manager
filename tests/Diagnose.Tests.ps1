$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "New-CMDiagnosisContext" {
    It "should construct context with snapshot/app/error/tried" {
        $snap = [PSCustomObject]@{ os = "Win11"; admin = $true }
        $ctx = New-CMDiagnosisContext -Snapshot $snap -AppName "Office" -ErrorText "0x80070005" -TriedActions "ran as admin"
        $ctx.snapshot.os | Should Be "Win11"
        $ctx.app | Should Be "Office"
        $ctx.error | Should Be "0x80070005"
        $ctx.tried | Should Be "ran as admin"
    }
}

Describe "Format-CMDiagnosisUserMessage" {
    It "should format context to a user message string" {
        $ctx = [PSCustomObject]@{
            snapshot = [PSCustomObject]@{ os = "Win11" }
            app = "Office"
            error = "0x80070005"
            tried = "ran as admin"
        }
        $msg = Format-CMDiagnosisUserMessage -Context $ctx
        $msg | Should Match "Office"
        $msg | Should Match "0x80070005"
        $msg | Should Match "Win11"
    }
}