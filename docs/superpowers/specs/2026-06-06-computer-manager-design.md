# 电脑管理脚本 — 设计文档

- **日期**：2026-06-06
- **目标平台**：Windows 10/11（PowerShell 5.1 内置）
- **核心目标**：在无法安装任何应用的 Windows 机器上，单文件双击即用；通过 LLM 智能诊断"应用无法安装"问题，并辅助用户安全执行修复。

---

## 1. 范围

### 1.1 v1 必须做
1. **应用安装问题诊断与修复**（核心 + LLM 驱动）
2. **日常清理维护**（临时文件、缓存、回收站）
3. **软件管理**（已装软件列表、卸载、对 Microsoft Store / 桌面应用做"修复"）
4. **系统健康快照**（本地报告，不依赖 LLM）
5. **报告生成**（Markdown 格式）
6. **历史报告与日志回看**

### 1.2 v1 明确不做
- 自动更新、UI 国际化（仅中文）、系统还原点、命令黑名单（仅做基本解析防护）、Pester 单元测试套件（提供手工测试清单即可）、多用户并发访问。

---

## 2. 交付物

```
computer_manager/
├── computer_manager.ps1     # 主脚本（所有逻辑，单文件）
├── computer_manager.bat     # 启动器：powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0computer_manager.ps1" %*
├── config.json              # 用户配置（首次运行自动生成）
├── README.md                # 中文使用说明
├── logs/                    # 运行日志，按日期 logs/2026-06-06_143022.log
└── reports/                 # 诊断报告，reports/2026-06-06_143022_<app>.md
```

**便携性约束**：脚本中所有路径用 `$PSScriptRoot` 派生，不写注册表，不写用户目录之外的位置。

---

## 3. 配置文件 schema

`config.json` 首次运行自动生成模板，用户填入真实值。

```json
{
  "llm": {
    "base_url": "https://api.openai.com/v1",
    "api_key": "sk-xxx",
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
    "snapshot_mode": "quick",          // quick | full
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

校验启动时执行，缺字段补默认，错误字段打印警告并继续。

---

## 4. 菜单树

```
===== 电脑管理工具 =====
1. 诊断应用安装问题          [LLM]
2. 日常清理维护              [本地]
3. 软件管理                  [本地]
   3.1 列出已装软件
   3.2 卸载软件
   3.3 修复 Microsoft Store / 系统应用
4. 系统健康快照              [本地]
5. 查看历史报告
6. 设置                      [修改 config.json]
   6.1 重新配置 LLM
   6.2 修改默认行为
7. 关于 / 帮助
0. 退出
```

- 入口：默认进菜单；亦可命令行直跑 `computer_manager.ps1 diagnose --app "XXX" --error "YYY"`、`computer_manager.ps1 cleanup --dry-run` 等。
- 每一步操作**始终**回到主菜单（除非用户选 0 退出）。

---

## 5. 核心模块：诊断流程

### 5.1 数据流

```
[用户输入：app 名 + 报错 + 已尝试]
        ↓
[本地收集快照] ─── quick 30s / full 1-2min
        ↓
[拼装 prompt] ── system + snapshot + user
        ↓
[HTTP POST] ── /chat/completions (OpenAI 兼容)
        ↓
[解析响应] ── tool_calls 优先 → 文本 JSON 兜底
        ↓
[渲染] ── 分析文字 + 表格化命令列表
        ↓
[逐条 y/n 确认]
        ↓
[执行 + 捕获输出] ── powershell / cmd / 原生命令
        ↓
