# claude-statusline

轻量、零依赖的 [Claude Code](https://claude.com/claude-code) statusline。单个 bash 脚本
（`statusline.sh`）+ macOS 系统自带的 `jq` / `git`，**无需构建、无需工具链、无需 `brew install`**。
建仓保存，重装机器后 `clone → ./install.sh` 即可恢复，不用再逐项配置。

```
OPUS · high › 24% ▰▰▱▱▱ › board git:(feat/board-test*) › 36% 5H·2h › 11% 7D·6d 7h
```

## 显示内容

段间以 ` › ` 分隔，任一字段数据缺失则该段自动隐藏：

| 段 | 内容 | 数据来源（Claude Code 经 stdin 传入的 JSON） |
|---|---|---|
| 模型 · 档位 | `OPUS · high` | `model.display_name`（回退 `model.id`）、`effort.level` |
| context | `24% ▰▰▱▱▱` | `context_window.used_percentage`（缺失时按 token 回退计算） |
| 目录 · git | `board git:(feat/board-test*)` | `cwd` 取 basename；`git` 命令取分支，脏工作区加 `*` |
| 5 小时窗口 | `36% 5H·2h` | `rate_limits.five_hour.used_percentage` / `.resets_at` |
| 7 天窗口 | `11% 7D·6d 7h` | `rate_limits.seven_day.used_percentage` / `.resets_at` |

**阈值配色**（作用于 context %、进度条、5H %、7D %）：

- `< 50%` → 青 `#5eead4`
- `50–80%` → 琥珀 `#fbbf24`
- `≥ 80%` → 珊瑚红 `#fb7185`

## 安装

```bash
git clone <此仓库地址> claude-statusline
cd claude-statusline
./install.sh
```

`install.sh` 会把 `~/.claude/settings.json` 的 `.statusLine` 指向本仓库的 `statusline.sh`
（合并写入，保留其它设置；先自动备份为 `settings.json.bak.<时间戳>`）。
重启 / 新开 Claude Code 会话即可看到。

> 建议把仓库放在固定位置（如 `~/repose/Github/claude-statusline`），因为 settings.json
> 里记录的是脚本的绝对路径。

## 依赖

- `/bin/bash`（3.2+，macOS 自带）
- `/usr/bin/jq`（macOS 15+ 系统自带；旧系统 `brew install jq`）
- `/usr/bin/git`（macOS 自带）

## 本地测试

脚本从 stdin 读取 Claude Code 的上下文 JSON，打印一行：

```bash
echo '{"model":{"display_name":"Opus"},"effort":{"level":"high"},
       "context_window":{"used_percentage":24,"context_window_size":200000},
       "cwd":"/path/to/repo",
       "rate_limits":{"five_hour":{"used_percentage":36,"resets_at":9999999999},
                      "seven_day":{"used_percentage":11,"resets_at":9999999999}}}' \
  | ./statusline.sh
```

## 卸载 / 恢复

编辑 `~/.claude/settings.json` 删除 `statusLine` 键，或还原 `install.sh` 生成的
`settings.json.bak.*` 备份。

## 设计文档

见 [`docs/specs/2026-07-02-claude-statusline-design.md`](docs/specs/2026-07-02-claude-statusline-design.md)。
