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
    # 启动时清理过期日志/报告
    try {
        $logDays   = if ($Script:CMConfig.behavior.log_retention_days)   { [int]$Script:CMConfig.behavior.log_retention_days }   else { 30 }
        $reportDays = if ($Script:CMConfig.behavior.report_retention_days) { [int]$Script:CMConfig.behavior.report_retention_days } else { 90 }
        Invoke-CMLogRetention    -RootPath $Script:CMRoot -Days $logDays
        Invoke-CMReportRetention -RootPath $Script:CMRoot -Days $reportDays
    } catch {
        Write-CMWarn "保留期期清理失败：$($_.Exception.Message)"
    }
    return $true
}
#endregion

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
        if ($os.PSObject.Properties.Name -contains 'FreeSpace') {
            $free = [math]::Round($os.FreeSpace / 1GB, 2)
        } else {
            $ld = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($sysDrive)'" -ErrorAction SilentlyContinue
            $free = if ($ld -and $ld.FreeSpace) { [math]::Round($ld.FreeSpace / 1GB, 2) } else { -1 }
        }
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
    if ($dotnetPaths) {
        $versions = @($dotnetPaths | ForEach-Object { $_.GetValue("Version", $null) } | Where-Object { $_ })
        $snap["dotnet_version"] = if ($versions.Count -gt 0) {
            ($versions | Sort-Object { [Version]$_ } -Descending | Select-Object -First 1)
        } else { "未知" }
    } else {
        $snap["dotnet_version"] = "无"
    }

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

    # Event log errors (quick 5 / full 20)
    $maxEvents = if ($Mode -eq 'full') { 20 } else { 5 }
    $events = Get-WinEvent -FilterHashtable @{LogName='Application','System'; Level=2} -MaxEvents $maxEvents -ErrorAction SilentlyContinue
    $snap["event_log_errors"] = @($events | ForEach-Object {
        $msg = $_.Message
        if ($msg -and $msg.Length -gt 500) { $msg = $msg.Substring(0, 500) + "..." }
        [PSCustomObject]@{
            time    = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            log     = $_.LogName
            source  = $_.ProviderName
            eventId = $_.Id
            message = @($msg -split "`n" | Select-Object -First 3) -join " | "
        }
    })

    if ($Mode -eq 'full') {
        # Firewall profile
        try {
            $snap["firewall"] = (Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled | ConvertTo-Json -Compress)
        } catch { $snap["firewall"] = "Unknown" }

        # Auto-start services stopped
        $autoStopped = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | Select-Object -First 20 Name,Status
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
        reason  = ''
        risk    = 'low'
    }
    if ($null -eq $SafetyConfig) { $SafetyConfig = @{ allow_encoded_commands = $false; allow_iex = $false } }
    if (-not $SafetyConfig.ContainsKey('allow_encoded_commands')) { $SafetyConfig['allow_encoded_commands'] = $false }
    if (-not $SafetyConfig.ContainsKey('allow_iex')) { $SafetyConfig['allow_iex'] = $false }

    # Internal helper: reject + log
    $rejectScript = {
        param($reason)
        $result.allowed = $false
        $result.reason = $reason
        if ($Script:CMLogger) {
            try { Write-CMLog -Logger $Script:CMLogger -Level 'WARN' -Source 'PARSER' -Message "rejected: $Command reason=$reason" } catch {}
        }
        return $result
    }

    # 1. Multi-line
    if ($Command -match '[\r\n]') {
        return (& $rejectScript '命令包含换行符')
    }

    # 2. Quote-aware chain operator check
    # Conservative: check the raw command. `cmd /c "dir & del"` would still
    # be a chain at the OS level, so we keep the `&` detection strict.
    # The regex matches `&` (and `&&`, `||`) only when surrounded by whitespace,
    # which avoids false positives on URL params, paths, etc.
    if ($Command -match '\s&\s|\s&&\s|\s\|\|\s') {
        return (& $rejectScript '命令包含 cmd 链式操作符')
    }

    # 3. Encoded command
    if (-not $SafetyConfig['allow_encoded_commands']) {
        if ($Command -match '(?i)-EncodedCommand|-EC\b|FromBase64String') {
            return (& $rejectScript '包含被禁用的编码命令')
        }
    }

    # 4. Invoke-Expression (use word boundary to catch iex;calc, iex|cmd)
    if (-not $SafetyConfig['allow_iex']) {
        if ($Command -match '(?i)\bInvoke-Expression\b|\biex\b') {
            return (& $rejectScript '包含被禁用的 Invoke-Expression')
        }
    }

    # 5. System dir risk: also check for `del` and `erase` CMD built-ins
    $sysDirs = Get-CMSystemDirs
    $isDangerousRemoval = $Command -match '(?i)\b(Remove-Item|rd|rmdir|del|erase)\b'
    if ($isDangerousRemoval) {
        foreach ($d in $sysDirs) {
            if ($Command -match [Regex]::Escape($d)) {
                $result.risk = 'high'
                $result.reason = '目标命令系统目录 ' + $d
                break
            }
        }
    }

    return $result
}
#endregion