[生成 .md 报告] ── 含快照、对话、命令、结果
```

### 5.2 诊断快照（Diagnostic Snapshot）

收集内容**全部为只读**，绝不修改系统状态。字段示例（quick 默认）：

| 字段 | 来源 | 示例 |
|---|---|---|
| `os` | `Get-CimInstance Win32_OperatingSystem` | `Windows 11 Pro 23H2 (22631.3007)` |
| `admin` | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(...)` | `true / false` |
| `uac_level` | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorAdmin` | `5`（最高） |
| `pending_reboot` | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PendingFileRenameOperations` + `RebootRequired` 注册表项 | `false` |
| `disk_free_gb` | `Win32_LogicalDisk` 系统盘 | `42.3 GB` |
| `dotnet_versions` | `HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP` | `[4.8]` |
| `vc_runtimes` | 注册表 `HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\...` | `2005,2008,2010,2015-2022 x64` |
| `msi_service` | `Get-Service msiserver` | `Stopped` |
| `trustedinstaller` | `Get-Service TrustedInstaller` | `Stopped (manual)` |
| `defender_state` | `Get-MpComputerStatus`（若无则注册表回退） | `RealTimeProtectionEnabled=true` |
| `third_party_av` | `root\SecurityCenter2 AntiVirusProduct` | `[]` 或列表 |
| `applocker` | `Get-AppLockerPolicyInformation -Effective` | `NotConfigured` |
| `safeguard` | `HKLM\SOFTWARE\Policies\Microsoft\Windows\Safer` | `Absent` |
| `core_isolation` | `Get-MpComputerStatus` 中 `CoreIsolation` / `HypervisorEnforcedCodeIntegrity` 字段，回退到注册表 `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity\Enabled` | `Off` |
| `event_log_errors` | `Get-WinEvent -LogName Application,System -FilterXPath "*[System[Level=2]]" -MaxEvents 50` → 截断到 N 条 | `[ ... 5 条最近 ERROR ... ]` |
| `last_restore_point` | `Get-ComputerRestorePoint`（如启用） | `2026-05-20` |
| `temp_writable` | `[IO.Directory]::GetAccessControl($env:TEMP)` 简化版 | `true` |

`--full` 额外加：
- `Get-ChildItem Env:`、PATH 长度
- `sfc /verifyonly` 输出（只读检查，**不调用** `/scannow`）
- `DISM /Online /Get-CurrentEdition`、`/Get-ImageInfo` 摘要
- `bcdedit /enum` 摘要
- `powercfg /energy /output` 不调用，但读 `powercfg /query` 当前电源计划
- `Get-NetFirewallProfile | Select Name,Enabled`
- `Get-SmbSession`（如果有）
- 已挂载的 ISO / 虚拟光驱（`Get-Volume` + `Get-Disk`）

**截断策略**：
- 任何单条文本 > 500 字符截断并加 `... [truncated, full length=N]`
- 事件日志只保留 quick=N(默认 5) / full=20 条 ERROR，每条只保留前 3 行消息
- 总快照大小上限 32 KB（超出再压缩）

### 5.3 LLM 协议

**首选：tool/function calling**。`tools` 数组定义单个函数 `submit_diagnosis`，`tool_choice` 强制调用。`arguments` schema：

```json
{
  "type": "object",
  "properties": {
    "analysis": { "type": "string", "description": "1-3 句话的诊断分析" },
    "root_cause": { "type": "string", "description": "最可能的原因，单句" },
    "risk_level": { "type": "string", "enum": ["low", "medium", "high"] },
    "commands": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id":          { "type": "integer" },
          "description": { "type": "string" },
          "command":     { "type": "string", "description": "单行 PowerShell / cmd / 原生命令" },
          "expected_effect": { "type": "string" },
          "rollback_hint": { "type": "string" }
        },
        "required": ["id", "description", "command"]
      }
    },
    "notes": { "type": "string", "description": "人工补充说明" }
  },
  "required": ["analysis", "root_cause", "risk_level", "commands"]
}
```

**兜底**：若 `tool_calls` 字段为空/缺失/解析失败，尝试从 `choices[0].message.content` 中提取 ```json ... ``` 代码块；再失败则把原文展示给用户并写日志。

### 5.4 System Prompt（精炼版）

```
你是 Windows 系统管理员助手。你会收到一份"诊断快照"（系统只读信息）和用户描述的应用安装故障。

任务：分析故障，给出**可执行的、单行的 PowerShell / cmd / 原生命令**来修复。

约束（必须遵守）：
1. 仅返回 submit_diagnosis 函数的 JSON 参数，不要其他文字。
2. 命令必须是单行（不含换行符）。
3. 禁止使用：Invoke-Expression、iex、-EncodedCommand、FromBase64String、cmd.exe /c 的多语句链接。
4. 禁止破坏性操作：diskpart/format/clean、bcdedit 改引导、net user 添加账号、Set-MpPreference -ExclusionPath 大范围目录。
5. 如果建议涉及用户数据/账号/引导修复，把 risk_level 设为 "high"。
6. commands 数组最多 8 条；按"先无风险后高风险"排序。

低风险示例：Get-Service / Start-Service / Set-Service、sfc /scannow、DISM /Online /Cleanup-Image、msiexec /unregister+register、Get-AppxPackage -Repair、Get-AppLockerPolicyInformation（只读）、注册表 HKLM 读+受限写。
```

