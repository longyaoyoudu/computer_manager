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