#region Dispatcher
$Script:CMNativeWhitelist = @(
    'Get-','Set-','Start-','Stop-','Restart-','New-','Remove-','Add-','Clear-',
    'Update-','Test-','Resolve-','Register-','Unregister-','Reset-','Repair-',
    'Get','Set','Dism','sfc','msiexec','pnputil','bcdedit','powercfg',
    'netsh','reg','wmic','net','gpupdate','takeown',
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
    if ($Script:CMLogger) {
        try { Write-CMLog -Logger $Script:CMLogger -Level "CMD" -Source "DISPATCH" -Message "${Dispatch}: $Command" } catch {}
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($Dispatch -eq "ps") {
            $out = powershell.exe -NoProfile -Command "`$ErrorActionPreference='Stop'; $Command" 2>&1
            $ec = $LASTEXITCODE
            $stdout = ($out | Out-String).Trim()
            $stderr = "(merged into stdout; see .stdout)"
        } else {
            $out = cmd.exe /c $Command 2>&1
            $ec = $LASTEXITCODE
            $stdout = ($out | Out-String).Trim()
            $stderr = "(merged into stdout; see .stdout)"
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

# StrictMode-safe property accessor shared across LLM helpers.
# hashtable uses ContainsKey; PSObject uses Properties.Name.
function Get-CMSafeProp {
    [CmdletBinding()]
    param($obj, [Parameter(Mandatory)][string]$name)
    if ($obj -is [hashtable]) {
        if ($obj.ContainsKey($name)) { return $obj[$name] } else { return $null }
    } elseif ($obj) {
        $names = $obj.PSObject.Properties.Name
        if ($names -contains $name) { return $obj.$name } else { return $null }
    } else {
        return $null
    }
}

function Build-CMLLMRequestBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserMessage
    )
    $body = @{
        model       = $Config.llm.model
        messages    = @(
            @{ role = "system"; content = $Script:CMSystemPrompt }
            @{ role = "user";   content = $UserMessage }
        )
        tools       = @(Get-CMSubmitDiagnosisSchema)
        tool_choice = @{ type = "function"; function = @{ name = "submit_diagnosis" } }
        temperature = $Config.llm.temperature
        max_tokens  = $Config.llm.max_response_tokens
    }
    # Optional passthrough for vendor-specific knobs.
    # MiniMax-M3 supports `thinking: {type: "disabled"}` to skip the <think> reasoning block.
    # MiniMax-M2.x ignores it. Other OpenAI-compatible providers ignore unknown fields.
    # Use ContainsKey for hashtables (PSObject.Properties.Name on a hashtable returns
    # type metadata like Keys/Count, not its own key-value pairs).
    $hasThinking = $false
    if ($Config.llm -is [hashtable]) {
        $hasThinking = $Config.llm.ContainsKey('thinking')
    } else {
        $hasThinking = $Config.llm.PSObject.Properties.Name -contains 'thinking'
    }
    if ($hasThinking -and $Config.llm.thinking) {
        $body.thinking = $Config.llm.thinking
    }
    return $body | ConvertTo-Json -Depth 20
}

# Detect the "model thought but never produced output" failure mode.
# Returns $true when the response has no tool_calls and the content is empty
# or only contains a <think>...</think> block. The caller should retry with a
# hint in such cases.
function Test-CMLLMResponseThinkingOnly {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Raw)

    $choices = Get-CMSafeProp $Raw 'choices'
    $firstChoice = if ($choices -is [System.Collections.IList] -and $choices.Count -gt 0) { $choices[0] } elseif ($choices) { $choices } else { $null }
    $msg = if ($firstChoice) { Get-CMSafeProp $firstChoice 'message' } else { $null }
    if (-not $msg) { return $false }

    # Any tool_calls means the model emitted structured output - not thinking-only.
    if (Get-CMSafeProp $msg 'tool_calls') { return $false }

    $content = Get-CMSafeProp $msg 'content'
    if (-not $content) { return $true }

    $stripped = [Regex]::Replace([string]$content, '(?s)<think>.*?</think>', '').Trim()
    return [string]::IsNullOrWhiteSpace($stripped)
}

