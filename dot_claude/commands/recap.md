---
allowed-tools: Bash(sqlite3 *)
description: 直近の会話ログから作業の振り返りと次のタスクを提案
---

## タスク

1. 以下のコマンドで「現在のディレクトリに関連する、ログが存在する直近3日分」の会話ログを取得（ログがない日はスキップして遡る）:
   ```
   sqlite3 ~/.claude/conversation-logs/conversations.db \
     "SELECT session_id, created_at, role, content FROM messages
      WHERE project_dir = '$(pwd)'
        AND date(created_at) IN (
          SELECT DISTINCT date(created_at) FROM messages WHERE project_dir = '$(pwd)' ORDER BY date(created_at) DESC LIMIT 3
        )
      ORDER BY created_at;"
   ```

2. 取得した会話ログをセッションごとにグルーピングして分析し、以下を日本語で簡潔にまとめる:

- **直近やっていたこと** - 主な作業内容を箇条書3行で
- **現在の状態** - 完了したこと、進行中のこと
- **次にやるべきこと** - 具体的なアクションアイテム

会話が複数セッションにわたる場合は、セッション単位で時系列に整理する。
