$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Read-CMConfirm" {
    It "褰撹緭鍏?y 鏃惰繑鍥?true" {
        $result = Read-CMConfirm -Prompt "test?" -DefaultYes $false -SimulateInput "y"
        $result | Should Be $true
    }

    It "褰撹緭鍏?n 鏃惰繑鍥?false" {
        $result = Read-CMConfirm -Prompt "test?" -DefaultYes $true -SimulateInput "n"
        $result | Should Be $false
    }

    It "褰撹緭鍏ヤ负绌烘椂閬靛惊 DefaultYes" {
        $resultY = Read-CMConfirm -Prompt "?" -DefaultYes $true  -SimulateInput ""
        $resultN = Read-CMConfirm -Prompt "?" -DefaultYes $false -SimulateInput ""
        $resultY | Should Be $true
        $resultN | Should Be $false
    }
}

Describe "Format-CMBytes" {
    It "B 鍗曚綅"  { Format-CMBytes -Bytes 512       | Should Be "512 B" }
    It "KB 鍗曚綅" { Format-CMBytes -Bytes 2048      | Should Be "2.00 KB" }
    It "MB 鍗曚綅" { Format-CMBytes -Bytes 5242880   | Should Be "5.00 MB" }
    It "GB 鍗曚綅" { Format-CMBytes -Bytes 1073741824| Should Be "1.00 GB" }
}