function Invoke-CMLLMChat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserMessage,
        [int]$TimeoutSec = $Config.llm.timeout_seconds,
        [switch]$FallbackText,
        [int]$MaxRetries = 1
    )
    $baseUrl = $Config.llm.base_url.TrimEnd('/')
    $uri = "$baseUrl/chat/completions"

    $headers = @{
        "Authorization" = "Bearer $($Config.llm.api_key)"
        "Content-Type"  = "application/json"
    }

    $currentMessage = $UserMessage
    $resp = $null
    for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
        $body = Build-CMLLMRequestBody -Config $Config -UserMessage $currentMessage
        try {
            $resp = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec $TimeoutSec -ErrorAction Stop
        } catch {
            if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "ERR" -Source "LLM" -Message "HTTP 调用 失败: $($_.Exception.Message)" } catch {} }
            throw "LLM HTTP 调用失败：$($_.Exception.Message)"
        }

        if ($attempt -le $MaxRetries -and (Test-CMLLMResponseThinkingOnly -Raw $resp)) {
            if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "WARN" -Source "LLM" -Message "第 $attempt 次响应只有 <think> 无结构化输出，追加 hint 重试" } catch {} }
            $currentMessage = "$UserMessage`n`n[系统重试提示] 你刚才只输出了 <think> 思考块却没有调用 submit_diagnosis 函数。本轮请直接调用 submit_diagnosis 函数提交结构化结果（analysis / root_cause / risk_level / commands），不要再输出 <think>。"
            continue
        }

        return ConvertFrom-CMLLMResponse -Raw $resp -FallbackText:$FallbackText
    }

    # Unreachable in practice, but keeps the linter happy if control flow analysis misses the return above.
    return ConvertFrom-CMLLMResponse -Raw $resp -FallbackText:$FallbackText
}

