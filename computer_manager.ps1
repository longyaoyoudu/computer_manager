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
    # 使用 UTF8Encoding($false) 避免 Add-Content 在每行前追加 BOM（PS 5.1 行为）
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($Logger.LogFile, "$line`n", $utf8NoBom)
}
#endregion

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

#region Snapshot
#endregion

#region Parser
#endregion

#region Dispatcher
#endregion

#region LLM
#endregion

#region Diagnose
function Invoke-CMDiagnose {
    Write-CMWarn "诊断模块开发中（任务 14-19）"
}
#endregion

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

#region Report
#endregion

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
