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

    It "should embed snapshot as parseable JSON fenced block" {
        $ctx = [PSCustomObject]@{
            snapshot = [PSCustomObject]@{ os = "Win11"; admin = $true }
            app = "Office"
            error = "0x80070005"
            tried = "ran as admin"
        }
        $msg = Format-CMDiagnosisUserMessage -Context $ctx
        $msg | Should Match '```json'
        $msg | Should Match '```'
        # Extract the JSON block between ```json and ``` and verify it parses
        if ($msg -match '(?s)```json\s*(\{.*?\})\s*```') {
            $parsed = $matches[1] | ConvertFrom-Json -ErrorAction SilentlyContinue
            $parsed | Should Not BeNullOrEmpty
            $parsed.os | Should Be "Win11"
            $parsed.admin | Should Be $true
        } else {
            throw 'No JSON fenced block found'
        }
    }
}

Describe "Format-CMDiagnoseReport" {
    It "should generate a markdown report with the approved command table" {
        $ctx = [PSCustomObject]@{
            snapshot = [PSCustomObject]@{ os = "Win11"; admin = $true }
            app = "Office"
            error = "0x80070005"
            tried = "ran as admin"
        }
        $resp = [PSCustomObject]@{
            analysis = "registry issue"
            root_cause = "missing key"
            risk_level = "low"
            commands = @(@{ id = 1 })
        }
        $approved = @(
            [PSCustomObject]@{
                id = 1; risk = "low"; description = "d"; command = "Get-Service"
                expected_effect = "ok"; rollback_hint = "n/a"
                Result = [PSCustomObject]@{ exitCode = 0; durationSec = 1.5 }
            }
        )
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved -Mode "quick"
        $md | Should Match "Office"
        $md | Should Match "registry issue"
        $md | Should Match '\| # \|'
        $md | Should Match "Get-Service"
        $md | Should Match "0"
    }

    It "should handle missing response fields gracefully" {
        $ctx = [PSCustomObject]@{ snapshot = [PSCustomObject]@{}; app = "X"; error = "E"; tried = "" }
        $resp = [PSCustomObject]@{}  # no analysis/root_cause/risk_level
        $approved = @()
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved
        $md | Should Not BeNullOrEmpty
        $md | Should Match '## '
        # Should not throw and should produce a report (analysis/root_cause/risk_level are empty)
    }
}