$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMConfig" {
    It "当 config.json 不存在时返回 null" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $result = Get-CMConfig -RootPath $tmp
            $result | Should BeNullOrEmpty
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "当 config.json 存在时返回 hashtable" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            @{ llm = @{ api_key = "test" } } | ConvertTo-Json | Set-Content (Join-Path $tmp "config.json")
            $result = Get-CMConfig -RootPath $tmp
            $result | Should Not BeNullOrEmpty
            $result.llm.api_key | Should Be "test"
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "当 config.json 是无效 JSON 时抛出" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            "not json" | Set-Content (Join-Path $tmp "config.json")
            { Get-CMConfig -RootPath $tmp } | Should Throw
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }
}

Describe "New-CMConfigTemplate" {
    It "应该在指定目录生成 config.json" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            New-CMConfigTemplate -RootPath $tmp
            Test-Path (Join-Path $tmp "config.json") | Should Be $true
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "生成的 config.json 应该是合法 JSON" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            New-CMConfigTemplate -RootPath $tmp
            { Get-Content (Join-Path $tmp "config.json") -Raw | ConvertFrom-Json } | Should Not Throw
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }
}

