#!/bin/bash

# 会話履歴を保存するディレクトリ
HISTORY_BASE_DIR="$HOME/.claude/conversation-history"

# ディレクトリが存在しない場合は作成
mkdir -p "$HISTORY_BASE_DIR"

# タイムスタンプと日付を取得
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date -u +"%Y-%m-%d")

# 日付ごとのファイル名
HISTORY_FILE="${HISTORY_BASE_DIR}/${DATE}.jsonl"

# 標準入力からJSON全体を読み込む
INPUT=$(cat)

# プロジェクトディレクトリを環境変数から取得
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# プロジェクトディレクトリのパスをそのまま使う(先頭の/を除去)
if [ "$PROJECT_DIR" = "." ]; then
  PROJECT_PATH="default"
else
  PROJECT_PATH="${PROJECT_DIR#/}"
fi

# プロジェクトごとのディレクトリを作成
PROJECT_HISTORY_DIR="${HISTORY_BASE_DIR}/${PROJECT_PATH}"
mkdir -p "$PROJECT_HISTORY_DIR"

# 日付ごとのファイル名を更新
HISTORY_FILE="${PROJECT_HISTORY_DIR}/${DATE}.jsonl"

# 不要なフィールドを削除してJSONL形式でファイルに追記
# 削除するもの: tool_response（大きい）, transcript_path, cwd, session_id, permission_mode（定型的）
echo "${INPUT}" | jq -c --arg ts "$TIMESTAMP" --arg project "$PROJECT_DIR" \
  '{timestamp: $ts, project: $project, data: (. | del(.tool_response, .transcript_path, .cwd, .session_id, .permission_mode))}' >> "$HISTORY_FILE"

# エラーがなければ成功
exit 0
