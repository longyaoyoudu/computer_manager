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

    It "should not duplicate the 诊断快照 header" {
        $ctx = [PSCustomObject]@{ snapshot = [PSCustomObject]@{ os = "Win11" }; app = "X"; error = "E"; tried = "" }
        $resp = [PSCustomObject]@{ commands = @() }
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved @()
        # Count occurrences of the snapshot header - must be exactly 1.
        ([regex]::Matches($md, '## 诊断快照')).Count | Should Be 1
    }

    It "should list LLM-suggested commands that were not approved" {
        $ctx = [PSCustomObject]@{ snapshot = [PSCustomObject]@{}; app = "X"; error = "E"; tried = "" }
        $resp = [PSCustomObject]@{
            commands = @(
                [PSCustomObject]@{ id = 1; risk = "low"; description = "check service"; command = "Get-Service x"; expected_effect = "shows status" },
                [PSCustomObject]@{ id = 2; risk = "medium"; description = "restart"; command = "Restart-Service x"; expected_effect = "back to running" },
                [PSCustomObject]@{ id = 3; risk = "high"; description = "delete file"; command = "Remove-Item x"; expected_effect = "gone" }
            )
        }
        # User only approved #1; #2 and #3 should appear in the pending section.
        $approved = @(
            [PSCustomObject]@{
                id = 1; risk = "low"; description = "check service"; command = "Get-Service x"
                expected_effect = "shows status"; rollback_hint = "n/a"
                Result = [PSCustomObject]@{ exitCode = 0; durationSec = 0.5 }
            }
        )
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved
        $md | Should Match '### 建议但未执行'
        $md | Should Match 'Restart-Service x'
        $md | Should Match 'Remove-Item x'
        # Approved command should NOT appear in the pending section.
        $pendingSection = ($md -split '### 建议但未执行', 2)[1]
        $pendingSection | Should Not Match 'Get-Service x'
    }

    It "should not emit the pending section when everything was approved" {
        $ctx = [PSCustomObject]@{ snapshot = [PSCustomObject]@{}; app = "X"; error = "E"; tried = "" }
        $resp = [PSCustomObject]@{
            commands = @(
                [PSCustomObject]@{ id = 1; risk = "low"; description = "d"; command = "Get-Service"; expected_effect = "ok" }
            )
        }
        $approved = @(
            [PSCustomObject]@{
                id = 1; risk = "low"; description = "d"; command = "Get-Service"
                expected_effect = "ok"; rollback_hint = "n/a"
                Result = [PSCustomObject]@{ exitCode = 0; durationSec = 1 }
            }
        )
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved
        $md | Should Not Match '建议但未执行'
    }

    It "should annotate pending commands that fail Parser safety check" {
        $ctx = [PSCustomObject]@{ snapshot = [PSCustomObject]@{}; app = "X"; error = "E"; tried = "" }
        $resp = [PSCustomObject]@{
            commands = @(
                [PSCustomObject]@{ id = 1; risk = "low"; description = "safe"; command = "Get-Service x"; expected_effect = "ok" },
                # iex is rejected by Parser unless allow_iex=true
                [PSCustomObject]@{ id = 2; risk = "low"; description = "unsafe iex"; command = "Invoke-Expression 'Get-Process'"; expected_effect = "nope" }
            )
        }
        $approved = @()
        $safety = @{ allow_encoded_commands = $false; allow_iex = $false }
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved -SafetyConfig $safety
        # The unsafe command should be marked rejected with reason
        $md | Should Match 'rejected'
        $md | Should Match '被解析防护拒绝'
        # The safe command should still appear without rejected annotation
        $md | Should Match 'Get-Service x'
    }

    It "should fall back to '-' for pending risk when LLM omitted it" {
        $ctx = [PSCustomObject]@{ snapshot = [PSCustomObject]@{}; app = "X"; error = "E"; tried = "" }
        $resp = [PSCustomObject]@{
            commands = @(
                [PSCustomObject]@{ id = 1; description = "no risk field"; command = "Get-Service x"; expected_effect = "ok" }
            )
        }
        $approved = @()
        # Without SafetyConfig, risk defaults to '-'
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved
        # Find the pending row for id=1 and check its risk column
        $pendingSection = ($md -split '### 建议但未执行', 2)[1]
        $pendingSection | Should Match '\| 1 \| - \|'
    }

    It "should use Parser effective risk when LLM omitted risk and SafetyConfig provided" {
        $ctx = [PSCustomObject]@{ snapshot = [PSCustomObject]@{}; app = "X"; error = "E"; tried = "" }
        $resp = [PSCustomObject]@{
            commands = @(
                [PSCustomObject]@{ id = 1; description = "no risk"; command = "Get-Service x"; expected_effect = "ok" }
            )
        }
        $approved = @()
        $safety = @{ allow_encoded_commands = $false; allow_iex = $false }
        $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved -SafetyConfig $safety
        $pendingSection = ($md -split '### 建议但未执行', 2)[1]
        # Parser default risk for Get-Service is low; risk column should NOT be '-'
        $pendingSection | Should Not Match '\| 1 \| - \|'
        $pendingSection | Should Match '\| 1 \| low \|'
    }
}