### 5.5 命令执行模型

1. 渲染表格：序号 / 风险 / 描述 / 命令 / 预期效果
2. 逐条提示 `[y/n/q=quit/a=all-remaining]`：
   - `y` 执行该条
   - `n` 跳过
   - `q` 退出本次诊断
   - `a` 后续全部执行（仍受解析防护约束）
3. 执行：**派发而非无脑 `cmd /c`**——
   - 命令首 token 匹配 PowerShell cmdlet 形式（`Get-*` / `Set-*` / `Start-*` / `Stop-*` / `Restart-*` / `New-*` / `Remove-*` / `Add-*` / `Clear-*` / `Update-*` / `Test-*` / `Resolve-*` / `Register-*` / `Unregister-*` / `Reset-*` / `Repair-*` / `Dism` / `sfc` / `msiexec` / `pnputil` / `bcdedit` / `powercfg` / `netsh` / `net` / `sc` / `reg` / `tasklist` / `taskkill` / `wmic` 等）→ 调用 `powershell -NoProfile -Command <command>`
   - 其他 → `cmd.exe /c <command>`
   - 实现细节：用一个 `Get-CommandDispatch` 辅助函数返回 `ps` / `cmd` 标签，运行时根据标签分流
4. 捕获：stdout / stderr / exit code / 耗时
5. 失败处理：若 exit ≠ 0，下一条命令前额外提示"上一条失败，是否继续？"

### 5.6 解析防护（不叫黑名单，是基本解析）

- **多行 / 多语句规则**：
  - 包含换行符 `\n` / `\r` → 拒绝
  - cmd 链（`a & b`、`a && b`、`a || b`、`a ; b`）→ 拒绝（拆分成多条）
  - PowerShell 单行 `;` 链（如 `Set-Service X -StartupType Manual; Start-Service X`）→ **允许**，视为一条命令
  - PowerShell 管道 `|` → 允许
- **拒绝关键字**（基于 `safety.allow_*` 配置，默认全 false）：`Invoke-Expression`、`iex `、`-EncodedCommand`、`-EC`、`FromBase64String`、`[System.Convert]::FromBase64String`
- **路径级警告**（非拒绝）：`Remove-Item -Recurse` / `Remove-Item -Force` / `rd /s` / `rmdir /s` 目标路径若命中以下系统目录前缀之一 → 强制 `high` 风险标签 + 二次确认：
  - `C:\Windows\`、`C:\Windows\System32\`、`C:\Program Files\`、`C:\Program Files (x86)\`、`C:\ProgramData\`、`%WINDIR%`、`%PROGRAMDATA%`、`%SYSTEMROOT%`
- **长度上限**：`max_command_length`（默认 2000）超出需二次输入 `FORCE` 才执行。
- **dry-run 模式**：`--dry-run` 仅打印命令不执行。

### 5.7 报告

`reports/2026-06-06_143022_<sanitized-app>.md` 内容：

```markdown
# 应用安装诊断报告
- 时间：2026-06-06 14:30:22
- 主机：<computername> / <user> / <os build>
- 应用：<user-provided name>
- 错误描述：<user-provided>

## 1. 诊断快照（摘要）
<贴上 quick 快照表格>

## 2. 模型分析
- **结论**：<analysis>
- **根因**：<root_cause>
- **风险等级**：<risk_level>

## 3. 建议修复命令
| # | 风险 | 描述 | 命令 | 预期 | 实际结果 | 退出码 | 用户选择 |
|---|---|---|---|---|---|---|---|

