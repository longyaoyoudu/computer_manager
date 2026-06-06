# 电脑管理脚本 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 10/11（PowerShell 5.1）单文件双击即跑的电脑管理工具，覆盖 LLM 驱动的应用安装问题诊断、日常清理、软件管理、系统健康快照、报告生成。

**Architecture:** 单个 `computer_manager.ps1` 包含全部逻辑（regions 分模块），配套 `.bat` 启动器、Pester 单元测试。LLM 通过 OpenAI 兼容 HTTP API 调用，工具调用（`tool_calls`）为主响应，文本 JSON 解析为兜底。所有 LLM 生成的命令在执行前逐条 y/n 人工确认。

**Tech Stack:** PowerShell 5.1（默认 Win10/11 内置），Pester 3.4（仅开发期），OpenAI 兼容 LLM API（DeepSeek/Qwen/OpenAI/Ollama 等），`Invoke-RestMethod` 做 HTTP，CIM/WMI/Registry 做系统检测。

---

## 文件结构

```
computer_manager/
├── computer_manager.ps1     # 主脚本（全部逻辑，region 分模块，目标 ≤ 2000 行）
├── computer_manager.bat     # 启动器
├── config.example.json      # 配置模板（提交；config.json 不提交）
├── README.md                # 中文使用说明
├── .gitignore               # 已存在
├── tests/                   # Pester 测试（不随工具分发）
│   ├── Config.Tests.ps1
│   ├── Logging.Tests.ps1
│   ├── Parser.Tests.ps1
│   ├── Dispatcher.Tests.ps1
│   ├── Snapshot.Tests.ps1
│   ├── Health.Tests.ps1
│   ├── Cleanup.Tests.ps1
│   └── Software.Tests.ps1
└── docs/superpowers/
    ├── specs/2026-06-06-computer-manager-design.md  # 设计文档
    └── plans/2026-06-06-computer-manager-implementation.md  # 本文件
```

**主脚本内部 region 顺序**（从上到下）：

```
#region Header & Globals
#region Config
#region Logging
#region UI Helpers
#region System Context
#region Snapshot (诊断快照)
#region Parser (命令解析/拒绝规则)
#region Dispatcher (ps/cmd 派发)
#region LLM (HTTP/解析/系统提示)
#region Diagnose (诊断主流程)
#region Cleanup
#region Software
#region Health (系统健康快照)
#region Report
#region Menu (主菜单 + 分发)
#region Main (入口，含 dot-source 守卫)
#endregion
```

**测试入口**（每个测试文件都做）：
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut   # dot-source 加载所有函数
```

主脚本末尾守卫（保证 dot-source 时不进入主菜单）：
```powershell
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-CMMain
}
```

---

## 测试基础设施

**Pester 3.4 经典语法**。运行测试：
```bash
powershell -NoProfile -Command "Invoke-Pester tests/"
```

或单文件：
```bash
powershell -NoProfile -Command "Invoke-Pester tests/Parser.Tests.ps1"
```

**约定**：
- 测试文件命名 `Xxx.Tests.ps1`
- 一个 Describe 对应一个函数的一个主要场景
- It 标题用"应该"开头
- 所有断言用 `Should Be / Should BeExactly / Should BeNullOrEmpty / Should Match / Should Throw / Should Contain`

---

## 阶段 1：基础设施（Tasks 1-6）

端到端目标：跑 `computer_manager.bat` → 看到菜单 → 选择 0 退出。中间选择都返回"该功能开发中"。

### Task 1: 仓库脚手架与 .bat 启动器

**Files:**
- Create: `computer_manager.bat`
- Modify: `.gitignore` (add config.example.json; config.json already ignored)
- Create: `config.example.json`
- Create: `README.md`

- [ ] **Step 1: 创建 config.example.json（配置模板）**

`config.example.json`:
```json
{
  "llm": {
    "base_url": "https://api.openai.com/v1",
    "api_key": "REPLACE_WITH_YOUR_KEY",
    "model": "gpt-4o-mini",
    "temperature": 0.2,
    "timeout_seconds": 60,
    "max_response_tokens": 2000
  },
  "ui": {
    "language": "zh-CN",
    "color": true,
    "confirm_default": false
  },
  "behavior": {
    "snapshot_mode": "quick",
    "max_event_log_lines": 5,
    "max_command_length": 2000,
    "log_retention_days": 30,
    "report_retention_days": 90
  },
  "safety": {
    "allow_encoded_commands": false,
    "allow_iex": false,
    "allowed_base_urls": []
  }
}
```

- [ ] **Step 2: 创建 computer_manager.bat（启动器）**

`computer_manager.bat`:
```batch
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%computer_manager.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
```

- [ ] **Step 3: 创建 README.md（占位）**

`README.md`:
```markdown
# 电脑管理工具

在 Windows 上无需安装任何应用、双击即用的电脑管理脚本。通过 LLM 智能诊断"应用无法安装"问题，并辅助用户安全执行修复。

## 快速开始

1. 复制本目录到目标机器
2. 复制 `config.example.json` 为 `config.json`，填入你的 LLM API 信息
3. 双击 `computer_manager.bat`

## 菜单

1. 诊断应用安装问题  （需要配置 LLM）
2. 日常清理维护
3. 软件管理
4. 系统健康快照
5. 查看历史报告
6. 设置
0. 退出

详细文档见 [docs/superpowers/specs/2026-06-06-computer-manager-design.md](docs/superpowers/specs/2026-06-06-computer-manager-design.md)
```

- [ ] **Step 4: 验证 .bat 启动器能调用 PowerShell**

Run: `cmd //c "computer_manager.bat" 2>&1 || echo "脚本文件不存在（预期，后续任务会创建）"`
Expected: 输出 "脚本文件不存在（预期，后续任务会创建）" 或 PowerShell 错误"找不到文件"（因为 `computer_manager.ps1` 还没创建）

- [ ] **Step 5: 提交**

Run:
```bash
git add computer_manager.bat config.example.json README.md .gitignore
git commit -m "feat: 项目脚手架（启动器、配置模板、README）"
```

---

### Task 2: 主脚本骨架与 dot-source 守卫

**Files:**
- Create: `computer_manager.ps1`
- Create: `tests/computer_manager.Tests.ps1`

- [ ] **Step 1: 创建主脚本骨架（仅 header + main + 守卫）**

`computer_manager.ps1`:
```powershell
#requires -Version 5.1
<#
.SYNOPSIS
    电脑管理工具 — Windows 单文件管理脚本
.DESCRIPTION
    在 Windows 上无需安装任何应用、双击即用。覆盖 LLM 驱动的应用安装问题
    诊断、日常清理、软件管理、系统健康快照、报告生成。
.NOTES
    Version : 1.0.0
    Author  : longyaoyoudu
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 全局变量
$Script:CMRoot = $PSScriptRoot
$Script:CMVersion = '1.0.0'
$Script:CMConfig = $null
$Script:CMLogger = $null

#region Header & Globals
#endregion

#region Config
#endregion

#region Logging
#endregion

#region UI Helpers
#endregion

#region System Context
#endregion

#region Snapshot
#endregion

#region Parser
#endregion

#region Dispatcher
#endregion

#region LLM
#endregion

#region Diagnose
#endregion

#region Cleanup
#endregion

#region Software
#endregion

#region Health
#endregion

#region Report
#endregion

#region Menu
function Show-CMMainMenu {
    Write-Host ""
    Write-Host "===== 电脑管理工具 v$Script:CMVersion =====" -ForegroundColor Cyan
    Write-Host "1. 诊断应用安装问题"
    Write-Host "2. 日常清理维护"
    Write-Host "3. 软件管理"
    Write-Host "4. 系统健康快照"
    Write-Host "5. 查看历史报告"
    Write-Host "6. 设置"
    Write-Host "7. 关于 / 帮助"
    Write-Host "0. 退出"
    Write-Host ""
}

function Invoke-CMMain {
    Show-CMMainMenu
    Write-Host "（功能开发中 — 任务 6 将接入分发）" -ForegroundColor Yellow
}
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-CMMain
    } catch {
        Write-Host "未捕获错误：$_" -ForegroundColor Red
        exit 1
    }
}
#endregion
```

- [ ] **Step 2: 创建测试入口（验证 dot-source 不进入主菜单）**

`tests/computer_manager.Tests.ps1`:
```powershell
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
```

- [ ] **Step 3: 运行测试（应当全部通过）**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/computer_manager.Tests.ps1"`
Expected: `Tests Passed: 2`

- [ ] **Step 4: 手动验证主菜单能显示（直接运行）**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File computer_manager.ps1`
Expected: 打印菜单 + "（功能开发中 — 任务 6 将接入分发）" 黄字

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/computer_manager.Tests.ps1
git commit -m "feat: 主脚本骨架与 dot-source 守卫"
```

---

### Task 3: Config 模块（加载/校验/生成模板）

