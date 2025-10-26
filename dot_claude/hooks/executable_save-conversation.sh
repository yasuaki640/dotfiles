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

# JSONL形式でファイルに追記
echo "${INPUT}" | jq -c --arg ts "$TIMESTAMP" --arg project "$PROJECT_DIR" \
  '{timestamp: $ts, project: $project, data: .}' >> "$HISTORY_FILE"

# エラーがなければ成功
exit 0
