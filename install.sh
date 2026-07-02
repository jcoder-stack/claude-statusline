#!/bin/bash
# 把本仓库的 statusline.sh 装成 Claude Code 的 statusLine。
# 安全合并 settings.json，保留其它所有设置；先自动备份。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/statusline.sh"

command -v jq  >/dev/null 2>&1 || { echo "✗ 未找到 jq（macOS 15+ 自带；或 brew install jq）"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "✗ 未找到 git"; exit 1; }
[ -f "$SCRIPT" ] || { echo "✗ 未找到 $SCRIPT"; exit 1; }

chmod +x "$SCRIPT"

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG/settings.json"
mkdir -p "$CFG"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  jq --arg cmd "$SCRIPT" '.statusLine = {type:"command", command:$cmd}' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
else
  jq -n --arg cmd "$SCRIPT" '{statusLine:{type:"command", command:$cmd}}' > "$SETTINGS"
fi

echo "✓ 已安装 statusline"
echo "  脚本    : $SCRIPT"
echo "  settings: $SETTINGS  (.statusLine 已更新，其它设置保留)"
echo
echo "预览（示例数据）："
printf '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":24,"context_window_size":200000},"cwd":"%s","rate_limits":{"five_hour":{"used_percentage":36,"resets_at":%s},"seven_day":{"used_percentage":11,"resets_at":%s}}}' \
  "$DIR" "$(( $(date +%s) + 7200 ))" "$(( $(date +%s) + 543600 ))" | bash "$SCRIPT"
echo
echo "重启 / 新开 Claude Code 会话即可看到。"
