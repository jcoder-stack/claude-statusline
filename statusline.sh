#!/bin/bash
# claude-statusline — 轻量单文件 Claude Code statusline
# 依赖：/bin/bash(3.2+) · /usr/bin/jq · /usr/bin/git （均为 macOS 系统自带）
# 用法：Claude Code 通过 stdin 传入上下文 JSON，本脚本打印一行状态栏。
#   echo '<json>' | ./statusline.sh   # 本地测试
#
# 显示（真彩色 ANSI，段间 ' › ' 分隔）：
#   OPUS · high › 24% ▰▰▱▱▱ › board git:(feat/board-test*) › 36% 5H·2h › 11% 7D·6d 7h
# 阈值配色：<50% 青 / 50–80% 琥珀 / ≥80% 珊瑚红

set -o pipefail

# 以字节模式运行：避免非法/异常 locale（如 LC_CTYPE=UTF-8）破坏多字节拼接。
# 脚本只做字节级拼接并输出写死的 UTF-8，C locale 最稳且跨环境一致。
export LC_ALL=C

esc=$'\033'
reset="${esc}[0m"

# col R G B -> 输出真彩色前景转义
col() { printf '%s[38;2;%s;%s;%sm' "$esc" "$1" "$2" "$3"; }

# 固定配色（RGB）
C_SEP="58 60 70"       # #3a3c46 分隔符 / 中点
C_MODEL="196 181 253"  # #c4b5fd 模型名
C_EFFORT="90 92 102"   # #5a5c66 推理档
C_DIR="232 232 234"    # #e8e8ea 目录
C_GIT="251 191 36"     # #fbbf24 git:( )
C_BRANCH="253 230 138" # #fde68a 分支名
C_WLABEL="74 76 86"    # #4a4c56 窗口标签
C_EMPTY="30 33 40"     # #1e2128 空条段
# 阈值色
C_CYAN="94 234 212"    # #5eead4
C_AMBER="251 191 36"   # #fbbf24
C_CORAL="251 113 133"  # #fb7185

# threshold PCT -> 输出对应阈值色的 ANSI set
threshold() {
  local p=$1
  if   (( p < 50 )); then col $C_CYAN
  elif (( p < 80 )); then col $C_AMBER
  else                    col $C_CORAL
  fi
}

# make_bar PCT -> 5 段进度条（填充随阈值色，空段固定色）
make_bar() {
  local p=$1 seg i out
  seg=$(( (p * 5 + 50) / 100 ))       # round(pct/100*5)
  (( seg < 0 )) && seg=0
  (( seg > 5 )) && seg=5
  out="$(threshold "$p")"
  for (( i=0; i<seg; i++ )); do out="$out▰"; done
  out="$out${reset}$(col $C_EMPTY)"
  for (( i=seg; i<5; i++ )); do out="$out▱"; done
  printf '%s%s' "$out" "$reset"
}

# fmt_reset DIFF_SECONDS -> 剩余时间：<1h→48m / <24h→2h|2h30m / ≥24h→6d 7h|6d
fmt_reset() {
  local diff=$1 d h m
  (( diff < 0 )) && diff=0
  if (( diff < 3600 )); then
    printf '%dm' "$(( diff / 60 ))"
  elif (( diff < 86400 )); then
    h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
    if (( m > 0 )); then printf '%dh%dm' "$h" "$m"; else printf '%dh' "$h"; fi
  else
    d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 ))
    if (( h > 0 )); then printf '%dd %dh' "$d" "$h"; else printf '%dd' "$d"; fi
  fi
}

# ---- 读取并解析 stdin JSON ----
input=$(cat)
[ -z "$input" ] && exit 0

JQ='
def num(x): if x == null then "" else (x|round|tostring) end;
def ctxpct:
  (.context_window.used_percentage) as $u
  | if ($u != null and $u > 0) then ($u|round|tostring)
    else ((.context_window.context_window_size // 0) as $s
          | ((.context_window.current_usage.input_tokens // 0)
             + (.context_window.current_usage.cache_creation_input_tokens // 0)
             + (.context_window.current_usage.cache_read_input_tokens // 0)) as $t
          | if $s > 0 then (($t / $s * 100) | round | tostring) else "" end)
    end;
[ (.model.display_name // .model.id // ""),
  (.effort | if . == null then "" elif type=="string" then . else (.level // "") end | tostring),
  (ctxpct),
  (.cwd // ""),
  num(.rate_limits.five_hour.used_percentage),
  num(.rate_limits.five_hour.resets_at),
  num(.rate_limits.seven_day.used_percentage),
  num(.rate_limits.seven_day.resets_at)
] | join("")
'

fields=$(printf '%s' "$input" | jq -j "$JQ" 2>/dev/null) || exit 0
[ -z "$fields" ] && exit 0

IFS=$'\037' read -r model effort ctx_pct cwd five_pct five_reset seven_pct seven_reset <<< "$fields"

now=$(date +%s)
segments=()

# 1) 模型 · 推理档
if [ -n "$model" ]; then
  MODEL=$(printf '%s' "$model" | sed -E 's/^Claude //; s/ *\([^)]*\)$//' | tr '[:lower:]' '[:upper:]')
  s="$(col $C_MODEL)${MODEL}${reset}"
  if [ -n "$effort" ]; then
    s="${s}$(col $C_SEP) · ${reset}$(col $C_EFFORT)${effort}${reset}"
  fi
  segments+=("$s")
fi

# 2) context 百分比 + 进度条
if [ -n "$ctx_pct" ]; then
  s="$(threshold "$ctx_pct")${ctx_pct}%${reset} $(make_bar "$ctx_pct")"
  segments+=("$s")
fi

# 3) 目录 + git 分支/脏标记
if [ -n "$cwd" ]; then
  dir="${cwd%/}"; dir="${dir##*/}"
  s="$(col $C_DIR)${dir}${reset}"
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    star=""
    [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ] && star="*"
    s="${s} $(col $C_GIT)git:($(col $C_BRANCH)${branch}${star}$(col $C_GIT))${reset}"
  fi
  segments+=("$s")
fi

# 4) 5 小时窗口
if [ -n "$five_pct" ]; then
  label=" 5H"
  [ -n "$five_reset" ] && label=" 5H·$(fmt_reset $(( five_reset - now )))"
  s="$(threshold "$five_pct")${five_pct}%${reset}$(col $C_WLABEL)${label}${reset}"
  segments+=("$s")
fi

# 5) 7 天窗口
if [ -n "$seven_pct" ]; then
  label=" 7D"
  [ -n "$seven_reset" ] && label=" 7D·$(fmt_reset $(( seven_reset - now )))"
  s="$(threshold "$seven_pct")${seven_pct}%${reset}$(col $C_WLABEL)${label}${reset}"
  segments+=("$s")
fi

# ---- 用 ' › ' 分隔符拼接存在的段 ----
sep="$(col $C_SEP) › ${reset}"
out=""
for i in "${!segments[@]}"; do
  if [ "$i" -eq 0 ]; then out="${segments[$i]}"; else out="${out}${sep}${segments[$i]}"; fi
done
printf '%s\n' "$out"