## 4. 备注
<notes>
```

---

## 6. 清理维护模块（本地）

**白名单清理**（默认全开，每项可单独 `--skip`）：

| 项 | 路径 / 操作 | 默认 |
|---|---|---|
| 用户临时 | `%LOCALAPPDATA%\Temp`、`%TEMP%`、`C:\Windows\Temp\*`（仅当前用户可写部分） | 开 |
| Windows Update 缓存 | `C:\Windows\SoftwareDistribution\Download`（需先停 wuauserv） | 关 |
| 缩略图缓存 | `%LOCALAPPDATA%\Microsoft\Windows\Explorer` 内 `thumbcache_*.db` | 开 |
| 回收站 | `Clear-RecycleBin -Force` | 关 |
| Edge / Chrome 缓存 | `%LOCALAPPDATA%\...\User Data\Default\Cache` | 关（可选） |
| 旧日志 | `logs/` 目录中超过 `log_retention_days` 的文件 | 开 |
| 旧报告 | `reports/` 目录中超过 `report_retention_days` 的文件 | 开 |

每项执行前后**显示**大小变化；总回收大小打印在结尾。

---

## 7. 软件管理模块

- **列出已装软件**：合并两路来源
  - `Get-Package`（PowerShellGet 视角）
  - 注册表 `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`、`HKLM\SOFTWARE\WOW6432Node\...\Uninstall`、`HKCU\...\Uninstall`
  - 输出 `名称 / 发行商 / 版本 / 安装日期 / UninstallString / 静默卸载参数 / 架构`
- **卸载**：调用 `UninstallString`；如有 `/quiet`/`/S`/`/silent` 模式则提供静默开关；MsiExec 形式用 `msiexec /x {GUID} /qn`
- **修复 Microsoft Store / 系统应用**：
  - `Get-AppxPackage -AllUsers Microsoft.WindowsStore | Reset-AppxPackage`
  - `wsreset.exe`（清空 Store 缓存）
  - `Get-AppxPackage -AllUsers | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" }`（重注册所有系统应用）
- **常见软件专属修复**（硬编码小字典）：`office` → `OfficeC2RClient ... /repair`、`edge` → `--repair`、`onedrive` → `OneDriveSetup.exe /reset`、`vcredist` → 提示下载最新合集（不给 URL，让用户去 msdn 找，避免脚本带过期链接）

---

## 8. 系统健康快照（不依赖 LLM）

输出至控制台 + 可选 `.md`：

- OS / 启动时间（`Get-CimInstance Win32_OperatingSystem LastBootUpTime`）
- CPU/内存/磁盘
- 网络：`Get-NetAdapter` 状态、`Test-NetConnection google.com -Port 443`（仅测连通性）
- 服务异常：`Get-Service | Where {$_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic'}` 关键服务列表
- 关键事件：最近 N 条 ERROR
- 启动项：`Get-CimInstance Win32_StartupCommand` 摘要
- 计划任务中失败：`Get-ScheduledTask | Get-ScheduledTaskInfo | Where {$_.LastTaskResult -ne 0}`

---

## 9. 错误处理矩阵

| 场景 | 行为 |
|---|---|
| `config.json` 不存在 | 生成模板，提示用户填 api_key，退出 |
| `config.json` JSON 错误 | 备份为 `config.json.bak.<timestamp>`，生成新模板 |
| 缺 api_key | 提示，仅"诊断"模块不可用，其他模块正常 |
| 网络超时 / DNS 失败 | 打印错误 + 建议检查网络；不重试 |
| HTTP 401/403 | 提示检查 api_key；建议菜单"设置 → 重新配置 LLM" |
| HTTP 429 | 提示稍后重试，附 `Retry-After`（如有） |
| LLM 返回非 JSON | 显示原文，提示用户复制日志去反馈，可选"重试" |
| 命令执行超时 | 默认 60s 可配；超时后 kill，给出"卡住"提示 |
| 命令 exit ≠ 0 | 显示 stderr 摘要，不终止流程；用户可继续或退出 |
| 磁盘空间 < 200 MB | 清理模块自动转 dry-run，需用户显式 `--force` |
| 系统盘无写权限 | 启动时检测，提示"请以管理员身份运行" |

---

## 10. 日志

- 路径：`logs/<date>_<time>.log`
- 格式：`<ISO 时间> [<LEVEL>] <来源> <消息>`（LEVEL = INFO/WARN/ERR/USER/CMD/OUT）
- 大小上限：单文件 5 MB（轮转）
- 清理：见 §6 白名单

每条**用户确认选择** (`y`/`n`/`q`/`a`) **必须**入日志，便于事后追溯。