function ConvertFrom-CMLLMResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Raw,
        [switch]$FallbackText
    )

    $choices = Get-CMSafeProp $Raw 'choices'
    $firstChoice = if ($choices -is [System.Collections.IList] -and $choices.Count -gt 0) { $choices[0] } elseif ($choices) { $choices } else { $null }
    $msg = if ($firstChoice) { Get-CMSafeProp $firstChoice 'message' } else { $null }
    $parsed = $null
    $parseError = $null

    # 1) tool_calls
    $tc = Get-CMSafeProp $msg 'tool_calls'
    if ($tc) {
        # PowerShell unwraps single-element arrays; if it is an array, take the first; otherwise use as-is.
        $tc0 = if ($tc -is [System.Collections.IList] -and $tc.Count -gt 0) { $tc[0] } else { $tc }
        $func = Get-CMSafeProp $tc0 'function'
        $args = if ($func) { Get-CMSafeProp $func 'arguments' } else { $null }
        if ($args -is [string]) {
            try { $parsed = $args | ConvertFrom-Json -ErrorAction Stop } catch { $parseError = "函数 调用 失败: $($_.Exception.Message)" }
        } elseif ($args -is [PSCustomObject] -or $args -is [hashtable]) {
            $parsed = $args
        }
    }

    # 2) text content fallback
    if (-not $parsed) {
        $txt = Get-CMSafeProp $msg 'content'
        if ($txt) {
            # Strip reasoning blocks emitted by some models so they don't pollute JSON extraction.
            $clean = [Regex]::Replace([string]$txt, '(?s)<think>.*?</think>', '')

            $candidate = $null
            $m = [Regex]::Match($clean, '(?s)```(?:json)?\s*(\{.*?\})\s*```')
            if ($m.Success) {
                $candidate = $m.Groups[1].Value
            } elseif ($clean) {
                # Fallback: enumerate balanced top-level JSON-like substrings and try each
                # until one parses. This is robust against stray braces in prose (PowerShell
                # scriptblocks like `{$_.x}`) which would otherwise be picked as the "first"
                # match by a naive IndexOf/LastIndexOf strategy.
                $candidates = Get-CMAllBalancedJsonObjects -Text $clean
                foreach ($cand in $candidates) {
                    try {
                        $parsed = $cand | ConvertFrom-Json -ErrorAction Stop
                        $candidate = $cand
                        break
                    } catch {
                        if (-not $parseError) { $parseError = "文本 内容 解析: $($_.Exception.Message)" }
                    }
                }
            }
            if ($candidate -and -not $parsed) {
                try { $parsed = $candidate | ConvertFrom-Json -ErrorAction Stop } catch { if (-not $parseError) { $parseError = "文本 内容 解析: $($_.Exception.Message)" } }
            }
            if (-not $parsed -and $FallbackText) {
                # Strip any <think>...</think> blocks so the user sees clean text rather
                # than a wall of model reasoning. Fall back to the original text if
                # stripping leaves nothing useful.
                $displayText = [Regex]::Replace([string]$txt, '(?s)<think>.*?</think>', '').Trim()
                if ([string]::IsNullOrWhiteSpace($displayText)) { $displayText = $txt }
                $parsed = [PSCustomObject]@{
                    analysis = $displayText
                    root_cause = "（模型未返回结构化结果）"
                    risk_level = "unknown"
                    commands = @()
                }
            }
        }
    }

    if (-not $parsed) {
        $suffix = if ($parseError) { " [$parseError]" } else { "" }
        throw "无法解析 LLM 响应：$($msg | Out-String)$suffix"
    }
    return $parsed
}

