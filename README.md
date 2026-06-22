# 电脑管理工具 v1.0

Windows 上无需安装任何应用、双击即用的电脑管理脚本。通过 LLM 智能诊断"应用无法安装"问题，并辅助用户安全执行修复。

## 核心特性

- **LLM 驱动的应用安装诊断**（核心）：收集系统快照 → LLM 分析 → 逐条 y/n 确认执行
- **日常清理维护**：临时文件、缩略图缓存、回收站、Windows Update 缓存
- **软件管理**：列出/卸载已装软件、修复 Microsoft Store 和系统应用
- **系统健康快照**：OS/内存/磁盘/服务/事件/启动项
- **报告生成**：所有操作可生成 Markdown 报告（`reports/`）
- **历史回看**：浏览历史报告与日志

## 快速开始

### 1. 复制 4 个文件到目标机器任意目录

| 文件 | 说明 |
|---|---|
| `computer_manager.ps1` | 主脚本 |
| `computer_manager.bat` | 双击启动器 |
| `config.example.json` | 配置模板 |
| `README.md` | 本文件 |

### 2. 复制 `config.example.json` → `config.json`，填入 LLM API

```json
{
  "llm": {
    "base_url": "https://api.openai.com/v1",
    "api_key": "sk-xxx",
    "model": "gpt-4o-mini",
    "max_response_tokens": 4000
  }
}
```

### 3. 双击 `computer_manager.bat`

首次运行若提示"无法加载脚本"，在 PowerShell 中执行一次：

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## 诊断流程

```
启动 → 选择"诊断应用安装问题"
     → 输入应用名 + 报错码 + 已尝试的操作
     → 自动收集 quick 快照（OS / 磁盘 / 服务 / 事件 / UAC ...）
     → 调用 LLM 分析，返回 root_cause + 风险等级 + 命令列表
     → 逐条命令 y/n 确认（高风险需 YES；长命令需 FORCE）
     → 写入 Markdown 报告到 reports/ 目录
```

报告章节：

- **模型分析**：结论 / 根因 / 风险等级
- **诊断快照**：quick 或 full 模式下的字段表
- **建议修复命令**：实际执行过的命令（含退出码 / 耗时）
- **建议但未执行**：LLM 推荐但未在交互中确认的命令
- **备注**：模型的额外说明

## LLM 配置详解

`llm` 块支持以下字段：

| 字段 | 必填 | 说明 |
|---|---|---|
| `base_url` | 是 | OpenAI 兼容 API 地址 |
| `api_key` | 是 | API 密钥（写入日志前自动脱敏）|
| `model` | 是 | 模型名 |
| `temperature` | 否 | 采样温度，默认 0.2 |
| `timeout_seconds` | 否 | HTTP 超时，默认 60 |
| `max_response_tokens` | 否 | 模型最大输出 token，默认 2000；复杂诊断建议 4000+ |
| `thinking` | 否 | MiniMax-M3 等推理模型专用，`{"type":"disabled"}` 关闭思考块 |

### MiniMax-M3 配置示例

```json
{
  "llm": {
    "base_url": "https://api.minimaxi.com/v1",
    "api_key": "your-key",
    "model": "MiniMax-M3",
    "thinking": { "type": "disabled" }
  }
}
```

### 允许的 base_url 白名单

为防止 base_url 被篡改指向恶意服务器，`safety.allowed_base_urls` 控制允许的域名列表：

```json
"safety": {
  "allowed_base_urls": ["api.openai.com", "api.minimaxi.com"]
}
```

留空数组表示允许任意（不推荐生产环境）。

## 主菜单

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

## 安全模型

- LLM 生成的命令 **逐条人工 y/n 确认** 后才执行
- 拒绝 `Invoke-Expression`、`-EncodedCommand`、多语句 cmd 链（`&` / `&&` / `||` / `;`）
- 命中系统目录的 `Remove-Item` / `del` 自动标记为高风险
- 长命令（超过 `behavior.max_command_length`）需额外输入 `FORCE`
- API key 写入日志前自动脱敏为 `sk-xx...xx` 形式
- base_url 受 `safety.allowed_base_urls` 限制

## 故障排查

### 诊断报告没有根因 / 命令列表为空

可能原因：模型响应里只有思考块（`<think>...</think>`）而没有调用 `submit_diagnosis` 工具函数。

解决：

1. 确认 `config.json` 中已设置 `"thinking": { "type": "disabled" }`（仅对支持该参数的模型，如 MiniMax-M3 生效）
2. 若仍出现，重试一次即可（脚本内置自动重试 + 提示）
3. 如根因诊断长，调大 `max_response_tokens` 至 `4000-8000`

### 报告里 `## 诊断快照` 重复出现

这是早期版本的 bug，已在最新版修复。重新拉取代码即可。

### 报告里 `备注` 段被截断

通常是 `max_response_tokens` 设得过小，模型输出被截断。调大到 4000 以上。

## 兼容性

- Windows 10 / 11（PowerShell 5.1 内置，**不支持 PowerShell 7+**）
- 部分清理与修复操作需要管理员权限（脚本会自动检测并提示）

## 目录结构

```
computer_manager/
├── computer_manager.ps1     # 主脚本（所有逻辑）
├── computer_manager.bat     # 双击启动器
├── config.example.json      # 配置模板
├── config.json              # 你的配置（不会提交）
├── README.md                # 本文件
├── docs/                    # 设计与实施文档
├── tests/                   # Pester 单元测试
├── reports/                 # 诊断报告输出
├── forward/                 # 你提供的诊断样本（用于回归对比）
└── logs/                    # 运行日志
```

## 开发与测试

```powershell
# 跑全部 Pester 测试
Invoke-Pester ./tests/

# 单跑某个模块
Invoke-Pester ./tests/LLM.Tests.ps1

# 冒烟测试（端到端 8 步）
./tests/smoke.ps1
```

## 文档

- [设计文档](docs/superpowers/specs/2026-06-06-computer-manager-design.md)
- [实施计划](docs/superpowers/plans/2026-06-06-computer-manager-implementation.md)

## 更新日志

- **v1.0.x**：LLM 响应解析加固（平衡花括号扫描器 + thinking 关闭 + 重试 + FallbackText）
- **v1.0.x**：诊断报告渲染加固（去重标题 + 保留未执行的 LLM 建议）
- **v1.0**：首次发布