---

## 11. 测试策略

### 11.1 手工测试清单（随 README 提供）
1. 首次运行 → 自动生成 config.json
2. 菜单 1（诊断）跑通，命令被 y/n 确认
3. 菜单 2（清理）dry-run + 实际跑
4. 菜单 3.1 列出已装软件（含 Microsoft Store 应用）
5. 菜单 3.3 修复 Store（在一台 Store 异常的机器上验证）
6. 菜单 4 生成健康快照 .md
7. 菜单 5 回看历史报告
8. 断网情况下，菜单 1 应给出明确错误，菜单 2/3/4 不受影响
9. 命令解析防护：构造一条多行命令的 LLM 模拟响应，应被拒绝
10. 编码命令：`-EncodedCommand` 应被拒绝

### 11.2 可选 Pester（若用户机器有 Pester）
- `Get-DiagnosticSnapshot` 输出结构测试
- 命令解析器（拒绝多行/iex/encoded）单元测试
- LLM 响应解析器（tool_calls + 文本 JSON 兜底）单元测试

v1 不强制 Pester；Pester 测试代码可作为后续增强。

---

## 12. 安全与隐私

- **不外发**：除 LLM 调用外，所有数据本地处理；LLM 调用只发送"诊断快照 + 用户描述"，不发送文件内容、密码、注册表敏感键（脚本主动过滤：`HKCU\...\Credentials`、`HKLM\SAM`、`HKLM\SECURITY` 等永不发送）
- **API key**：config.json 明文存储，**不**写入日志（`api_key` 字段在日志中替换为 `***`）
- **LLM 响应中含 key/token 的可能**：在生成报告前对报告做"敏感串脱敏"（`api[_-]?key`、`token`、`bearer\s+[A-Za-z0-9._-]+` 等正则替换为 `***`），双保险
- **破坏性操作**：依赖 user-confirm + LLM 约束 + 解析防护三层；不做"自动回滚"
- **网络白名单**：默认不限制 base_url；提供 `safety.allowed_base_urls` 数组作为可选限制（默认空 = 不限制）

---

## 13. 性能与可维护性

- 单文件 ≤ 2000 行（v1 目标），超则按 region 折叠
- 函数命名 PascalCase 动词-名词（`Get-DiagnosticSnapshot`、`Invoke-LLMDiagnose`）
- 字符串使用 here-string，避免硬编码大量转义
- 颜色用 `Write-Host -ForegroundColor`（v1 简单方案）
- 无第三方依赖；不调用 `Install-Module`

---

## 14. 后续路线（非 v1 范围）

- v1.1：Pester 测试 + CI 校验脚本语法
- v1.2：交互式追问（LLM 反问 → 多轮对话）
- v1.3：本地轻量规则库（断网时根据 `app 名` 关键词给候选命令）
- v2.0：可选 GUI（WinForms），仍单文件、无依赖

---

## 附录 A：菜单 1 一次跑通的端到端示例

```
> computer_manager.bat
===== 电脑管理工具 v1.0 =====
请选择: 1

[1/3] 收集诊断快照 (quick 模式) ... 完成 (8 项)
[2/3] 请描述问题：
       目标应用：Office 2021
       报错信息：0x80070005 拒绝访问
       已尝试操作：以管理员运行、手动开 msiserver
[3/3] 调用 LLM 分析 ...

<等待 5-12 秒>

=== 模型分析 ===
结论：msiserver 处于 Stopped 且被某条组策略禁用；UAC ConsentPromptBehaviorAdmin=5。
根因：组策略禁用 Windows Installer 服务。
风险等级：low

=== 建议命令 ===
# 风险  描述                       命令                                                预期
1 low  启用并启动 msiserver       Set-Service msiserver -StartupType Manual; Start-Service msiserver  Running
2 low  重新注册 MSI                msiexec /unregister && msiexec /regserver           重新初始化

执行 [1/2]? (y/n/q/a): y
[CMD] Set-Service msiserver -StartupType Manual; Start-Service msiserver
[OUT] exit=0

执行 [2/2]? (y/n/q/a): y
[CMD] msiexec /unregister && msiexec /regserver
[OUT] exit=0

报告已保存: reports/2026-06-06_143022_office2021.md
```

---

文档结束。
