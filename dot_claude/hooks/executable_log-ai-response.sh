#!/bin/bash

DB="$HOME/.claude/conversation-logs/conversations.db"

# DB未作成なら初期化
if [ ! -f "$DB" ]; then
  source "$(dirname "$0")/init-db.sh"
fi

# 標準入力からJSON読み込み
INPUT=$(cat)

AI_RESPONSE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
TIMESTAMP=$(TZ=Asia/Tokyo date +"%Y-%m-%dT%H:%M:%S")

if [ -n "$AI_RESPONSE" ]; then
  SAFE_RESPONSE=$(printf '%s' "$AI_RESPONSE" | sed "s/'/''/g")
  SAFE_PROJECT=$(printf '%s' "$PROJECT_DIR" | sed "s/'/''/g")

  sqlite3 "$DB" "INSERT INTO messages (session_id, project_dir, role, content, created_at)
    VALUES ('${SESSION_ID}', '${SAFE_PROJECT}', 'assistant', '${SAFE_RESPONSE}', '${TIMESTAMP}');"
fi

exit 0
