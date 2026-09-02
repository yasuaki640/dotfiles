#!/bin/bash
# Claude Code 通知スクリプト
# 使い方:
#   echo '{"title":"...","message":"..."}' | bash notify.sh                (Notification hook)
#   echo '{"last_assistant_message":"..."}' | bash notify.sh               (Stop hook)
#   bash notify.sh "タイトル" "メッセージ"                                    (引数モード)

# ネスト起動ガード: auto-commit-push.sh 等が起動した子 claude -p からの
# 再発火を無視する（commit メッセージ等が通知に暴発するのを防ぐ）。
[ -n "${LIFE_DASHBOARD_HOOK_NESTED:-}" ] && exit 0

MAX_LEN=100

if [ $# -ge 2 ]; then
  TITLE="$1"
  MESSAGE="$2"
else
  INPUT=$(cat)

  # Stop hook: last_assistant_message から冒頭を抽出
  ASSISTANT_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
  if [ -n "$ASSISTANT_MSG" ]; then
    TITLE="Claude Code"
    # 改行を空白に置換し、先頭MAX_LEN文字を切り出す
    MESSAGE=$(printf '%s' "$ASSISTANT_MSG" | tr '\n' ' ' | cut -c 1-"$MAX_LEN")
    [ ${#ASSISTANT_MSG} -gt "$MAX_LEN" ] && MESSAGE="${MESSAGE}..."
  else
    # Notification hook: title/message を使用
    TITLE=$(echo "$INPUT" | jq -r '.title // "Claude Code"')
    MESSAGE=$(echo "$INPUT" | jq -r '.message // ""')
  fi
fi

[ -z "$MESSAGE" ] && exit 0

terminal-notifier -title "$TITLE" -message "$MESSAGE" -sound Glass >/dev/null 2>&1 &

exit 0
