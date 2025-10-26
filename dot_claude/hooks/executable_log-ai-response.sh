#!/bin/bash

# AIレスポンスを記録するディレクトリ
LOG_DIR="$HOME/.claude/conversation-logs"
mkdir -p "$LOG_DIR"

# タイムスタンプと日付を取得（JST）
DATE=$(TZ=Asia/Tokyo date +"%Y-%m-%d")
TIMESTAMP=$(TZ=Asia/Tokyo date +"%Y-%m-%d %H:%M:%S")

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

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# transcriptファイルから最後のAIレスポンスを取得
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # transcriptから最後のassistantメッセージを抽出（テキストのみ）
  AI_RESPONSE=$(jq -sr '[.[] | select(.type == "assistant")] | last |
    if .message.content then
      [.message.content[] | select(.type == "text") | .text] | join("\n")
    else
      empty
    end' "$TRANSCRIPT_PATH")

  # シンプルなテキスト形式で記録
  if [ -n "$AI_RESPONSE" ]; then
    cat >> "$LOG_FILE" << EOF
[A]
${AI_RESPONSE}

EOF
  fi
fi

exit 0