# Enumerate every top-level balanced JSON-like substring in the text.
# Robust against stray braces in prose (e.g. PowerShell scriptblocks like `{$_.x}`)
# and braces inside JSON string values. Returns an array of matched substrings
# in source order (may be empty). The caller is expected to try-parse each in
# turn, since a balanced substring is not necessarily valid JSON.
function Get-CMAllBalancedJsonObjects {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $results = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $start = -1
    $inString = $false
    $escape = $false

    for ($k = 0; $k -lt $Text.Length; $k++) {
        $ch = $Text[$k]

        if ($escape) {
            $escape = $false
            continue
        }
        if ($inString) {
            if ($ch -eq '\') { $escape = $true }
            elseif ($ch -eq '"') { $inString = $false }
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
        } elseif ($ch -eq '{') {
            if ($depth -eq 0) { $start = $k }
            $depth++
        } elseif ($ch -eq '}') {
            if ($depth -gt 0) {
                $depth--
                if ($depth -eq 0 -and $start -ge 0) {
                    $results.Add($Text.Substring($start, $k - $start + 1))
                    $start = -1
                }
            }
        }
    }
    return ,$results.ToArray()
}
#endregion

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
        '## 诊断快照',
        '```json',
        $snapJson,
        '```',
        '',
        '## 用户描述',
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
    $mode = "quick"
    if ($Script:CMConfig.PSObject.Properties.Name -contains "behavior" -and $Script:CMConfig.behavior.PSObject.Properties.Name -contains "snapshot_mode") {
        $mode = $Script:CMConfig.behavior.snapshot_mode
    }
    Write-CMInfo "[1/4] 收集诊断快照 (mode=$mode)..."
    try {
        $snap = Get-CMSnapshot -Mode $mode
    } catch {
        Write-CMError "快照收集失败：$($_.Exception.Message)"
        if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "ERR" -Source "DIAGNOSE" -Message $_.ToString() } catch {} }
        return
    }
    $cmdMax = 2000
    if ($Script:CMConfig.PSObject.Properties.Name -contains "behavior" -and $Script:CMConfig.behavior.PSObject.Properties.Name -contains "max_command_length") {
        $cmdMax = [int]$Script:CMConfig.behavior.max_command_length
    }

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
        $resp = Invoke-CMLLMChat -Config $Script:CMConfig -UserMessage $userMsg -FallbackText
    } catch {
        Write-CMError "LLM 调用失败：$($_.Exception.Message)"
        if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "ERR" -Source "LLM" -Message $_.ToString() } catch {} }
        return
    }
    Write-CMSuccess "分析：$($resp.analysis)"
    Write-CMInfo  "根因：$($resp.root_cause)"
    Write-CMWarn  "风险：$($resp.risk_level)"

    # 4) Execute
    $approved = @()
    if (-not $resp.commands -or $resp.commands.Count -eq 0) {
        Write-CMWarn "模型未返回可执行命令"
    } else {
        $i = 0
        foreach ($c in $resp.commands) {
            $i++
            $safetyCheck = Test-CMCommandAllowed -Command $c.command -SafetyConfig $safety
            if (-not $safetyCheck.allowed) {
                Write-CMWarn "  [$i] 被解析防护拒绝：$($safetyCheck.reason)  → 跳过"
                if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "WARN" -Source "PARSER" -Message "REJECTED [$i] $($c.command): $($safetyCheck.reason)" } catch {} }
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
                Result = $null
            }
            if ($cmdObj.command.Length -gt $cmdMax) {
                Write-CMWarn "命令超过 $cmdMax 字符，需要输入 FORCE 确认"
                $forceInput = (Read-Host "  输入 FORCE 以继续（其他跳过）").Trim()
                if ($forceInput -ne "FORCE") {
                    Write-CMWarn "  未输入 FORCE，已跳过"
                    if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "DIAGNOSE" -Message "SKIP-FORCE [$i] $($cmdObj.command)" } catch {} }
                    continue
                }
            }
            if ($effectiveRisk -eq "high") {
                Write-CMError "[!!] 高风险命令，需输入 YES 二次确认"
                $yesInput = (Read-Host "  输入 YES 继续（其他跳过）").Trim()
                if ($yesInput -ne "YES") {
                    Write-CMWarn "  未输入 YES，已跳过"
                    if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "DIAGNOSE" -Message "SKIP-HIGH-RISK [$i] $($cmdObj.command)" } catch {} }
                    continue
                }
            }
            $ok = Confirm-CMCommandRun -Cmd $cmdObj -Index $i -Total $resp.commands.Count
            if ($ok) {
                $dispatch = Get-CMCommandDispatch -Command $cmdObj.command
                if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "DIAGNOSE" -Message "ACCEPT [$i] $($cmdObj.command)" } catch {} }
                $result = Invoke-CMExecuteCommand -Command $cmdObj.command -Dispatch $dispatch
                $cmdObj.Result = $result
                $approved += $cmdObj
                Write-Host ("  exit={0}  ({1}s)" -f $result.exitCode, $result.durationSec)
                if ($result.exitCode -ne 0) {
                    Write-CMWarn "  上一条命令失败（exit=$($result.exitCode)）"
                }
            } else {
                if ($Script:CMLogger) { try { Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "DIAGNOSE" -Message "SKIP [$i] $($cmdObj.command)" } catch {} }
            }
        }
    }

    # 5) Report
    Write-CMInfo "[4/4] 写入报告..."
    $md = Format-CMDiagnoseReport -Context $ctx -Response $resp -Approved $approved -Mode $mode
    $reportDir = Join-Path $Script:CMRoot "reports"
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    $safeApp = ($app -replace "[^A-Za-z0-9_-]", "_")
    if ($safeApp.Length -gt 40) { $safeApp = $safeApp.Substring(0, 40) }
    if ([string]::IsNullOrEmpty($safeApp)) { $safeApp = "unnamed" }
    $file = Join-Path $reportDir ((Get-Date -Format "yyyy-MM-dd_HHmmss") + "_" + $safeApp + ".md")
    $md | Set-Content -Path $file -Encoding UTF8
    Write-CMSuccess "已保存：$file"
}

