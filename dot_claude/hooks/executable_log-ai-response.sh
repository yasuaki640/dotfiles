#!/bin/bash

# プロジェクトディレクトリを環境変数から取得
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# プロジェクトディレクトリ配下のログディレクトリを設定
if [ "$PROJECT_DIR" = "." ]; then
  LOG_DIR="$HOME/.claude/conversation-logs"
else
  LOG_DIR="${PROJECT_DIR}/.claude/conversation-logs"
fi
mkdir -p "$LOG_DIR"

# タイムスタンプと日付を取得(JST)
DATE=$(TZ=Asia/Tokyo date +"%Y-%m-%d")

# 日付ごとのファイル名(テキスト形式)
LOG_FILE="${LOG_DIR}/${DATE}.txt"

# 標準入力からJSONを読み込み
INPUT=$(cat)

# last_assistant_messageを直接取得（transcript_pathのパース不要）
AI_RESPONSE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

# シンプルなテキスト形式で記録
if [ -n "$AI_RESPONSE" ]; then
  # ロック取得（最大5秒待機）
  LOCK_DIR="${LOG_DIR}/.lock"
  for i in $(seq 1 50); do
    mkdir "$LOCK_DIR" 2>/dev/null && break
    sleep 0.1
  done

  cat >> "$LOG_FILE" << EOF
[A]
${AI_RESPONSE}

EOF

  # ロック解放
  rmdir "$LOCK_DIR" 2>/dev/null
fi

exit 0
