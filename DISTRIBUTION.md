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
