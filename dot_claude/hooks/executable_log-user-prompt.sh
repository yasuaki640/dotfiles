#!/bin/bash

# ネスト起動ガード: auto-commit-push.sh 等が起動した子 claude -p からの
# 再発火を無視する。
[ -n "${LIFE_DASHBOARD_HOOK_NESTED:-}" ] && exit 0

DB="$HOME/.claude/conversation-logs/conversations.db"

# DB未作成なら初期化
if [ ! -f "$DB" ]; then
  source "$(dirname "$0")/init-db.sh"
fi

# 標準入力からJSON読み込み
INPUT=$(cat)

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
TIMESTAMP=$(TZ=Asia/Tokyo date +"%Y-%m-%dT%H:%M:%S")

if [ -n "$PROMPT" ]; then
  # パラメータバインドの代わりにsedでシングルクォートをエスケープ
  SAFE_PROMPT=$(printf '%s' "$PROMPT" | sed "s/'/''/g")
  SAFE_PROJECT=$(printf '%s' "$PROJECT_DIR" | sed "s/'/''/g")

  sqlite3 "$DB" "INSERT INTO messages (session_id, project_dir, role, content, created_at)
    VALUES ('${SESSION_ID}', '${SAFE_PROJECT}', 'user', '${SAFE_PROMPT}', '${TIMESTAMP}');"
fi

exit 0
