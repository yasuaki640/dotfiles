---
name: session-history
description: 過去のセッション履歴（全プロジェクトの会話ログ）を SQLite DB から検索・通読する。hooks が記録した `~/.claude/conversation-logs/conversations.db` を引く。「セッション履歴」「過去の会話」「前に話した/相談した内容」「以前のやり取り」「あのとき何を決めたか」「別プロジェクトでの会話」を遡りたい、思い出したい、検索したい、という依頼が trigger。キーワード検索・特定セッションの通読・プロジェクト横断の一覧・期間絞り込みに対応。`/search-log` 後継。
---

# セッション履歴の検索・通読

過去の全セッションの会話ログは hooks で SQLite に記録されている。どのプロジェクトからでも横断的に遡れる。引数（検索キーワード等）は `$ARGUMENTS` で受け取る。空なら何を遡りたいかユーザーに確認する。

検索・通読は **共有スクリプト `~/.claude/scripts/conversations/search.py` を必ず使う**（生 SQL を shell に手書きしない）。
このスクリプトは conversations.db を引く横断ユーティリティで、`/recap` 等からも共有される（だからこの skill ディレクトリの外に置いてある）。
理由: shell の引用符内で SQL を組み立てると検索語の `!`・`'`・空白で壊れる（過去に zsh の `!` 履歴展開で SQL が壊れた事故あり）。`search.py` は Python の sqlite3 プレースホルダで組み立てるので、検索語に何が入っても壊れない。DB は read-only で開く。

## search.py の使い方

`SEARCH=~/.claude/scripts/conversations/search.py` として:

```bash
# 1. キーワード横断検索（複数語は OR。最初から言い換えを並べる ↓）
python3 "$SEARCH" 録音 interview-record 面接録音

# 2. セッションを時系列で通読（先頭8桁でも可）
python3 "$SEARCH" --read 1ce27e0d

# 3. 直近セッション一覧（プロジェクト横断、既定30件）
python3 "$SEARCH" --recent
```

共通オプション: `--since YYYY-MM-DD` / `--until YYYY-MM-DD`（期間）、`--project SUBSTR`（project_dir 部分一致）、`--limit N`（検索上限・既定20）、`--width N`（content 表示幅・既定300、`0` で全文）。

### 検索のコツ（重要）

- **1 発目から複数表現を OR で投げる**。日本語は表記ゆれでヒットしないことが多いので、ユーザーの語をそのまま 1 語で検索しない。日本語・英語・略称・関連語を並べる:
  - 例「録音ツールの話」→ `python3 "$SEARCH" 録音 interview-record 面接録音 文字起こし`
  - 例「セッション履歴の skill」→ `python3 "$SEARCH" session-history search-log セッション履歴`
- それでも 0 件なら、より短い語・別の言い換えで再試行する。
- 文脈を追いたいときは **「キーワードで session_id を特定 → `--read` で通読」** の 2 段階。
- 結果が多い/古い話に埋もれるときは `--since` や `--project` で絞る。

## DB（参考）

- **パス**: `~/.claude/conversation-logs/conversations.db`（WALモード）
- **記録の仕組み**: `UserPromptSubmit` フックがユーザー発言を、`Stop` フックが assistant の最終応答を、それぞれリアルタイムに INSERT（`~/.claude/hooks/log-*.sh`）。

### テーブル `messages`

| カラム | 型 | 説明 |
|---|---|---|
| `id` | INTEGER PK | 連番（時系列順） |
| `session_id` | TEXT | セッションUUID |
| `project_dir` | TEXT | 作業ディレクトリの絶対パス（空のこともある） |
| `role` | TEXT | `user` または `assistant` |
| `content` | TEXT | 発言本文（user=プロンプト、assistant=最終応答のみ。途中のツール実行は含まない） |
| `created_at` | TEXT | `YYYY-MM-DDTHH:MM:SS`（JST） |

インデックス: `session_id` / `created_at` / `project_dir`。

`search.py` で表現できない特殊なクエリが要るときだけ、上記スキーマを使って直接 `sqlite3` を叩く（その場合も検索語の引用符破壊に注意）。
