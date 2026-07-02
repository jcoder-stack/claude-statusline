# claude-statusline 设计文档

- 日期：2026-07-02
- 目标：自建一个**轻量、独立**的 Claude Code statusline，精确还原参考预览
  （`preview.html`），并建仓保存，做到「重装即用、零重配」。不依赖 claude-hud。

## 1. 背景与目标

用户当前 statusline 由 `claude-hud` 插件渲染，参考预览 `preview.html` 即其风格效果。
用户希望改为**自己完全掌控的轻量实现**，放进独立 git 仓库，重装机器后
`clone → ./install.sh` 即可恢复，无需再逐项配置。

成功标准：

1. 在 Claude Code（v2.1.x）中渲染出与 `preview.html` 一致的单行状态栏。
2. 全部数据来自 Claude Code 通过 stdin 传入的 JSON（+ 本地 `git` 命令），
   不读取任何凭证、不发起网络/API 请求。
3. 重装流程为 `git clone` 后运行一条命令；不改动用户 `settings.json` 中其它设置。

## 2. 运行时与语言

**Go**（编译型，标准库-only）。

- 理由：statusline 每次渲染都被调用，Go 编译为单个静态二进制，启动 ~2ms、运行时零
  依赖，适合高频常驻调用；标准库自带 `encoding/json` / `os/exec` / `time`，无第三方依赖。
- 「重装即用」：仓库提交**预编译 darwin-arm64 二进制** `bin/statusline`。重装后即使
  没有 Go 工具链也能直接用；有 Go 时 `install.sh` 可选择重新 `go build`。
- 前提：**首次构建预编译二进制需要在本机装一次 Go**（`brew install go`）。装一次即可，
  产物二进制提交进仓库后，后续重装不再需要 Go。

## 3. 数据来源（全部来自 stdin JSON，git 段除外）

Claude Code 通过 stdin 传入 JSON。已核对的 stdin 结构（仅列本项目用到的字段）：

```jsonc
{
  "cwd": "/path/to/board",
  "model":   { "id": "claude-opus-...", "display_name": "Opus" },
  "effort":  { "level": "high" },          // 也可能是字符串 "high"
  "context_window": {
    "context_window_size": 200000,
    "used_percentage": 24,                  // 首选，直接用
    "current_usage": { "input_tokens": 0, "cache_creation_input_tokens": 0,
                       "cache_read_input_tokens": 0 }
  },
  "rate_limits": {
    "five_hour": { "used_percentage": 36, "resets_at": 1751... },  // resets_at 为 unix 秒
    "seven_day": { "used_percentage": 11, "resets_at": 1752... }
  }
}
```

| 字段 | 来源 | 说明 |
|---|---|---|
| 模型名 `OPUS` | `model.display_name`，回退 `model.id` | 去掉 `Claude ` 前缀 / `(1M context)` 后缀；大写展示 |
| 推理档 `high` | `effort.level`（或 `effort` 为字符串时直接取） | 缺失则省略该段 |
| context `24%` | `context_window.used_percentage`（首选） | 若为 null/0，回退 `(input+cache_creation+cache_read)/context_window_size*100`（不含 output_tokens） |
| 目录 `board` | `cwd` 取 basename | 非 `workspace.current_dir` |
| git 分支 / `*` | `git rev-parse --abbrev-ref HEAD` + `git status --porcelain`（cwd=`cwd`） | 非 git 目录则整段省略；porcelain 非空即脏，加 `*` |
| `5H` 用量/重置 | `rate_limits.five_hour.used_percentage` / `.resets_at` | resets_at 为 unix 秒 |
| `7D` 用量/重置 | `rate_limits.seven_day.used_percentage` / `.resets_at` | 同上 |

`effort` 字段为多态（字符串 **或** `{level}` 对象）：用 `json.RawMessage` 兼容解析。

## 4. 显示还原（真彩色 ANSI）