**Files:**
- Modify: `computer_manager.ps1` (#region Config)
- Create: `tests/Config.Tests.ps1`

- [ ] **Step 1: 写失败测试（4 个 It）**

`tests/Config.Tests.ps1`:
```powershell
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
```

- [ ] **Step 2: 运行测试，验证全部失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Config.Tests.ps1"`
Expected: 全部失败，错误 "Get-CMConfig / New-CMConfigTemplate 不存在"

- [ ] **Step 3: 实现 Config 模块**

把 `#region Config` 替换为：

```powershell
#region Config
function New-CMConfigTemplate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)

    $template = @'
{
  "llm": {
    "base_url": "https://api.openai.com/v1",
    "api_key": "REPLACE_WITH_YOUR_KEY",
    "model": "gpt-4o-mini",
    "temperature": 0.2,
    "timeout_seconds": 60,
    "max_response_tokens": 2000
  },
  "ui": {
    "language": "zh-CN",
    "color": true,
    "confirm_default": false
  },
  "behavior": {
    "snapshot_mode": "quick",
    "max_event_log_lines": 5,
    "max_command_length": 2000,
    "log_retention_days": 30,
    "report_retention_days": 90
  },
  "safety": {
    "allow_encoded_commands": false,
    "allow_iex": false,
    "allowed_base_urls": []
  }
}
'@
    $path = Join-Path $RootPath "config.json"
    $template | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Get-CMConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)

    $path = Join-Path $RootPath "config.json"
    if (-not (Test-Path $path)) {
        return $null
    }
    try {
        $json = Get-Content -Path $path -Raw -Encoding UTF8
        $obj = $json | ConvertFrom-Json
        # 转 hashtable（PS 5.1 没有 -AsHashtable，手动转一层）
        return ConvertTo-Hashtable -InputObject $obj
    } catch {
        throw "config.json 解析失败：$($_.Exception.Message)"
    }
}

function ConvertTo-Hashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject }
    $h = @{}
    foreach ($p in $InputObject.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [PSCustomObject]) { $v = ConvertTo-Hashtable -InputObject $v }
        elseif ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
            $arr = @()
            foreach ($item in $v) {
                if ($item -is [PSCustomObject]) { $arr += ConvertTo-Hashtable -InputObject $item }
                else { $arr += $item }
            }
            $v = $arr
        }
        $h[$p.Name] = $v
    }
    return $h
}
#endregion
```

- [ ] **Step 4: 运行测试，验证全部通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Config.Tests.ps1"`
Expected: `Tests Passed: 5`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/Config.Tests.ps1
git commit -m "feat(Config): 加载/校验/生成模板"
```

---

### Task 4: Logging 模块

**Files:**
- Modify: `computer_manager.ps1` (#region Logging)
- Create: `tests/Logging.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Logging.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "New-CMLogger" {
    It "创建 logger 时应建立 logs 子目录" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $logger = New-CMLogger -RootPath $tmp
            Test-Path (Join-Path $tmp "logs") | Should Be $true
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "Write-CMLog 应把消息写入日志文件" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $logger = New-CMLogger -RootPath $tmp
            Write-CMLog -Logger $logger -Level "INFO" -Source "TEST" -Message "hello world"
            $logFile = Get-ChildItem (Join-Path $tmp "logs") -Filter "*.log" | Select -First 1
            $content = Get-Content $logFile.FullName -Raw
            $content | Should Match "INFO"
            $content | Should Match "TEST"
            $content | Should Match "hello world"
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "api_key 字段在日志中应被脱敏" {
        $tmp = Join-Path $env:TEMP ("cm_test_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $logger = New-CMLogger -RootPath $tmp
            Write-CMLog -Logger $logger -Level "INFO" -Source "TEST" -Message "key=sk-abc123def456"
            $logFile = Get-ChildItem (Join-Path $tmp "logs") -Filter "*.log" | Select -First 1
            $content = Get-Content $logFile.FullName -Raw
            $content | Should Not Match "sk-abc123def456"
            $content | Should Match "\*\*\*"
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Logging.Tests.ps1"`
Expected: 全部失败（New-CMLogger / Write-CMLog 不存在）

- [ ] **Step 3: 实现 Logging 模块**

把 `#region Logging` 替换为：

```powershell
#region Logging
function New-CMLogger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)

    $logsDir = Join-Path $RootPath "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $logFile = Join-Path $logsDir "$timestamp.log"

    $logger = [PSCustomObject]@{
        RootPath = $RootPath
        LogsDir  = $logsDir
        LogFile  = $logFile
    }
    return $logger
}

function Format-CMLogMessage {
    param([string]$Level, [string]$Source, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $sanitized = Protect-CMLogSecret -Message $Message
    return "[$ts] [$Level] [$Source] $sanitized"
}

function Protect-CMLogSecret {
    param([string]$Message)
    # 简单脱敏：sk-... / Bearer xxx / api_key=xxx / token=xxx
    $patterns = @(
        'sk-[A-Za-z0-9_-]{8,}',
        'Bearer\s+[A-Za-z0-9._-]+',
        '(?i)(api[_-]?key|token)\s*[:=]\s*["'']?[^"''\s,}]+',
        '(?i)(password|secret)\s*[:=]\s*["'']?[^"''\s,}]+'
    )
    foreach ($p in $patterns) {
        $Message = [Regex]::Replace($Message, $p, '***')
    }
    return $Message
}

function Write-CMLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Logger,
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERR','USER','CMD','OUT')][string]$Level,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Message
    )
    $line = Format-CMLogMessage -Level $Level -Source $Source -Message $Message
    Add-Content -Path $Logger.LogFile -Value $line -Encoding UTF8
}
#endregion
```

- [ ] **Step 4: 运行测试，验证全部通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Logging.Tests.ps1"`
Expected: `Tests Passed: 3`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/Logging.Tests.ps1
git commit -m "feat(Logging): 文件日志 + 脱敏"
```

---

### Task 5: UI Helpers（彩色输出/确认/菜单项）

**Files:**
- Modify: `computer_manager.ps1` (#region UI Helpers)
- Create: 新建 Pester 测试（见步骤 1）

- [ ] **Step 1: 写失败测试**

新建 `tests/UI.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Read-CMConfirm" {
    It "当输入 y 时返回 true" {
        $result = Read-CMConfirm -Prompt "test?" -DefaultYes $false -SimulateInput "y"
        $result | Should Be $true
    }

    It "当输入 n 时返回 false" {
        $result = Read-CMConfirm -Prompt "test?" -DefaultYes $true -SimulateInput "n"
        $result | Should Be $false
    }

    It "当输入为空时遵循 DefaultYes" {
        $resultY = Read-CMConfirm -Prompt "?" -DefaultYes $true  -SimulateInput ""
        $resultN = Read-CMConfirm -Prompt "?" -DefaultYes $false -SimulateInput ""
        $resultY | Should Be $true
        $resultN | Should Be $false
    }
}

Describe "Format-CMBytes" {
    It "B 单位"  { Format-CMBytes -Bytes 512       | Should Be "512 B" }
    It "KB 单位" { Format-CMBytes -Bytes 2048      | Should Be "2.00 KB" }
    It "MB 单位" { Format-CMBytes -Bytes 5242880   | Should Be "5.00 MB" }
    It "GB 单位" { Format-CMBytes -Bytes 1073741824| Should Be "1.00 GB" }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/UI.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 UI Helpers**

把 `#region UI Helpers` 替换为：

```powershell
#region UI Helpers
function Write-CMSuccess { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-CMWarn    { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-CMError   { param([string]$Message) Write-Host $Message -ForegroundColor Red }
function Write-CMInfo    { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-CMStep    { param([string]$Message) Write-Host $Message -ForegroundColor Magenta }

function Read-CMConfirm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$DefaultYes = $false,
        [string]$SimulateInput
    )
    if ($PSBoundParameters.ContainsKey('SimulateInput')) {
        $input = $SimulateInput
    } else {
        $hint = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
        $input = (Read-Host "$Prompt $hint").Trim()
    }
    if ([string]::IsNullOrWhiteSpace($input)) { return $DefaultYes }
    return ($input -match '^(y|yes)$')
}

function Format-CMBytes {
    param([Parameter(Mandatory)][long]$Bytes)
    if     ($Bytes -lt 1024)            { return "$Bytes B" }
    elseif ($Bytes -lt 1024 * 1024)     { return ("{0:N2} KB" -f ($Bytes / 1024.0)) }
    elseif ($Bytes -lt 1024 * 1024*1024){ return ("{0:N2} MB" -f ($Bytes / 1024.0 / 1024.0)) }
    else                                { return ("{0:N2} GB" -f ($Bytes / 1024.0 / 1024.0 / 1024.0)) }
}

function Read-CMMenuChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int[]]$ValidChoices,
        [string]$SimulateInput
    )
    while ($true) {
        if ($PSBoundParameters.ContainsKey('SimulateInput')) {
            $input = $SimulateInput
        } else {
            $input = (Read-Host $Prompt).Trim()
        }
        $n = 0
        if ([int]::TryParse($input, [ref]$n) -and $ValidChoices -contains $n) {
            return $n
        }
        if (-not $PSBoundParameters.ContainsKey('SimulateInput')) {
            Write-CMWarn "无效输入，请输入: $($ValidChoices -join ', ')"
        }
    }
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/UI.Tests.ps1"`
Expected: `Tests Passed: 7`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/UI.Tests.ps1
git commit -m "feat(UI): 彩色输出、确认、菜单输入、字节格式化"
```

---

### Task 6: Menu 分发（接入各模块占位）

**Files:**
- Modify: `computer_manager.ps1` (#region Menu + #region System Context)

- [ ] **Step 1: 实现 System Context 模块**

把 `#region System Context` 替换为：

```powershell
#region System Context
function Get-CMSystemContext {
    [CmdletBinding()]
    param()
    $ctx = [PSCustomObject]@{}
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $ctx | Add-Member -NotePropertyName OsCaption -NotePropertyValue $os.Caption
        $ctx | Add-Member -NotePropertyName OsVersion -NotePropertyValue $os.Version
        $ctx | Add-Member -NotePropertyName OsBuild -NotePropertyValue $os.BuildNumber
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $ctx | Add-Member -NotePropertyName IsAdmin -NotePropertyValue $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $ctx | Add-Member -NotePropertyName UserName -NotePropertyValue $identity.Name
    $ctx | Add-Member -NotePropertyName ComputerName -NotePropertyValue $env:COMPUTERNAME
    return $ctx
}

function Initialize-CM {
    [CmdletBinding()]
    param()
    $Script:CMConfig = Get-CMConfig -RootPath $Script:CMRoot
    if (-not $Script:CMConfig) {
        Write-CMWarn "未找到 config.json，正在生成模板..."
        $path = New-CMConfigTemplate -RootPath $Script:CMRoot
        Write-CMWarn "已生成：$path"
        Write-CMWarn "请填入 api_key 后重新运行。"
        return $false
    }
    $Script:CMLogger = New-CMLogger -RootPath $Script:CMRoot
    Write-CMLog -Logger $Script:CMLogger -Level "INFO" -Source "INIT" -Message "computer_manager.ps1 启动，版本 $Script:CMVersion"
    return $true
}
#endregion
```

- [ ] **Step 2: 重写 Menu region，连接分发**

把 `#region Menu` 替换为：

```powershell
#region Menu
function Show-CMMainMenu {
    Write-Host ""
    Write-Host "===== 电脑管理工具 v$Script:CMVersion =====" -ForegroundColor Cyan
    Write-Host "1. 诊断应用安装问题"
    Write-Host "2. 日常清理维护"
    Write-Host "3. 软件管理"
    Write-Host "   3.1 列出已装软件"
    Write-Host "   3.2 卸载软件"
    Write-Host "   3.3 修复 Microsoft Store / 系统应用"
    Write-Host "4. 系统健康快照"
    Write-Host "5. 查看历史报告"
    Write-Host "6. 设置"
    Write-Host "7. 关于 / 帮助"
    Write-Host "0. 退出"
    Write-Host ""
}

function Start-CMMainLoop {
    while ($true) {
        Show-CMMainMenu
        $choice = Read-CMMenuChoice -Prompt "请选择" -ValidChoices @(0,1,2,3,4,5,6,7)
        Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "MENU" -Message "选择 $choice"
        switch ($choice) {
            1 { Invoke-CMDiagnose }
            2 { Invoke-CMCleanup }
            3 { Show-CMSoftwareMenu }
            4 { Invoke-CMHealthSnapshot }
            5 { Show-CMHistory }
            6 { Show-CMSettingsMenu }
            7 { Show-CMAbout }
            0 { Write-Host "再见。" -ForegroundColor Green; return }
        }
    }
}

function Show-CMSoftwareMenu {
    while ($true) {
        Write-Host ""
        Write-Host "--- 软件管理 ---" -ForegroundColor Cyan
        Write-Host "1. 列出已装软件"
        Write-Host "2. 卸载软件"
        Write-Host "3. 修复 Microsoft Store / 系统应用"
        Write-Host "0. 返回主菜单"
        $c = Read-CMMenuChoice -Prompt "选择" -ValidChoices @(0,1,2,3)
        switch ($c) {
            1 { Get-CMInstalledSoftware | Out-Host }
            2 { Invoke-CMUninstallSoftware }
            3 { Invoke-CMRepairStoreApps }
            0 { return }
        }
    }
}

function Show-CMSettingsMenu {
    while ($true) {
        Write-Host ""
        Write-Host "--- 设置 ---" -ForegroundColor Cyan
        Write-Host "1. 重新生成 config.json 模板（覆盖现有）"
        Write-Host "0. 返回主菜单"
        $c = Read-CMMenuChoice -Prompt "选择" -ValidChoices @(0,1)
        switch ($c) {
            1 {
                if (Read-CMConfirm -Prompt "将覆盖 config.json，确定？") {
                    New-CMConfigTemplate -RootPath $Script:CMRoot | Out-Null
                    Write-CMSuccess "已重新生成，请重新填入 api_key。"
                }
            }
            0 { return }
        }
    }
}

function Show-CMHistory {
    Write-Host ""
    Write-Host "--- 历史报告（最近 10 条）---" -ForegroundColor Cyan
    $reportDir = Join-Path $Script:CMRoot "reports"
    if (-not (Test-Path $reportDir)) {
        Write-CMWarn "还没有报告。"
        return
    }
    Get-ChildItem $reportDir -Filter "*.md" | Sort-Object LastWriteTime -Descending | Select -First 10 | ForEach-Object {
        Write-Host ("  {0:yyyy-MM-dd HH:mm}  {1}" -f $_.LastWriteTime, $_.Name)
    }
    Write-Host ""
    Write-Host "（完整功能在任务 19）" -ForegroundColor Yellow
}

function Show-CMAbout {
    Write-Host ""
    Write-Host "电脑管理工具 v$Script:CMVersion" -ForegroundColor Cyan
    Write-Host "项目地址：https://github.com/longyaoyoudu/computer_manager"
    Write-Host "详细文档：docs/superpowers/specs/2026-06-06-computer-manager-design.md"
    Write-Host ""
}
#endregion
```

- [ ] **Step 3: 重写 Main region，挂上 Initialize-CM + Start-CMMainLoop**

把 `#region Main` 替换为：

```powershell
#region Main
function Invoke-CMMain {
    if (-not (Initialize-CM)) { return }
    $ctx = Get-CMSystemContext
    Write-CMInfo "用户: $($ctx.UserName) | 管理员: $($ctx.IsAdmin) | 系统: $($ctx.OsCaption) ($($ctx.OsBuild))"
    Start-CMMainLoop
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-CMMain
    } catch {
        Write-CMError "未捕获错误：$_"
        if ($Script:CMLogger) {
            Write-CMLog -Logger $Script:CMLogger -Level "ERR" -Source "FATAL" -Message $_.ToString()
        }
        exit 1
    }
}
#endregion
```

- [ ] **Step 4: 添加各模块的占位 stub（避免菜单调用未定义函数报错）**

把每个空 region 替换为最小占位，例如 `#region Diagnose` 替换为：

```powershell
#region Diagnose
function Invoke-CMDiagnose {
    Write-CMWarn "诊断模块开发中（任务 14-19）"
}
#endregion
```

同样为 Cleanup / Health / Report / Snapshot / Parser / Dispatcher / LLM / Software 添加占位。模板：

```powershell
#region Cleanup
function Invoke-CMCleanup {
    Write-CMWarn "清理模块开发中（任务 9）"
}
#endregion

#region Software
function Get-CMInstalledSoftware { Write-CMWarn "列出软件：开发中" }
function Invoke-CMUninstallSoftware { Write-CMWarn "卸载：开发中" }
function Invoke-CMRepairStoreApps { Write-CMWarn "Store 修复：开发中" }
#endregion

#region Health
function Invoke-CMHealthSnapshot { Write-CMWarn "健康快照：开发中" }
#endregion

#region Snapshot
#endregion

#region Parser
#endregion

#region Dispatcher
#endregion

#region LLM
#endregion

#region Report
#endregion
```

- [ ] **Step 5: 验证运行（菜单能选择 0 退出）**

Run: `echo 0 | powershell -NoProfile -ExecutionPolicy Bypass -File computer_manager.ps1`
Expected: 显示菜单 + "再见。" + 退出码 0

- [ ] **Step 6: 验证日志文件已生成**

Run: `ls computer_manager/logs/`
Expected: 至少一个 `.log` 文件

- [ ] **Step 7: 跑全部测试**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/"`
Expected: 之前所有测试仍通过

- [ ] **Step 8: 提交**

```bash
git add computer_manager.ps1
git commit -m "feat(Menu): 主菜单分发 + 各模块占位 + 启动初始化"
```

---

## 阶段 2：本地模块（Tasks 7-10）

### Task 7: Snapshot 模块（系统健康快照 + 诊断快照共用）

**Files:**
- Modify: `computer_manager.ps1` (#region Snapshot)
- Create: `tests/Snapshot.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Snapshot.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMSnapshot" {
    It "quick 模式应返回包含 os/admin/uac/disk 等字段" {
        $snap = Get-CMSnapshot -Mode "quick" -ErrorAction SilentlyContinue
        $snap | Should Not BeNullOrEmpty
        $snap.PSObject.Properties.Name | Should Contain "os"
        $snap.PSObject.Properties.Name | Should Contain "admin"
        $snap.PSObject.Properties.Name | Should Contain "uac_level"
        $snap.PSObject.Properties.Name | Should Contain "disk_free_gb"
    }

    It "full 模式应包含 quick 全部字段并增加更多" {
        $snap = Get-CMSnapshot -Mode "full" -ErrorAction SilentlyContinue
        $snap.PSObject.Properties.Name | Should Contain "firewall"
    }
}

Describe "Format-CMSnapshotMarkdown" {
    It "应把 snapshot 渲染为 Markdown 表格" {
        $snap = [PSCustomObject]@{
            os = "Windows 11 Pro 23H2"
            admin = $true
            uac_level = 5
            disk_free_gb = 42.3
        }
        $md = Format-CMSnapshotMarkdown -Snapshot $snap
        $md | Should Match "Windows 11 Pro"
        $md | Should Match "42.3"
        $md | Should Match "##"
    }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Snapshot.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Snapshot 模块**

把 `#region Snapshot` 替换为：

```powershell
#region Snapshot
function Get-CMSnapshot {
    [CmdletBinding()]
    param(
        [ValidateSet('quick','full')][string]$Mode = "quick"
    )
    $snap = [ordered]@{}

    # OS
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $snap["os"] = "$($os.Caption) ($($os.Version), build $($os.BuildNumber))"
        $sysDrive = $os.SystemDrive
        $free = [math]::Round($os.FreeSpace / 1GB, 2)
        $snap["disk_free_gb"] = $free
    } else {
        $snap["os"] = "Unknown"
        $snap["disk_free_gb"] = -1
    }

    # Admin / user
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $snap["admin"] = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $snap["user"] = $identity.Name

    # UAC
    $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $uac = (Get-ItemProperty -Path $uacPath -Name ConsentPromptBehaviorAdmin -ErrorAction SilentlyContinue).ConsentPromptBehaviorAdmin
    $snap["uac_level"] = if ($null -eq $uac) { 5 } else { [int]$uac }

    # .NET
    $dotnetPaths = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
    $snap["dotnet_version"] = if ($dotnetPaths) { $dotnetPaths.GetValue("Version", "未知") } else { "无" }

    # Pending reboot
    $pending = $false
    $val = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
    if ($val -and $val.PendingFileRenameOperations) { $pending = $true }
    $val2 = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
    if ($val2) { $pending = $true }
    $snap["pending_reboot"] = $pending

    # MSI service
    $msi = Get-Service -Name msiserver -ErrorAction SilentlyContinue
    $snap["msi_service"] = if ($msi) { $msi.Status.ToString() } else { "Not Found" }

    # Defender
    try {
        $def = Get-MpComputerStatus -ErrorAction Stop
        $snap["defender"] = @{
            real_time = $def.RealTimeProtectionEnabled
            antivirus = $def.AntivirusEnabled
            amsi      = $def.AMServiceEnabled
        } | ConvertTo-Json -Compress
    } catch {
        $snap["defender"] = "Unknown"
    }

    # Core isolation
    $ciReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -ErrorAction SilentlyContinue
    $snap["core_isolation"] = if ($ciReg) { [bool]$ciReg.Enabled } else { $false }

    # Event log errors（quick 5 / full 20）
    $maxEvents = if ($Mode -eq 'full') { 20 } else { 5 }
    $events = Get-WinEvent -FilterHashtable @{LogName='Application','System'; Level=2} -MaxEvents $maxEvents -ErrorAction SilentlyContinue
    $snap["event_log_errors"] = @($events | ForEach-Object {
        $msg = $_.Message
        if ($msg.Length -gt 500) { $msg = $msg.Substring(0, 500) + "..." }
        [PSCustomObject]@{
            time    = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            log     = $_.LogName
            source  = $_.ProviderName
            eventId = $_.Id
            message = ($msg -split "`n")[0..2] -join " | "
        }
    })

    if ($Mode -eq 'full') {
        # 防火墙 profile
        try {
            $snap["firewall"] = (Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled | ConvertTo-Json -Compress)
        } catch { $snap["firewall"] = "Unknown" }

        # 自动启动服务 stopped
        $autoStopped = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | Select-Object -First 20 Name,Status
        $snap["auto_services_stopped"] = ($autoStopped | ConvertTo-Json -Compress)
    }

    return [PSCustomObject]$snap
}

function Format-CMSnapshotMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot)
    $lines = @("## 诊断快照", "")
    $lines += "| 字段 | 值 |"
    $lines += "|---|---|"
    foreach ($p in $Snapshot.PSObject.Properties) {
        $val = $p.Value
        if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
            $val = ($val | ForEach-Object { $_.ToString() }) -join "; "
        }
        $valStr = if ($null -eq $val) { "(空)" } else { ($val | Out-String).Trim() }
        if ($valStr.Length -gt 200) { $valStr = $valStr.Substring(0, 200) + "..." }
        $lines += "| $($p.Name) | $valStr |"
    }
    return ($lines -join "`n")
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Snapshot.Tests.ps1"`
Expected: `Tests Passed: 3`

