#!/bin/bash
# Claude プラン使用量（5時間窓）を status line に表示する。
# rate_limits は Claude.ai サブスク(Pro/Max)で、セッション最初の API 応答後にのみ現れる。
input=$(cat)

pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

if [ -z "$pct" ]; then
  # まだ rate_limits が来ていない（最初の API 応答前 など）
  echo "5h: --"
  exit 0
fi

# 整数化
pct_int=${pct%.*}
[ -z "$pct_int" ] && pct_int=0

# 10 マスのプログレスバー（▓ = 使用済み, ░ = 残り）
filled=$((pct_int / 10))
[ "$filled" -gt 10 ] && filled=10
empty=$((10 - filled))
bar=""
for ((i = 0; i < filled; i++)); do bar+="▓"; done
for ((i = 0; i < empty; i++)); do bar+="░"; done

# リセットまでの残り時間
remain=""
if [ -n "$resets_at" ]; then
  now=$(date +%s)
  diff=$((resets_at - now))
  if [ "$diff" -gt 0 ]; then
    h=$((diff / 3600))
    m=$(((diff % 3600) / 60))
    remain=$(printf " (reset %dh%02dm)" "$h" "$m")
  fi
fi

# 色分け: 80%以上=赤, 50%以上=黄, それ未満=緑
if [ "$pct_int" -ge 80 ]; then
  color='\033[31m'
elif [ "$pct_int" -ge 50 ]; then
  color='\033[33m'
else
  color='\033[32m'
fi
reset='\033[0m'

printf "${color}5h ${bar} %d%%${reset}%s\n" "$pct_int" "$remain"