单行，段间用 ` › ` 分隔符（`#3a3c46`）。真彩色转义：`\x1b[38;2;R;G;Bm ... \x1b[0m`。

段序：

1. `OPUS`(`#c4b5fd`) ` · `(`#3a3c46`) `high`(`#5a5c66`)
2. `24%`(阈值色) ` ` `▰▰▱▱▱`（5 段条：`filled=round(pct/100*5)`，填充随阈值色，空段 `▱` `#1e2128`）
3. `board`(`#e8e8ea`) ` ` `git:(`(`#fbbf24`)`feat/board-test`(`#fde68a`)`*`(脏,`#fbbf24`)`)`(`#fbbf24`)
4. `36%`(阈值色) ` 5H·2h`(`#4a4c56`)
5. `11%`(阈值色) ` 7D·6d 7h`(`#4a4c56`)

**阈值配色**（作用于 context %、context 条、5H %、7D %）：

- `pct < 50` → 青 `#5eead4`
- `50 ≤ pct < 80` → 琥珀 `#fbbf24`
- `pct ≥ 80` → 珊瑚红 `#fb7185`（边界：79→琥珀，80→珊瑚红）

**字符**：分隔符 `›`(U+203A)；填充 `▰`(U+25B0) / 空 `▱`(U+25B1)；标签分隔 `·`(U+00B7)。

**重置时间格式**（由 `resets_at - now` 计算，统一规则）：

- `< 1h` → `48m`
- `< 24h` → `2h` 或 `2h30m`（有余分钟才带 m）
- `≥ 24h` → `6d 7h` 或 `6d`（有余小时才带 h）

**缺失优雅降级**：任一 rate_limit 段数据缺失（null）→ 隐藏该段；非 git 目录 → 隐藏 git 段；
模型/context 缺失 → 隐藏对应段。段之间的 ` › ` 分隔符按实际存在的段动态拼接。

> 说明：`preview.html` 中的条形段数为手绘示意（如 24% 画了 2 段），实际按公式计算；
> 观感与行为一致。

## 5. 仓库结构

位置：`~/repose/Github/claude-statusline/`

```
claude-statusline/
├── main.go            # 脚本本体（stdlib-only）
├── go.mod
├── bin/statusline     # 预编译 darwin-arm64，提交进仓库
├── build.sh           # go build -o bin/statusline
├── install.sh         # 有 go 则 build，否则用预编译件；合并 settings.json 的 statusLine
├── README.md          # 说明 + 重装步骤
├── preview.html       # 参考预览留档
└── docs/specs/        # 本设计文档
```

**`install.sh` 行为**：

1. 若 `go` 可用 → `./build.sh` 生成 `bin/statusline`；否则校验已提交的 `bin/statusline` 存在。
2. 用 python 安全合并 `~/.claude/settings.json`：设置
   `.statusLine = { "type": "command", "command": "<repo>/bin/statusline" }`，
   保留文件中其它所有键。无 settings.json 则新建。
3. 打印完成提示。

**重装流程**：`git clone <repo>` → `cd claude-statusline` → `./install.sh` → 完成。

## 6. 测试策略

- 提供若干条固定 stdin JSON 样例（对应 preview.html 的 5 种状态：全安全 / context 逼近 /
  5H 偏高 / 7D 逼近 / 全红），`echo '<json>' | ./bin/statusline` 目测输出。
- 边界：无 rate_limits、非 git 目录、effort 为字符串形态、context used_percentage 为 0/null
  回退计算、resets_at 已过期（负 duration → 显示 `0m`）。
- 颜色阈值：49/50/79/80/99 各取一值验证青/琥珀/珊瑚红切换。

## 7. 非目标（YAGNI）

- 不做配置系统 / 主题切换 / i18n（claude-hud 已有，这里追求轻量固定还原）。
- 不做 tokens 明细、cost、ahead/behind、todos、外部用量快照互操作。
- 不支持 Windows / 非 arm64（如需，`build.sh` 可扩展交叉编译，暂不做）。