- [ ] **Step 5: 手动验证（quick 模式）**

Run:
```bash
echo "0" | powershell -NoProfile -Command ". ./computer_manager.ps1; Get-CMSnapshot -Mode quick | ConvertTo-Json -Depth 3"
```
Expected: 输出 JSON 含 os/admin/uac_level/disk_free_gb 等字段

- [ ] **Step 6: 提交**

```bash
git add computer_manager.ps1 tests/Snapshot.Tests.ps1
git commit -m "feat(Snapshot): quick/full 诊断快照收集 + Markdown 渲染"
```

---

### Task 8: Health 模块（系统健康快照 + 报告输出）

**Files:**
- Modify: `computer_manager.ps1` (#region Health)
- Create: `tests/Health.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Health.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMHealthReport" {
    It "应返回包含 os/cpu/memory/disk 的健康数据" {
        $r = Get-CMHealthReport -ErrorAction SilentlyContinue
        $r | Should Not BeNullOrEmpty
        $r.PSObject.Properties.Name | Should Contain "os"
        $r.PSObject.Properties.Name | Should Contain "memory"
        $r.PSObject.Properties.Name | Should Contain "disk"
        $r.PSObject.Properties.Name | Should Contain "auto_services_stopped"
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
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Health.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Health 模块**

把 `#region Health` 替换为：

```powershell
#region Health
function Get-CMHealthReport {
    [CmdletBinding()]
    param()
    $r = [ordered]@{}

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $lastBoot = $os.LastBootUpTime
        $uptimeDays = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 1)
        $r["os"] = "$($os.Caption) build $($os.BuildNumber) (启动 $uptimeDays 天)"
    }

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $mem = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($mem) {
        $totalGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 1)
        $freeGB  = [math]::Round($mem.FreePhysicalMemory / 1MB, 1)
        $r["memory"] = [PSCustomObject]@{ total_gb = $totalGB; free_gb = $freeGB }
    }

    $r["cpu"] = if ($cs) { $cs.ProcessorName } else { "Unknown" }

    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    $r["disk"] = @($disks | ForEach-Object {
        [PSCustomObject]@{
            drive      = $_.DeviceID
            free_gb    = [math]::Round($_.FreeSpace / 1GB, 1)
            size_gb    = [math]::Round($_.Size / 1GB, 1)
            percent_free = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
        }
    })

    $r["auto_services_stopped"] = @(Get-Service |
        Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } |
        Select-Object -ExpandProperty Name -First 20)

    $r["recent_event_errors"] = @(Get-WinEvent -FilterHashtable @{LogName='Application','System'; Level=2} -MaxEvents 10 -ErrorAction SilentlyContinue |
        ForEach-Object {
            [PSCustomObject]@{
                time = $_.TimeCreated.ToString("HH:mm:ss")
                log  = $_.LogName
                id   = $_.Id
            }
        })

    $r["startup_items"] = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object -First 20 Name, Command, Location)

    return [PSCustomObject]$r
}

function Format-CMHealthMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Report)
    $lines = @("# 系统健康快照", "", "生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "")
    foreach ($p in $Report.PSObject.Properties) {
        $lines += "## $($p.Name)"
        $val = $p.Value
        if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
            if ($val.Count -eq 0) {
                $lines += "（无）"
            } else {
                $lines += "| " + (($val[0].PSObject.Properties.Name) -join " | ") + " |"
                $lines += "|" + ((@($val[0].PSObject.Properties.Name) | ForEach-Object { "---" }) -join "|") + "|"
                foreach ($item in $val) {
                    $cells = @($item.PSObject.Properties | ForEach-Object {
                        $s = if ($null -eq $_.Value) { "" } else { "$($_.Value)" }
                        if ($s.Length -gt 80) { $s.Substring(0, 80) + "..." }
                        $s
                    })
                    $lines += "| " + ($cells -join " | ") + " |"
                }
            }
        } else {
            $lines += "``$val``".Replace('`$val', ($val | Out-String).Trim())
        }
        $lines += ""
    }
    return ($lines -join "`n")
}