function Format-CMDiagnoseReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Approved,
        [string]$Mode = "quick"
    )
    # StrictMode-safe property accessor for malformed LLM responses
    function script:Get-CMRProp($obj, $name) {
        if ($obj -is [hashtable]) {
            if ($obj.ContainsKey($name)) { return $obj[$name] } else { return $null }
        } elseif ($obj) {
            $hit = $false
            foreach ($p in $obj.PSObject.Properties) {
                if ($p.Name -eq $name) { $hit = $true; break }
            }
            if ($hit) { return $obj.$name } else { return $null }
        } else { return $null }
    }
    $analysis   = Get-CMRProp $Response 'analysis'
    $rootCause  = Get-CMRProp $Response 'root_cause'
    $riskLevel  = Get-CMRProp $Response 'risk_level'
    $notes      = Get-CMRProp $Response 'notes'
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
        "- **结论**：$analysis",
        "- **根因**：$rootCause",
        "- **风险等级**：$riskLevel",
        ""
    )
    $snapMd = Format-CMSnapshotMarkdown -Snapshot $Context.snapshot
    if ($snapMd) { $lines += $snapMd.Split("`n") }
    $lines += ""
    $lines += "## 建议修复命令"
    $lines += "| # | 风险 | 描述 | 命令 | 预期 | 实际退出码 | 耗时(s) |"
    $lines += "|---|---|---|---|---|---|---|"
    foreach ($a in $Approved) {
        $exitCode = if ($a.PSObject.Properties.Name -contains 'Result' -and $a.Result) { $a.Result.exitCode } else { '-' }
        $duration = if ($a.PSObject.Properties.Name -contains 'Result' -and $a.Result) { $a.Result.durationSec } else { '-' }
        $lines += "| $($a.id) | $($a.risk) | $($a.description) | ``$($a.command)`` | $($a.expected_effect) | $exitCode | $duration |"
    }
    # Show LLM-suggested commands the user did not approve, so they are not
    # silently lost when the interactive prompt was skipped or declined.
    $approvedIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($a in $Approved) { [void]$approvedIds.Add([int]$a.id) }
    $pending = @()
    foreach ($c in (Get-CMRProp $Response 'commands')) {
        if (-not $approvedIds.Contains([int]$c.id)) { $pending += $c }
    }
    if ($pending.Count -gt 0) {
        $lines += ""
        $lines += "### 建议但未执行"
        $lines += "| # | 风险 | 描述 | 命令 | 预期 |"
        $lines += "|---|---|---|---|---|"
        foreach ($c in $pending) {
            $cRisk = Get-CMRProp $c 'risk'
            $cDesc = Get-CMRProp $c 'description'
            $cCmd  = Get-CMRProp $c 'command'
            $cEff  = Get-CMRProp $c 'expected_effect'
            $lines += "| $([int](Get-CMRProp $c 'id')) | $cRisk | $cDesc | ``$cCmd`` | $cEff |"
        }
    }
    if ($notes) {
        $lines += ""
        $lines += "## 备注"
        $lines += $notes
    }
    return ($lines -join "`n")
}
#endregion

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
    $handler = $null
    if ($Target.PSObject.Properties.Name -contains 'handler') { $handler = $Target.handler }
    $pattern = $null
    if ($Target.PSObject.Properties.Name -contains 'pattern') { $pattern = $Target.pattern }
    if ($handler -eq "RecycleBin") {
        if ($DryRun) { return @{ bytes = 0; ok = $true; note = "DRY RUN: 不清空" } }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $ok = $? -and $LASTEXITCODE -eq 0
        $note = if ($ok) { "已清空回收站" } else { "清空回收站失败（exit=$LASTEXITCODE）" }
        return @{ bytes = 0; ok = $ok; note = $note }
    }
    if ($handler -eq "WUAService") {
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
    if ($pattern) {
        $files = Get-ChildItem -Path $Target.path -Filter $pattern -Force -ErrorAction SilentlyContinue
        $sizeBefore = ($files | Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $sizeBefore) { $sizeBefore = 0 }
        if (-not $DryRun) { $files | Remove-Item -Force -ErrorAction SilentlyContinue }
        return @{ bytes = [long]$sizeBefore; ok = $true; note = "匹配 $pattern" }
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
            $dn = if ($props.PSObject.Properties['DisplayName']) { $props.DisplayName } else { $null }
            if ([string]::IsNullOrWhiteSpace($dn)) { return }
            $items += [PSCustomObject]@{
                name        = $dn
                version     = if ($props.PSObject.Properties['DisplayVersion']) { $props.DisplayVersion } else { $null }
                publisher   = if ($props.PSObject.Properties['Publisher']) { $props.Publisher } else { $null }
                installDate = if ($props.PSObject.Properties['InstallDate']) { $props.InstallDate } else { $null }
                uninstall   = if ($props.PSObject.Properties['UninstallString']) { $props.UninstallString } else { $null }
                quietUninstall = if ($props.PSObject.Properties['QuietUninstallString']) { $props.QuietUninstallString } else { $null }
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
        $silent = [string]::Format("msiexec.exe /x{{{0}}} /qn REBOOT=ReallySuppress", $guid)
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
    $idx = Read-CMMenuChoice -Prompt "选择要卸载的编号（0取消）" -ValidChoices (@(0) + @(1..$list.Count))
    if ($idx -eq 0) { return }
    $target = $list[$idx - 1]
    if ($Script:CMLogger) {
        Write-CMLog -Logger $Script:CMLogger -Level "USER" -Source "SOFTWARE" -Message "Selected: $($target.name) ($($target.version)) arch=$($target.architecture)"
    }
    $parsed = Format-CMUninstallString -UninstallString $target.uninstall
    Write-CMWarn "将执行：$($parsed.cmd)"
    if ($parsed.silent) {
        Write-CMWarn "可静默执行：$($parsed.silent)"
        if (Read-CMConfirm -Prompt "使用静默模式？") {
            $cmd = $parsed.silent
        } else { $cmd = $parsed.cmd }
    } else { $cmd = $parsed.cmd }
    if (Read-CMConfirm -Prompt "确认卸载？") {
        if ($Script:CMLogger) {
            Write-CMLog -Logger $Script:CMLogger -Level "CMD" -Source "SOFTWARE" -Message "uninstall: $($target.name) ($($target.version)) cmd=`"$cmd`""
        }
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -Wait -NoNewWindow
        Write-CMSuccess "已发送卸载命令。"
    }
}

function Invoke-CMRepairStoreApps {
    $choice = Read-CMMenuChoice -Prompt "选择修复操作 [1=重置 Store  2=重注册系统应用  3=清 Store 缓存 wsreset]" -ValidChoices @(1,2,3)
    switch ($choice) {
        1 {
            if ($Script:CMLogger) { Write-CMLog -Logger $Script:CMLogger -Level "CMD" -Source "STORE" -Message "Reset-AppxPackage Microsoft.WindowsStore" }
            $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Reset-AppxPackage
                Write-CMSuccess "已重置 Microsoft Store"
            } else {
                Write-CMWarn "未找到 Microsoft Store 包"
            }
        }
        2 {
            if ($Script:CMLogger) { Write-CMLog -Logger $Script:CMLogger -Level "CMD" -Source "STORE" -Message "Re-register all system apps" }
            if (-not (Read-CMConfirm -Prompt "将重新注册所有系统应用，可能耗时数分钟。继续？")) { return }
            Get-AppxPackage -AllUsers | ForEach-Object {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
            }
            Write-CMSuccess "已重注册所有系统应用"
        }
        3 {
            if ($Script:CMLogger) { Write-CMLog -Logger $Script:CMLogger -Level "CMD" -Source "STORE" -Message "wsreset.exe (clear Store cache)" }
            Start-Process wsreset.exe -Wait
            Write-CMSuccess "Store 缓存已清空"
        }
    }
}
#endregion

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
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $r["memory"] = [PSCustomObject]@{ total_gb = $totalGB; free_gb = $freeGB }
    }

    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $r["cpu"] = if ($cpu) { $cpu.Name } else { "Unknown" }

    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    $r["disk"] = @($disks | ForEach-Object {
        [PSCustomObject]@{
            drive      = $_.DeviceID
            free_gb    = [math]::Round($_.FreeSpace / 1GB, 1)
            size_gb    = [math]::Round($_.Size / 1GB, 1)
            percent_free = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
        }
    })

    $r["auto_services_stopped"] = @(Get-Service -ErrorAction SilentlyContinue |
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
            } elseif ($val[0] -is [string] -or $val[0] -is [hashtable] -or $val[0] -is [valuetype]) {
                foreach ($item in $val) {
                    $s = if ($null -eq $item) { "" } else { "$item" }
                    $lines += "- $s"
                }
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

#region Report
function Get-CMReportSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)
    $dir = Join-Path $RootPath "reports"
    if (-not (Test-Path $dir)) { return ,@() }
    return ,@(Get-ChildItem $dir -Filter "*.md" | Sort-Object LastWriteTime -Descending)
}

function Invoke-CMReportRetention {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath, [int]$Days = 30)
    $dir = Join-Path $RootPath "reports"
    if (-not (Test-Path $dir)) { return }
    $cutoff = (Get-Date).AddDays(-$Days)
    $stale = @(Get-ChildItem $dir -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff })
    if ($stale.Count -gt 0) {
        $stale | Remove-Item -Force -ErrorAction SilentlyContinue
        if ($Script:CMLogger) {
            try { Write-CMLog -Logger $Script:CMLogger -Level 'INFO' -Source 'RETAIN' -Message ("已删除 {0} 份过期报告 (>{1}天)" -f $stale.Count, $Days) } catch {}
        }
    }
}

function Invoke-CMLogRetention {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath, [int]$Days = 30)
    $dir = Join-Path $RootPath "logs"
    if (-not (Test-Path $dir)) { return }
    $cutoff = (Get-Date).AddDays(-$Days)
    $stale = @(Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff })
    if ($stale.Count -gt 0) {
        $stale | Remove-Item -Force -ErrorAction SilentlyContinue
        if ($Script:CMLogger) {
            try { Write-CMLog -Logger $Script:CMLogger -Level 'INFO' -Source 'RETAIN' -Message ("已删除 {0} 份过期日志 (>{1}天)" -f $stale.Count, $Days) } catch {}
        }
    }
}
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
    $list = Get-CMReportSummary -RootPath $Script:CMRoot
    if ($list.Count -eq 0) {
        Write-CMWarn '还没有报告'
        return
    }
    Write-Host ""
    Write-Host '--- 历史报告 ---' -ForegroundColor Cyan
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
    Write-Host ("===== {0} =====" -f $f.Name) -ForegroundColor Cyan
    Get-Content $f.FullName | Out-Host
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

