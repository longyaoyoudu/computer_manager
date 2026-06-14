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

    if ($Command -match '[\r\n]') {
        $result.allowed = $false; $result.reason = '命令包含换行符'; return $result
    }

    if ($Command -match '\s&\s|\s&&\s|\s\|\|\s') {
        $result.allowed = $false; $result.reason = '命令包含 cmd 链式操作符'; return $result
    }

    if (-not $SafetyConfig['allow_encoded_commands']) {
        if ($Command -match '(?i)-EncodedCommand|-EC\b|FromBase64String') {
            $result.allowed = $false; $result.reason = '包含被禁用的编码命令'; return $result
        }
    }
    if (-not $SafetyConfig['allow_iex']) {
        if ($Command -match '(?i)\bInvoke-Expression\b|\biex\s') {
            $result.allowed = $false; $result.reason = '包含被禁用的 Invoke-Expression'; return $result
        }
    }

    $sysDirs = Get-CMSystemDirs
    $isDangerousRemoval = $Command -match '(?i)\b(Remove-Item|rd|rmdir)\b'
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
#endregion

#region LLM
#endregion

#region Diagnose
function Invoke-CMDiagnose {
    Write-CMWarn "诊断模块开发中（任务 14-19）"
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
