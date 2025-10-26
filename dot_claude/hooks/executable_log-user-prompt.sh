#!/bin/bash

# ユーザープロンプトを記録するディレクトリ
LOG_DIR="$HOME/.claude/conversation-logs"
mkdir -p "$LOG_DIR"

# タイムスタンプと日付を取得（JST）
DATE=$(TZ=Asia/Tokyo date +"%Y-%m-%d")
TIMESTAMP=$(TZ=Asia/Tokyo date +"%H:%M:%S")

# プロジェクトディレクトリを環境変数から取得
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# プロジェクトディレクトリのパスを整形
if [ "$PROJECT_DIR" = "." ]; then
  PROJECT_PATH="default"
else
  PROJECT_PATH="${PROJECT_DIR#/}"
fi

# プロジェクトごとのディレクトリを作成
PROJECT_LOG_DIR="${LOG_DIR}/${PROJECT_PATH}"
mkdir -p "$PROJECT_LOG_DIR"

# 日付ごとのファイル名（テキスト形式）
LOG_FILE="${PROJECT_LOG_DIR}/${DATE}.txt"

# 標準入力からJSONを読み込み
INPUT=$(cat)

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

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

exit 0
