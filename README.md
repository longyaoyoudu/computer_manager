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