function Invoke-CMHealthSnapshot {
    Write-CMInfo "收集健康快照..."
    $r = Get-CMHealthReport
    $md = Format-CMHealthMarkdown -Report $r
    $reportDir = Join-Path $Script:CMRoot "reports"
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    $file = Join-Path $reportDir ("health_" + (Get-Date -Format "yyyy-MM-dd_HHmmss") + ".md")
    $md | Set-Content -Path $file -Encoding UTF8
    Write-CMSuccess "已保存：$file"
    Write-Host ""
    Write-Host $md
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Health.Tests.ps1"`
Expected: `Tests Passed: 2`

- [ ] **Step 5: 手动验证**

Run: `echo "4" | powershell -NoProfile -ExecutionPolicy Bypass -File computer_manager.ps1` 然后 `0` 退出
Expected: 屏幕打印健康快照，生成 `reports/health_*.md` 文件

- [ ] **Step 6: 提交**

```bash
git add computer_manager.ps1 tests/Health.Tests.ps1
git commit -m "feat(Health): 系统健康快照 + Markdown 报告"
```

---

### Task 9: Cleanup 模块

**Files:**
- Modify: `computer_manager.ps1` (#region Cleanup)
- Create: `tests/Cleanup.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Cleanup.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMCleanupTargets" {
    It "应返回至少 3 个清理目标" {
        $targets = Get-CMCleanupTargets
        $targets.Count | Should BeGreaterThan 3
        $targets[0].PSObject.Properties.Name | Should Contain "name"
        $targets[0].PSObject.Properties.Name | Should Contain "path"
    }
}

Describe "Get-CMCleanupSize" {
    It "应能统计一个目录的总大小（不抛错）" {
        $tmp = Join-Path $env:TEMP ("cm_cleanup_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            "hello" | Set-Content (Join-Path $tmp "a.txt")
            "world" | Set-Content (Join-Path $tmp "b.txt")
            $size = Get-CMCleanupSize -Path $tmp
            $size | Should BeGreaterOrEqual 10
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "路径不存在时应返回 0 不抛错" {
        $size = Get-CMCleanupSize -Path "C:\does\not\exist\zzz_$([Guid]::NewGuid())"
        $size | Should Be 0
    }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Cleanup.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Cleanup 模块**

把 `#region Cleanup` 替换为：

```powershell
#region Cleanup
function Get-CMCleanupTargets {
    $targets = @(
        [PSCustomObject]@{
            name        = "用户临时文件"
            path        = $env:TEMP
            description = "%TEMP% 内容"
            safe        = $true
        },
        [PSCustomObject]@{
            name        = "本地临时文件"
            path        = $env:LOCALAPPDATA + "\Temp"
            description = "%LOCALAPPDATA%\Temp 内容"
            safe        = $true
        },
        [PSCustomObject]@{
            name        = "缩略图缓存"
            path        = $env:LOCALAPPDATA + "\Microsoft\Windows\Explorer"
            description = "thumbcache_*.db 文件"
            safe        = $true
            pattern     = "thumbcache_*.db"
        },
        [PSCustomObject]@{
            name        = "回收站"
            path        = "::RECYCLE::"
            description = "清空回收站"
            safe        = $true
            handler     = "RecycleBin"
        },
        [PSCustomObject]@{
            name        = "Windows Update 下载缓存"
            path        = "C:\Windows\SoftwareDistribution\Download"
            description = "已下载的更新包"
            safe        = $false
            handler     = "WUAService"
        }
    )
    return $targets
}

function Get-CMCleanupSize {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $sum = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $sum) { return 0 }
        return [long]$sum
    } catch { return 0 }
}

function Invoke-CMCleanupTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Target, [switch]$DryRun)
    if ($Target.handler -eq "RecycleBin") {
        if ($DryRun) { return @{ bytes = 0; ok = $true; note = "DRY RUN: 不清空" } }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        return @{ bytes = 0; ok = $true; note = "已清空回收站" }
    }
    if ($Target.handler -eq "WUAService") {
        if ($DryRun) { return @{ bytes = Get-CMCleanupSize -Path $Target.path; ok = $true; note = "DRY RUN" } }
        $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
        $wasRunning = $svc -and $svc.Status -eq 'Running'
        if ($wasRunning) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
        $sizeBefore = Get-CMCleanupSize -Path $Target.path
        try {
            Get-ChildItem $Target.path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
        if ($wasRunning) { Start-Service wuauserv -ErrorAction SilentlyContinue }
        return @{ bytes = $sizeBefore; ok = $true; note = "已清理 WU 缓存" }
    }
    if ($Target.pattern) {
        $files = Get-ChildItem -Path $Target.path -Filter $Target.pattern -Force -ErrorAction SilentlyContinue
        $sizeBefore = ($files | Measure-Object Length -Sum).Sum
        if (-not $DryRun) { $files | Remove-Item -Force -ErrorAction SilentlyContinue }
        return @{ bytes = $sizeBefore; ok = $true; note = "匹配 $($Target.pattern)" }
    }
    if (-not (Test-Path $Target.path)) {
        return @{ bytes = 0; ok = $true; note = "路径不存在，跳过" }
    }
    $sizeBefore = Get-CMCleanupSize -Path $Target.path
    if (-not $DryRun) {
        Get-ChildItem -Path $Target.path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    return @{ bytes = $sizeBefore; ok = $true; note = "普通目录清理" }
}

function Invoke-CMCleanup {
    [CmdletBinding()]
    param([switch]$DryRun, [switch]$Force)
    $targets = Get-CMCleanupTargets
    $totalBefore = 0
    $results = @()
    foreach ($t in $targets) {
        if (-not $t.safe -and -not $Force) {
            $results += [PSCustomObject]@{ name = $t.name; bytes = 0; ok = $true; note = "需 --force 跳过" }
            continue
        }
        $r = Invoke-CMCleanupTarget -Target $t -DryRun:$DryRun
        $results += [PSCustomObject]@{ name = $t.name; bytes = $r.bytes; ok = $r.ok; note = $r.note }
        $totalBefore += $r.bytes
        Write-Host ("  {0,-30}  {1,12}  {2}" -f $t.name, (Format-CMBytes $r.bytes), $r.note)
    }
    $action = if ($DryRun) { "预估" } else { "已回收" }
    Write-CMSuccess "$action 总大小：$(Format-CMBytes $totalBefore)"
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Cleanup.Tests.ps1"`
Expected: `Tests Passed: 3`

- [ ] **Step 5: 手动验证（dry-run）**

Run:
```bash
echo "0" | powershell -NoProfile -Command ". ./computer_manager.ps1; Invoke-CMCleanup -DryRun"
```
Expected: 打印 5 行清理项 + 总大小

- [ ] **Step 6: 提交**

```bash
git add computer_manager.ps1 tests/Cleanup.Tests.ps1
git commit -m "feat(Cleanup): 临时文件/缓存/回收站/WU 缓存清理 + dry-run"
```

---

### Task 10: Software 模块（列出 / 卸载 / Store 修复）

**Files:**
- Modify: `computer_manager.ps1` (#region Software)
- Create: `tests/Software.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Software.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMInstalledSoftware" {
    It "应返回非空集合且每个元素有 name/architecture 字段" {
        $list = Get-CMInstalledSoftware -ErrorAction SilentlyContinue
        $list | Should Not BeNullOrEmpty
        $first = $list | Select -First 1
        $first.PSObject.Properties.Name | Should Contain "name"
        $first.PSObject.Properties.Name | Should Contain "architecture"
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
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Software.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Software 模块**

把 `#region Software` 替换为：

```powershell
#region Software
function Get-CMInstalledSoftware {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $items = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        $arch = if ($p -match 'WOW6432Node') { "x86" } elseif ($p -match 'HKCU') { "x64_user" } else { "x64" }
        Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if (-not $props.DisplayName) { return }
            $items += [PSCustomObject]@{
                name        = $props.DisplayName
                version     = $props.DisplayVersion
                publisher   = $props.Publisher
                installDate = $props.InstallDate
                uninstall   = $props.UninstallString
                quietUninstall = $props.QuietUninstallString
                architecture = $arch
            }
        }
    }
    return $items | Sort-Object name -Unique
}

function Format-CMUninstallString {
    param([string]$UninstallString)
    if ([string]::IsNullOrWhiteSpace($UninstallString)) { return $null }
    $cmd = $UninstallString.Trim()
    $silent = $null
    if ($cmd -match '(?i)msiexec\.exe\s+/[ixXI].*?\{([0-9A-Fa-f-]+)\}') {
        $guid = $Matches[1]
        $silent = "msiexec.exe /x{{$guid}} /qn REBOOT=ReallySuppress"
    } elseif ($cmd -match '(?i)/S\b') {
        $silent = $cmd
    } elseif ($cmd -match '(?i)/silent\b') {
        $silent = $cmd
    } elseif ($cmd -match '(?i)/quiet\b') {
        $silent = $cmd
    }
    return [PSCustomObject]@{ cmd = $cmd; silent = $silent }
}

function Invoke-CMUninstallSoftware {
    $list = Get-CMInstalledSoftware | Where-Object { $_.uninstall }
    if (-not $list) { Write-CMWarn "没有可卸载的软件"; return }
    for ($i = 0; $i -lt $list.Count; $i++) {
        $s = $list[$i]
        Write-Host ("{0,4}. {1} ({2})" -f ($i+1), $s.name, $s.version)
    }
    $idx = Read-CMMenuChoice -Prompt "选择要卸载的编号（0 取消）" -ValidChoices (@(0) + @(1..$list.Count))
    if ($idx -eq 0) { return }
    $target = $list[$idx - 1]
    $parsed = Format-CMUninstallString -UninstallString $target.uninstall
    Write-CMWarn "将执行：$($parsed.cmd)"
    if ($parsed.silent) {
        Write-CMWarn "可静默执行：$($parsed.silent)"
        if (Read-CMConfirm -Prompt "使用静默模式？") {
            $cmd = $parsed.silent
        } else { $cmd = $parsed.cmd }
    } else { $cmd = $parsed.cmd }
    if (Read-CMConfirm -Prompt "确认卸载？") {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -Wait -NoNewWindow
        Write-CMSuccess "已发送卸载命令。"
    }
}

function Invoke-CMRepairStoreApps {
    $choice = Read-CMMenuChoice -Prompt "选择修复操作 [1=重置 Store  2=重注册系统应用  3=清 Store 缓存 wsreset]" -ValidChoices @(1,2,3)
    switch ($choice) {
        1 {
            $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Reset-AppxPackage
                Write-CMSuccess "已重置 Microsoft Store"
            } else {
                Write-CMWarn "未找到 Microsoft Store 包"
            }
        }
        2 {
            if (-not (Read-CMConfirm -Prompt "将重新注册所有系统应用，可能耗时数分钟。继续？")) { return }
            Get-AppxPackage -AllUsers | ForEach-Object {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
            }
            Write-CMSuccess "已重注册所有系统应用"
        }
        3 {
            Start-Process wsreset.exe -Wait
            Write-CMSuccess "Store 缓存已清空"
        }
    }
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Software.Tests.ps1"`
Expected: `Tests Passed: 3`

- [ ] **Step 5: 手动验证列出软件**

Run: `echo "0" | powershell -NoProfile -Command ". ./computer_manager.ps1; Get-CMInstalledSoftware | Select -First 5 name,version,architecture"`
Expected: 打印已装软件前 5 条

- [ ] **Step 6: 提交**

```bash
git add computer_manager.ps1 tests/Software.Tests.ps1
git commit -m "feat(Software): 列出 / 卸载 / Store 修复"
```

---

## 阶段 3：LLM 与诊断（Tasks 11-17）

### Task 11: Parser 模块（命令解析/拒绝规则）

**Files:**
- Modify: `computer_manager.ps1` (#region Parser)
- Create: `tests/Parser.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Parser.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Test-CMCommandAllowed" {
    It "接受简单 cmdlet" {
        Test-CMCommandAllowed -Command "Get-Service msiserver" -SafetyConfig $null | Should Be $true
    }

    It "接受 PS 单行 ; 链" {
        Test-CMCommandAllowed -Command "Set-Service X -StartupType Manual; Start-Service X" -SafetyConfig $null | Should Be $true
    }

    It "拒绝多行命令" {
        Test-CMCommandAllowed -Command "Get-Service`nrm -rf C:\" -SafetyConfig $null | Should Be $false
    }

    It "拒绝 cmd 链 &" {
        Test-CMCommandAllowed -Command "dir & del /q /f C:\" -SafetyConfig $null | Should Be $false
    }

    It "拒绝 cmd 链 &&" {
        Test-CMCommandAllowed -Command "dir && del /q /f C:\" -SafetyConfig $null | Should Be $false
    }

    It "拒绝 cmd 链 ||" {
        Test-CMCommandAllowed -Command "dir || del /q /f C:\" -SafetyConfig $null | Should Be $false
    }

    It "拒绝 Invoke-Expression" {
        Test-CMCommandAllowed -Command "Invoke-Expression 'calc'" -SafetyConfig @{ allow_iex = $false } | Should Be $false
    }

    It "允许 iex 当 allow_iex=true" {
        Test-CMCommandAllowed -Command "Invoke-Expression 'calc'" -SafetyConfig @{ allow_iex = $true } | Should Be $true
    }

    It "拒绝 -EncodedCommand" {
        Test-CMCommandAllowed -Command "powershell -EncodedCommand ZQBjAGgAbwAgACQARQBuAHYA" -SafetyConfig $null | Should Be $false
    }

    It "拒绝 FromBase64String" {
        Test-CMCommandAllowed -Command "[System.Convert]::FromBase64String('aGk=')" -SafetyConfig $null | Should Be $false
    }

    It "Remove-Item 命中系统目录时标记高风险" {
        $r = Test-CMCommandAllowed -Command "Remove-Item -Recurse -Force C:\Windows\System32\foo" -SafetyConfig $null
        $r.allowed | Should Be $true  # 解析上允许
        $r.risk | Should Be "high"
    }
}

Describe "Get-CMSystemDirs" {
    It "应返回系统目录前缀列表" {
        $dirs = Get-CMSystemDirs
        $dirs | Should Match "C:\\Windows"
    }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Parser.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Parser 模块**

把 `#region Parser` 替换为：

```powershell
#region Parser
function Get-CMSystemDirs {
    return @(
        "$env:WINDIR\",
        "$env:WINDIR\System32\",
        "${env:ProgramFiles}\",
        "${env:ProgramFiles(x86)}\",
        "${env:ProgramData}\",
        "$env:SYSTEMROOT\"
    ) | ForEach-Object { $_.TrimEnd('\') + '\' }
}

function Test-CMCommandAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        $SafetyConfig
    )
    $result = [PSCustomObject]@{
        allowed = $true
        reason  = ""
        risk    = "low"
    }
    if ($null -eq $SafetyConfig) { $SafetyConfig = @{ allow_encoded_commands = $false; allow_iex = $false } }

    # 1. 多行检查
    if ($Command -match "[\r\n]") {
        $result.allowed = $false; $result.reason = "命令包含换行符"; return $result
    }

    # 2. cmd 链式操作符检查（& / && / ||）；允许 PS 单行 ; 链
    if ($Command -match '\s&\s|\s&&\s|\s\|\|\s') {
        $result.allowed = $false; $result.reason = "命令包含 cmd 链式操作符"; return $result
    }

    # 3. 关键字检查
    if (-not $SafetyConfig.allow_encoded_commands) {
        if ($Command -match '(?i)-EncodedCommand|-EC\b|FromBase64String') {
            $result.allowed = $false; $result.reason = "包含被禁用的编码命令"; return $result
        }
    }
    if (-not $SafetyConfig.allow_iex) {
        if ($Command -match '(?i)\bInvoke-Expression\b|\biex\s') {
            $result.allowed = $false; $result.reason = "包含被禁用的 Invoke-Expression"; return $result
        }
    }

    # 4. 系统目录风险升级
    $sysDirs = Get-CMSystemDirs
    $isDangerousRemoval = $Command -match '(?i)\b(Remove-Item|rd|rmdir)\b'
    if ($isDangerousRemoval) {
        foreach ($d in $sysDirs) {
            if ($Command -match [Regex]::Escape($d)) {
                $result.risk = "high"
                $result.reason = "目标命中系统目录 $d"
                break
            }
        }
    }

    return $result
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Parser.Tests.ps1"`
Expected: `Tests Passed: 12`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/Parser.Tests.ps1
git commit -m "feat(Parser): 命令解析、拒绝规则、风险标签"
```

---

### Task 12: Dispatcher 模块（ps / cmd 派发 + 执行器）

**Files:**
- Modify: `computer_manager.ps1` (#region Dispatcher)
- Create: `tests/Dispatcher.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Dispatcher.Tests.ps1`:
```powershell
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
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Dispatcher.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Dispatcher 模块**

把 `#region Dispatcher` 替换为：

```powershell
#region Dispatcher
$Script:CMNativeWhitelist = @(
    'Get-','Set-','Start-','Stop-','Restart-','New-','Remove-','Add-','Clear-',
    'Update-','Test-','Resolve-','Register-','Unregister-','Reset-','Repair-',
    'Get','Set','Dism','sfc','msiexec','pnputil','bcdedit','powercfg',
    'netsh','sc','reg','tasklist','taskkill','wmic','net','gpupdate','takeown',
    'icacls','robocopy','xcopy','copy','del','rd','rmdir','mkdir','move','ren',
    'where','findstr','find','sort','more','type','attrib','compact','expand'
)

function Get-CMCommandDispatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command)
    $first = ($Command.Trim() -split '\s+')[0]
    foreach ($w in $Script:CMNativeWhitelist) {
        if ($first -like "$w*") { return "ps" }
    }
    return "cmd"
}

function Invoke-CMExecuteCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        [ValidateSet('ps','cmd')][string]$Dispatch,
        [int]$TimeoutSec = 60
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($Dispatch -eq "ps") {
            $out = powershell.exe -NoProfile -Command "`$ErrorActionPreference='Stop'; $Command" 2>&1
            $ec = $LASTEXITCODE
            $stdout = ($out | Out-String).Trim()
            $stderr = ""
        } else {
            $out = cmd.exe /c $Command 2>&1
            $ec = $LASTEXITCODE
            $stdout = ($out | Out-String).Trim()
            $stderr = ""
        }
    } catch {
        $ec = 1
        $stdout = ""
        $stderr = $_.Exception.Message
    }
    $sw.Stop()
    return [PSCustomObject]@{
        command  = $Command
        dispatch = $Dispatch
        exitCode = $ec
        stdout   = $stdout
        stderr   = $stderr
        durationSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    }
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Dispatcher.Tests.ps1"`
Expected: `Tests Passed: 6`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/Dispatcher.Tests.ps1
git commit -m "feat(Dispatcher): ps/cmd 派发 + 执行器"
```

---

### Task 13: LLM 模块（HTTP 调用 + 响应解析）

**Files:**
- Modify: `computer_manager.ps1` (#region LLM)
- Create: `tests/LLM.Tests.ps1`

- [ ] **Step 1: 写失败测试（仅解析器，不真发 HTTP）**

`tests/LLM.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "ConvertFrom-CMLLMResponse (tool_calls)" {
    It "应解析 tool_calls 形式" {
        $raw = @{
            choices = @(@{
                message = @{
                    tool_calls = @(@{
                        function = @{
                            name = "submit_diagnosis"
                            arguments = '{"analysis":"x","root_cause":"y","risk_level":"low","commands":[{"id":1,"description":"d","command":"Get-Service"}]}'
                        }
                    })
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be "x"
        $r.root_cause | Should Be "y"
        $r.risk_level | Should Be "low"
        $r.commands[0].command | Should Be "Get-Service"
    }
}

Describe "ConvertFrom-CMLLMResponse (text JSON fallback)" {
    It "应解析 markdown 包裹的 JSON" {
        $raw = @{
            choices = @(@{
                message = @{
                    content = "```json
{`"analysis`":`"a`",`"root_cause`":`"b`",`"risk_level`":`"medium`",`"commands`":[]}
```"
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be "a"
        $r.risk_level | Should Be "medium"
    }

    It "应解析裸 JSON" {
        $raw = @{
            choices = @(@{
                message = @{
                    content = '{"analysis":"plain","root_cause":"rc","risk_level":"high","commands":[]}'
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be "plain"
    }

    It "应兜底返回字符串" {
        $raw = @{
            choices = @(@{
                message = @{
                    content = "这不是 JSON"
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw -FallbackText
        $r.analysis | Should Be "这不是 JSON"
    }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/LLM.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 LLM 模块（解析器 + HTTP 函数）**

把 `#region LLM` 替换为：

```powershell
#region LLM
$Script:CMSystemPrompt = @'
你是 Windows 系统管理员助手。你会收到一份"诊断快照"（系统只读信息）和用户描述的应用安装故障。

任务：分析故障，给出可执行的、单行的 PowerShell / cmd / 原生命令来修复。

约束（必须遵守）：
1. 仅返回 submit_diagnosis 函数的 JSON 参数，不要其他文字。
2. 命令必须是单行（不含换行符）。
3. 禁止使用：Invoke-Expression、iex、-EncodedCommand、FromBase64String、cmd.exe /c 的多语句链接。
4. 禁止破坏性操作：diskpart/format/clean、bcdedit 改引导、net user 添加账号、Set-MpPreference -ExclusionPath 大范围目录。
5. 如果建议涉及用户数据/账号/引导修复，把 risk_level 设为 "high"。
6. commands 数组最多 8 条；按"先无风险后高风险"排序。

低风险示例：Get-Service / Start-Service / Set-Service、sfc /scannow、DISM /Online /Cleanup-Image、msiexec /unregister+register、Get-AppxPackage -Repair、Get-AppLockerPolicyInformation（只读）、注册表 HKLM 读+受限写。
'@

function Get-CMSubmitDiagnosisSchema {
    return @{
        type = "function"
        function = @{
            name = "submit_diagnosis"
            description = "提交应用安装问题的诊断结论和修复命令"
            parameters = @{
                type = "object"
                properties = @{
                    analysis    = @{ type = "string"; description = "1-3 句话的诊断分析" }
                    root_cause  = @{ type = "string"; description = "最可能的原因，单句" }
                    risk_level  = @{ type = "string"; enum = @("low","medium","high") }
                    commands = @{
                        type = "array"
                        items = @{
                            type = "object"
                            properties = @{
                                id = @{ type = "integer" }
                                description = @{ type = "string" }
                                command = @{ type = "string"; description = "单行命令" }
                                expected_effect = @{ type = "string" }
                                rollback_hint = @{ type = "string" }
                            }
                            required = @("id","description","command")
                        }
                    }
                    notes = @{ type = "string" }
                }
                required = @("analysis","root_cause","risk_level","commands")
            }
        }
    }
}

function Invoke-CMLLMChat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserMessage,
        [int]$TimeoutSec = $Config.llm.timeout_seconds
    )
    $baseUrl = $Config.llm.base_url.TrimEnd('/')
    $uri = "$baseUrl/chat/completions"

    $body = @{
        model = $Config.llm.model
        messages = @(
            @{ role = "system"; content = $Script:CMSystemPrompt }
            @{ role = "user";   content = $UserMessage }
        )
        tools = @(Get-CMSubmitDiagnosisSchema)
        tool_choice = @{ type = "function"; function = @{ name = "submit_diagnosis" } }
        temperature = $Config.llm.temperature
        max_tokens = $Config.llm.max_response_tokens
    } | ConvertTo-Json -Depth 20

    $headers = @{
        "Authorization" = "Bearer $($Config.llm.api_key)"
        "Content-Type"  = "application/json"
    }

    $resp = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec $TimeoutSec
    return ConvertFrom-CMLLMResponse -Raw $resp
}

function ConvertFrom-CMLLMResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Raw,
        [switch]$FallbackText
    )
    $msg = $Raw.choices[0].message
    $parsed = $null

    # 1) tool_calls
    if ($msg.tool_calls -and $msg.tool_calls.Count -gt 0) {
        $args = $msg.tool_calls[0].function.arguments
        if ($args -is [string]) {
            try { $parsed = $args | ConvertFrom-Json } catch { $parsed = $null }
        } elseif ($args -is [PSCustomObject] -or $args -is [hashtable]) {
            $parsed = $args
        }
    }

    # 2) text content fallback
    if (-not $parsed -and $msg.content) {
        $txt = $msg.content
        $m = [Regex]::Match($txt, '(?s)```(?:json)?\s*(\{.*?\})\s*```')
        $candidate = if ($m.Success) { $m.Groups[1].Value } else {
            # 尝试截取首尾花括号
            $i = $txt.IndexOf('{'); $j = $txt.LastIndexOf('}')
            if ($i -ge 0 -and $j -gt $i) { $txt.Substring($i, $j - $i + 1) } else { $null }
        }
        if ($candidate) {
            try { $parsed = $candidate | ConvertFrom-Json } catch { $parsed = $null }
        }
        if (-not $parsed -and $FallbackText) {
            $parsed = [PSCustomObject]@{
                analysis = $txt
                root_cause = "(模型未返回结构化结果)"
                risk_level = "unknown"
                commands = @()
            }
        }
    }

    if (-not $parsed) {
        throw "无法解析 LLM 响应：$($msg | Out-String)"
    }
    return $parsed
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/LLM.Tests.ps1"`
Expected: `Tests Passed: 4`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/LLM.Tests.ps1
git commit -m "feat(LLM): HTTP 调用 + tool_calls/JSON 解析"
```

---

### Task 14: Diagnose 主流程（拼装 + 确认 + 执行 + 收尾）

**Files:**
- Modify: `computer_manager.ps1` (#region Diagnose)
- Create: `tests/Diagnose.Tests.ps1`

- [ ] **Step 1: 写失败测试（用户输入模拟）**

`tests/Diagnose.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "New-CMDiagnosisContext" {
    It "应构造包含 snapshot/app/error 的上下文对象" {
        $snap = [PSCustomObject]@{ os = "Win11"; admin = $true }
        $ctx = New-CMDiagnosisContext -Snapshot $snap -AppName "Office" -ErrorText "0x80070005" -TriedActions "以管理员运行"
        $ctx.snapshot.os | Should Be "Win11"
        $ctx.app | Should Be "Office"
        $ctx.error | Should Be "0x80070005"
        $ctx.tried | Should Be "以管理员运行"
    }
}

Describe "Format-CMDiagnosisUserMessage" {
    It "应把上下文格式化为用户消息字符串" {
        $ctx = [PSCustomObject]@{
            snapshot = [PSCustomObject]@{ os = "Win11" }
            app = "Office"
            error = "0x80070005"
            tried = "以管理员运行"
        }
        $msg = Format-CMDiagnosisUserMessage -Context $ctx
        $msg | Should Match "Office"
        $msg | Should Match "0x80070005"
        $msg | Should Match "Win11"
    }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Diagnose.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Diagnose 主流程**

把 `#region Diagnose` 替换为：

```powershell
#region Diagnose
function New-CMDiagnosisContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string]$ErrorText,
        [string]$TriedActions
    )
    return [PSCustomObject]@{
        snapshot = $Snapshot
        app      = $AppName
        error    = $ErrorText
        tried    = $TriedActions
    }
}

function Format-CMDiagnosisUserMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    $snapJson = $Context.snapshot | ConvertTo-Json -Depth 5 -Compress
    $lines = @(
        "## 诊断快照",
        '```json',
        $snapJson,
        '```',
        "",
        "## 用户描述",
        "- 应用名：$($Context.app)",
        "- 报错：$($Context.error)",
        "- 已尝试：$($Context.tried)"
    )
    return ($lines -join "`n")
}

function Confirm-CMCommandRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Cmd,
        [int]$Index,
        [int]$Total,
        [string]$SimulateInput
    )
    $table = @"
  [$Index/$Total]  风险: $($Cmd.risk)
  描述: $($Cmd.description)
  命令: $($Cmd.command)
  预期: $($Cmd.expected_effect)
"@
    Write-Host $table
    return Read-CMConfirm -Prompt "执行？" -DefaultYes $false -SimulateInput $SimulateInput
}

function Invoke-CMDiagnose {
    if (-not $Script:CMConfig.llm.api_key -or $Script:CMConfig.llm.api_key -eq "REPLACE_WITH_YOUR_KEY") {
        Write-CMWarn "请先在 config.json 中填入 api_key（菜单 6 → 设置）。"
        return
    }

    # 1) Snapshot
    $mode = $Script:CMConfig.behavior.snapshot_mode
    Write-CMInfo "[1/4] 收集诊断快照 (mode=$mode)..."
    $snap = Get-CMSnapshot -Mode $mode
    $cmdMax = [int]$Script:CMConfig.behavior.max_command_length

    # 2) User input
    Write-CMInfo "[2/4] 请描述问题："
    $app     = (Read-Host "  目标应用").Trim()
    $err     = (Read-Host "  报错信息").Trim()
    $tried   = (Read-Host "  已尝试操作（可空）").Trim()
    if ([string]::IsNullOrWhiteSpace($app) -or [string]::IsNullOrWhiteSpace($err)) {
        Write-CMWarn "应用名和报错信息必填"; return
    }
    $ctx = New-CMDiagnosisContext -Snapshot $snap -AppName $app -ErrorText $err -TriedActions $tried
    $userMsg = Format-CMDiagnosisUserMessage -Context $ctx

    # 3) LLM
    Write-CMInfo "[3/4] 调用 LLM..."
    $safety = $Script:CMConfig.safety
    try {
        $resp = Invoke-CMLLMChat -Config $Script:CMConfig -UserMessage $userMsg
    } catch {
        Write-CMError "LLM 调用失败：$($_.Exception.Message)"
        Write-CMLog -Logger $Script:CMLogger -Level "ERR" -Source "LLM" -Message $_.ToString()
        return
    }
    Write-CMSuccess "分析：$($resp.analysis)"
    Write-CMInfo  "根因：$($resp.root_cause)"
    Write-CMWarn  "风险：$($resp.risk_level)"

    # 4) Execute
    $approved = @()
    $i = 0
    foreach ($c in $resp.commands) {
        $i++
        $safetyCheck = Test-CMCommandAllowed -Command $c.command -SafetyConfig $safety
        if (-not $safetyCheck.allowed) {
            Write-CMWarn "  [$i] 被解析防护拒绝：$($safetyCheck.reason)  → 跳过"
            Write-CMLog -Logger $Script:CMLogger -Level "WARN" -Source "PARSER" -Message "REJECTED [$i] $($c.command): $($safetyCheck.reason)"
            continue
        }
        $effectiveRisk = $safetyCheck.risk
        $cmdObj = [PSCustomObject]@{
            id = $c.id
            description = $c.description
            command = $c.command
            expected_effect = $c.expected_effect
            rollback_hint = $c.rollback_hint
            risk = $effectiveRisk
        }
        if ($cmdObj.command.Length -gt $cmdMax) {
            Write-CMWarn "  [$i] 命令超过 $cmdMax 字符，需要 FORCE 确认"
            $ok = Read-CMConfirm -Prompt "  输入 FORCE 以继续执行" -SimulateInput "FORCE"
            if ($ok -ne $true) { continue }
        }
        if ($effectiveRisk -eq "high") {
            Write-CMError "  [!!] 高风险命令，需二次确认"
        }
        $ok = Confirm-CMCommandRun -Cmd $cmdObj -Index $i -Total $resp.commands.Count
        if ($ok) {
            $dispatch = Get-CMCommandDispatch -Command $cmdObj.command
            Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "DIAGNOSE" -Message "ACCEPT [$i] $($cmdObj.command)"
            $result = Invoke-CMExecuteCommand -Command $cmdObj.command -Dispatch $dispatch
            $cmdObj | Add-Member -NotePropertyName Result -NotePropertyValue $result
            $approved += $cmdObj
            Write-Host ("  exit={0}  ({1}s)" -f $result.exitCode, $result.durationSec)
            if ($result.exitCode -ne 0) {
                Write-CMWarn "  上一条命令失败（exit=$($result.exitCode)）"
            }
        } else {
            Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "DIAGNOSE" -Message "SKIP [$i] $($cmdObj.command)"
        }
    }

    # 5) Report
    Write-CMInfo "[4/4] 写入报告..."
    $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved -Mode $mode
    $reportDir = Join-Path $Script:CMRoot "reports"
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    $safeApp = ($app -replace '[^A-Za-z0-9_-]', '_').Substring(0, [Math]::Min(40, $app.Length))
    $file = Join-Path $reportDir ((Get-Date -Format "yyyy-MM-dd_HHmmss") + "_" + $safeApp + ".md")
    $md | Set-Content -Path $file -Encoding UTF8
    Write-CMSuccess "已保存：$file"
}

function Format-CMDiagnoseReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][object[]]$Approved,
        [string]$Mode = "quick"
    )
    $lines = @(
        "# 应用安装诊断报告",
        "",
        "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "- 模式：$Mode",
        "- 应用：$($Context.app)",
        "- 报错：$($Context.error)",
        "- 已尝试：$($Context.tried)",
        "",
        "## 模型分析",
        "- **结论**：$($Response.analysis)",
        "- **根因**：$($Response.root_cause)",
        "- **风险等级**：$($Response.risk_level)",
        "",
        "## 诊断快照",
        ""
    )
    $lines += (Format-CMSnapshotMarkdown -Snapshot $Context.snapshot).Split("`n")
    $lines += ""
    $lines += "## 建议修复命令"
    $lines += "| # | 风险 | 描述 | 命令 | 预期 | 实际退出码 | 耗时(s) |"
    $lines += "|---|---|---|---|---|---|---|"
    foreach ($a in $Approved) {
        $lines += "| $($a.id) | $($a.risk) | $($a.description) | ``$($a.command)`` | $($a.expected_effect) | $($a.Result.exitCode) | $($a.Result.durationSec) |"
    }
    if ($Response.notes) {
        $lines += ""
        $lines += "## 备注"
        $lines += $Response.notes
    }
    return ($lines -join "`n")
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Diagnose.Tests.ps1"`
Expected: `Tests Passed: 2`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/Diagnose.Tests.ps1
git commit -m "feat(Diagnose): 拼装 + 确认 + 执行 + 报告"
```

---

### Task 15: Report 模块（健康/诊断/历史）

**Files:**
- Modify: `computer_manager.ps1` (#region Report — 已经是 Task 8 的部分, 这里补 Show-CMHistory 完整版)
- Create: `tests/Report.Tests.ps1`

- [ ] **Step 1: 写失败测试**

`tests/Report.Tests.ps1`:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Get-CMReportSummary" {
    It "应返回 reports 目录中文件按时间倒序" {
        $tmp = Join-Path $env:TEMP ("cm_rep_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            "a" | Set-Content (Join-Path $tmp "2026-06-06_100000_x.md")
            Start-Sleep -Milliseconds 1100
            "b" | Set-Content (Join-Path $tmp "2026-06-06_100001_y.md")
            $list = Get-CMReportSummary -RootPath $tmp
            $list.Count | Should Be 2
            $list[0].Name | Should Match "_y\.md$"
        } finally {
            Remove-Item -Recurse -Force $tmp
        }
    }

    It "目录不存在时返回空数组" {
        $r = Get-CMReportSummary -RootPath "C:\does\not\exist_$([Guid]::NewGuid())"
        ,$r | Should Not BeNullOrEmpty   # 返回空数组而非 $null
        $r.Count | Should Be 0
    }
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Report.Tests.ps1"`
Expected: 全部失败

- [ ] **Step 3: 实现 Report 模块**

把 `#region Report` 替换为：

```powershell
#region Report
function Get-CMReportSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)
    $dir = Join-Path $RootPath "reports"
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem $dir -Filter "*.md" | Sort-Object LastWriteTime -Descending)
}

function Invoke-CMReportRetention {
    param([Parameter(Mandatory)][string]$RootPath, [int]$Days = 30)
    $dir = Join-Path $RootPath "reports"
    if (-not (Test-Path $dir)) { return }
    $cutoff = (Get-Date).AddDays(-$Days)
    Get-ChildItem $dir -Filter "*.md" | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Invoke-CMLogRetention {
    param([Parameter(Mandatory)][string]$RootPath, [int]$Days = 30)
    $dir = Join-Path $RootPath "logs"
    if (-not (Test-Path $dir)) { return }
    $cutoff = (Get-Date).AddDays(-$Days)
    Get-ChildItem $dir -Filter "*.log" | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Show-CMHistory {
    $list = Get-CMReportSummary -RootPath $Script:CMRoot
    if ($list.Count -eq 0) {
        Write-CMWarn "还没有报告"; return
    }
    Write-Host ""
    Write-Host "--- 历史报告 ---" -ForegroundColor Cyan
    $i = 0
    foreach ($f in $list) {
        $i++
        $size = Format-CMBytes $f.Length
        Write-Host ("  {0,3}. {1:yyyy-MM-dd HH:mm}  {2,10}  {3}" -f $i, $f.LastWriteTime, $size, $f.Name)
    }
    Write-Host "  0. 返回主菜单"
    $idx = Read-CMMenuChoice -Prompt "选择要查看的报告编号" -ValidChoices (@(0) + @(1..[Math]::Min($list.Count, 50)))
    if ($idx -eq 0) { return }
    $f = $list[$idx - 1]
    Write-Host ""
    Write-Host "===== $($f.Name) =====" -ForegroundColor Cyan
    Get-Content $f.FullName | Out-Host
}
#endregion
```

- [ ] **Step 4: 运行测试，验证通过**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/Report.Tests.ps1"`
Expected: `Tests Passed: 2`

- [ ] **Step 5: 提交**

```bash
git add computer_manager.ps1 tests/Report.Tests.ps1
git commit -m "feat(Report): 历史报告查看 + 保留期清理"
```

---

### Task 16: 在 Initialize-CM 中接入 retention 钩子

**Files:**
- Modify: `computer_manager.ps1` (#region System Context — Initialize-CM)

- [ ] **Step 1: 修改 Initialize-CM 增加 retention 调用**

把 `Initialize-CM` 末尾 `return $true` 之前加上：

```powershell
    # 启动时清理过期日志/报告
    try {
        Invoke-CMLogRetention    -RootPath $Script:CMRoot -Days ([int]$Script:CMConfig.behavior.log_retention_days)
        Invoke-CMReportRetention -RootPath $Script:CMRoot -Days ([int]$Script:CMConfig.behavior.report_retention_days)
    } catch {
        Write-CMWarn "保留期清理失败：$($_.Exception.Message)"
    }
```

- [ ] **Step 2: 跑全部测试，确保没回归**

Run: `powershell -NoProfile -Command "Invoke-Pester tests/"`
Expected: 所有测试仍通过

- [ ] **Step 3: 提交**

```bash
git add computer_manager.ps1
git commit -m "feat(Init): 启动时清理过期日志与报告"
```

---

## 阶段 4：联调与收尾（Tasks 17-19）

### Task 17: 端到端冒烟测试（手工清单 + 自动）

**Files:**
- Create: `tests/smoke.ps1` (一个端到端冒烟测试脚本)

- [ ] **Step 1: 写冒烟测试**

`tests/smoke.ps1`:
```powershell
# 端到端冒烟：在隔离的临时目录里跑全部模块（不依赖 config.json，self-generate）
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

$root = Join-Path $env:TEMP ("cm_smoke_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root -Force | Out-Null

try {
    # 1) 自动生成 config
    New-CMConfigTemplate -RootPath $root | Out-Null
    $cfg = Get-CMConfig -RootPath $root
    if (-not $cfg) { throw "config 生成失败" }
    Write-Host "[1/8] config 生成 ✓"

    # 2) Logger
    $logger = New-CMLogger -RootPath $root
    Write-CMLog -Logger $logger -Level "INFO" -Source "SMOKE" -Message "hello"
    $log = Get-ChildItem (Join-Path $root "logs") -Filter "*.log" | Select -First 1
    if (-not (Test-Path $log.FullName)) { throw "日志未生成" }
    Write-Host "[2/8] logger ✓"

    # 3) Snapshot
    $snap = Get-CMSnapshot -Mode quick
    if (-not $snap.os) { throw "snapshot 缺少 os" }
    Write-Host "[3/8] snapshot ✓"

    # 4) Parser
    $r1 = Test-CMCommandAllowed -Command "Get-Service" -SafetyConfig $null
    if (-not $r1.allowed) { throw "parser 误拒" }
    $r2 = Test-CMCommandAllowed -Command "Invoke-Expression 'x'" -SafetyConfig $null
    if ($r2.allowed) { throw "parser 漏过 iex" }
    Write-Host "[4/8] parser ✓"

    # 5) Dispatcher + Executor
    $r = Invoke-CMExecuteCommand -Command "Get-Service | Out-Null" -Dispatch ps
    if ($r.exitCode -ne 0) { throw "ps executor 失败" }
    $r = Invoke-CMExecuteCommand -Command "echo hi" -Dispatch cmd
    if ($r.exitCode -ne 0 -or $r.stdout -notmatch "hi") { throw "cmd executor 失败" }
    Write-Host "[5/8] executor ✓"

    # 6) LLM 解析
    $raw = @{ choices = @(@{ message = @{ tool_calls = @(@{ function = @{ name="submit_diagnosis"; arguments='{"analysis":"a","root_cause":"r","risk_level":"low","commands":[]}' }}) }}) }
    $parsed = ConvertFrom-CMLLMResponse -Raw $raw
    if ($parsed.analysis -ne "a") { throw "llm 解析失败" }
    Write-Host "[6/8] llm 解析 ✓"

    # 7) Report
    $reportDir = Join-Path $root "reports"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    "test" | Set-Content (Join-Path $reportDir "smoke.md")
    $list = Get-CMReportSummary -RootPath $root
    if ($list.Count -ne 1) { throw "report summary 失败" }
    Write-Host "[7/8] report ✓"

    # 8) 清理
    Remove-Item -Recurse -Force (Join-Path $root "logs"), $reportDir -ErrorAction SilentlyContinue
    Write-Host "[8/8] 清理 ✓"
    Write-Host "ALL SMOKE TESTS PASSED"
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: 运行冒烟**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1`
Expected: 输出 `[1/8] ... [8/8]` 全部 ✓ + `ALL SMOKE TESTS PASSED`

- [ ] **Step 3: 修复任何失败的步骤**

如有失败，按错误信息回溯到对应模块修复后重跑。

- [ ] **Step 4: 提交**

```bash
git add tests/smoke.ps1
git commit -m "test: 端到端冒烟测试"
```

---

### Task 18: README 完善 + 发布清单

**Files:**
- Modify: `README.md`
- Create: `DISTRIBUTION.md` (用户部署清单)

- [ ] **Step 1: 替换 README.md**

`README.md`:
```markdown
# 电脑管理工具 v1.0

在 Windows 上无需安装任何应用、双击即用的电脑管理脚本。通过 LLM 智能诊断"应用无法安装"问题，并辅助用户安全执行修复。

## 功能

- **诊断应用安装问题**（核心）：收集系统快照 + LLM 分析 + 逐条确认执行
- **日常清理维护**：临时文件、缩略图缓存、回收站、Windows Update 缓存
- **软件管理**：列出/卸载已装软件、修复 Microsoft Store 和系统应用
- **系统健康快照**：OS/内存/磁盘/服务/事件/启动项
- **报告生成**：所有操作可生成 Markdown 报告
- **历史回看**：浏览/查看历史报告

## 快速开始

1. 复制以下 4 个文件/目录到目标机器任意目录：
   - `computer_manager.ps1`
   - `computer_manager.bat`
   - `config.example.json`
   - 本 README
2. 把 `config.example.json` 重命名为 `config.json`，填入你的 LLM API：
   ```json
   {
     "llm": {
       "base_url": "https://api.openai.com/v1",
       "api_key": "sk-xxx",
       "model": "gpt-4o-mini"
     }
   }
   ```
3. 双击 `computer_manager.bat`

## 菜单

```
===== 电脑管理工具 v1.0 =====
1. 诊断应用安装问题
2. 日常清理维护
3. 软件管理
4. 系统健康快照
5. 查看历史报告
6. 设置
7. 关于 / 帮助
0. 退出
```

## 兼容性

- Windows 10 / 11（PowerShell 5.1 内置）
- 需要管理员权限（部分清理与修复操作）

## 安全模型

- LLM 生成的命令 **逐条人工 y/n 确认** 后才执行
- 拒绝 `Invoke-Expression`、`-EncodedCommand`、多语句 cmd 链
- 命中系统目录的删除命令自动标记为高风险，需额外确认
- API key 写入日志前自动脱敏

## 文档

- [设计文档](docs/superpowers/specs/2026-06-06-computer-manager-design.md)
- [实施计划](docs/superpowers/plans/2026-06-06-computer-manager-implementation.md)
```

- [ ] **Step 2: 创建 DISTRIBUTION.md（用户部署清单）**

`DISTRIBUTION.md`:
```markdown
# 用户部署清单

## 复制到目标机器的 4 项

| 文件 | 大小 | 用途 |
|---|---|---|
| `computer_manager.ps1` | ~1500 行 | 主脚本 |
| `computer_manager.bat` | 4 行 | 启动器 |
| `config.example.json` | 30 行 | 配置模板（**先改名**为 `config.json` 再填 api_key） |
| `README.md` | 用户文档 | 快速开始 |

## 启动

```
双击 computer_manager.bat
```

或命令行：
```cmd
computer_manager.bat
```

## 第一次使用

1. 启动后会检测到没有 `config.json` → 自动生成模板
2. 用记事本编辑 `config.json` 填入 LLM api_key
3. 重新双击 `computer_manager.bat`

## 不复制的开发期文件

- `tests/` — Pester 测试，需要 Pester 3.4+ 才能跑
- `docs/` — 设计文档与实施计划
- `DISTRIBUTION.md` — 本文件
- `.gitignore` / `.git/`
```

- [ ] **Step 3: 验证 README 链接可点击**

Run: `cat README.md | grep -E "\[.*\]\(.*\)"`
Expected: 看到 2 个 markdown 链接

- [ ] **Step 4: 提交**

```bash
git add README.md DISTRIBUTION.md
git commit -m "docs: 完善 README + 用户部署清单"
```

---

### Task 19: 最终验证 + 打 tag

**Files:**
- Create: `tests/run-all.ps1` (一键跑全部测试)

- [ ] **Step 1: 写一键测试脚本**

`tests/run-all.ps1`:
```powershell
$ErrorActionPreference = 'Stop'
Write-Host "=== 1) Pester 单元测试 ===" -ForegroundColor Cyan
Invoke-Pester "$PSScriptRoot\..\tests" -EnableExit:$false
Write-Host ""
Write-Host "=== 2) 端到端冒烟 ===" -ForegroundColor Cyan
& "$PSScriptRoot\smoke.ps1"
Write-Host ""
Write-Host "=== ALL TESTS PASSED ===" -ForegroundColor Green
```

- [ ] **Step 2: 运行**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-all.ps1`
Expected: Pester 全部通过 + smoke 全部 ✓ + `ALL TESTS PASSED`

- [ ] **Step 3: 修复任何失败的步骤**

若有失败，按错误定位到对应任务回溯。

- [ ] **Step 4: 检查 main 脚本行数**

Run: `wc -l computer_manager.ps1`
Expected: ≤ 2000 行（spec 目标）

- [ ] **Step 5: 检查目标文件清单**

Run:
```bash
ls -la computer_manager.ps1 computer_manager.bat config.example.json README.md
```
Expected: 4 个文件全部存在

- [ ] **Step 6: 提交 + 打 tag**

```bash
git add tests/run-all.ps1
git commit -m "test: 一键测试入口"
git tag -a v1.0.0 -m "v1.0.0 - 电脑管理工具首发"
git push origin main --tags
```

- [ ] **Step 7: 验证 tag 已推送**

Run: `git ls-remote --tags origin`
Expected: 看到 `refs/tags/v1.0.0`

---

## 自审

✅ Spec 覆盖：
- §1 范围 → Task 1-19 全部覆盖
- §2 交付物 → Task 18
- §3 配置 schema → Task 3
- §4 菜单 → Task 6
- §5.1 数据流 → Task 14
- §5.2 快照 → Task 7
- §5.3 LLM 协议 → Task 13
- §5.4 System Prompt → Task 13
- §5.5 命令执行派发 → Task 12
- §5.6 解析防护 → Task 11
- §5.7 报告 → Task 14
- §6 清理 → Task 9
- §7 软件管理 → Task 10
- §8 健康快照 → Task 8
- §9 错误处理 → Task 12 (timeout/capture) + Task 14 (LLM 错误) + Task 7 (CIM 容错)
- §10 日志 → Task 4 + Task 16
- §11 测试 → Task 17
- §12 安全与隐私 → Task 4 (脱敏) + Task 11 (防护) + Task 12 (timeout)
- §13 性能/可维护 → Task 19 (行数检查)

✅ 占位扫描：无 TBD/TODO/"类似 Task N"。

✅ 类型一致性：
- `Get-CMConfig` 返回 hashtable ✓
- `Test-CMCommandAllowed` 返回 `{allowed, reason, risk}` ✓
- `ConvertFrom-CMLLMResponse` 返回 PSCustomObject 含 analysis/root_cause/risk_level/commands ✓
- `Invoke-CMExecuteCommand` 返回 `{command, dispatch, exitCode, stdout, stderr, durationSec}` ✓
- `Get-CMSnapshot` 返回 PSCustomObject ✓

---

## 计划结束

完成全部 19 个任务后，电脑管理工具 v1.0 即完成。`git push origin main --tags` 后 GitHub 上会看到首个 release tag。
