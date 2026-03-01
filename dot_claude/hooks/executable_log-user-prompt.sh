#!/bin/bash

# プロジェクトディレクトリを環境変数から取得
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# プロジェクトディレクトリ配下のログディレクトリを設定
if [ "$PROJECT_DIR" = "." ]; then
  # デフォルトの場合はホームディレクトリに保存
  LOG_DIR="$HOME/.claude/conversation-logs"
else
  # プロジェクトディレクトリ配下に保存
  LOG_DIR="${PROJECT_DIR}/.claude/conversation-logs"
fi
mkdir -p "$LOG_DIR"

# タイムスタンプと日付を取得(JST)
DATE=$(TZ=Asia/Tokyo date +"%Y-%m-%d")
TIMESTAMP=$(TZ=Asia/Tokyo date +"%H:%M:%S")

# 日付ごとのファイル名(テキスト形式)
LOG_FILE="${LOG_DIR}/${DATE}.txt"

# 標準入力からJSONを読み込み
INPUT=$(cat)

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# ロック取得（最大5秒待機）
LOCK_DIR="${LOG_DIR}/.lock"
for i in $(seq 1 50); do
  mkdir "$LOCK_DIR" 2>/dev/null && break
  sleep 0.1
done

# シンプルなテキスト形式で記録
if [ -n "$PROMPT" ]; then
  cat >> "$LOG_FILE" << EOF

===
${TIMESTAMP} | ${SESSION_ID:0:4}
===
[U]
${PROMPT}

EOF
fi

# ロック解放
rmdir "$LOCK_DIR" 2>/dev/null

exit 0
