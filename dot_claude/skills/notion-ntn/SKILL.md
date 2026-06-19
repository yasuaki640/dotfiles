---
name: notion-ntn
description: Notion を `ntn` CLI 経由で操作する。Notion 公式 MCP (notion-fetch / notion-search / notion-create-pages 等) で実現できない操作を依頼されたときに使う。具体的には、生の Notion 公開 API 呼び出し、ファイル(画像・添付)のアップロード、データソースのクエリ、worker の作成・デプロイ・実行など。「ntn で」「Notion CLI で」「Notion にファイルをアップロード」「Notion worker を」等の依頼、または MCP のツール一覧に該当操作が無いときが trigger。MCP で足りる読み取り/検索/ページ作成は MCP を優先する。
---

# Notion 操作: ntn CLI

`ntn` は Notion 公式 CLI (beta)。MCP で実現できない Notion 操作を担う。

## 大原則: まず help を読む

`ntn` は新しめの CLI でバージョンによって挙動が変わる。**コマンドを組み立てる前に必ず該当サブコマンドの help を読むこと。** 記憶やこの文書の例だけで引数を決めない。

```
ntn --help                 # トップレベルのコマンド一覧
ntn <command> --help       # サブコマンドの詳細 (例: ntn api --help)
ntn api ls                 # 叩ける公開 API エンドポイント一覧
ntn api <PATH> --docs      # そのエンドポイントの公式ドキュメント
ntn api <PATH> --spec      # そのエンドポイントの OpenAPI 断片
```

## MCP との使い分け

- **MCP を優先**: ページの読み取り・検索・通常のページ作成/更新・コメント取得など、`mcp__claude_ai_Notion__*` で完結する操作。
- **ntn を使う**: MCP に該当ツールが無い操作。主に以下。
  - 生の公開 API 呼び出し (`ntn api`)
  - ファイル(画像・添付)アップロード (`ntn files`)
  - データソースのクエリ/解決 (`ntn datasources`)
  - worker の作成・デプロイ・実行 (`ntn workers`)

迷ったら MCP のツール一覧を見て、該当操作が無ければ ntn を使う。

## 認証チェック (作業前に必ず)

操作前に認証が通っているか確認する。

```
ntn doctor
```

`Token valid` が `!` / `unauthorized` の場合は未認証。**`ntn login` はブラウザ認証が対話的なので Claude からは実行できない。** その場合は作業を止め、ユーザーに次を依頼する:

> プロンプトに `! ntn login` と入力して認証してください（`!` プレフィックスでこのセッション内でコマンドが実行されます）。

`NOTION_API_TOKEN` 環境変数があればキーチェーン認証を上書きできる(CI などトークン直指定のケース)。

## 主要コマンド早見表

| やりたいこと | コマンド | 補足 |
|---|---|---|
| 公開 API を直接叩く | `ntn api <PATH> [INPUT]...` | 後述の入力構文を使う |
| 叩ける API 一覧 | `ntn api ls` | |
| ページを Markdown で取得 | `ntn pages get <page-id>` | `--json` で生 JSON |
| ページを Markdown で作成 | `ntn pages create --parent <ref> --content '...'` | stdin / `$EDITOR` も可 |
| ページ本文を更新 | `ntn pages update <page-id> --content '...'` | |
| ページをゴミ箱へ | `ntn pages trash <page-id>` | |
| ファイルをアップロード | `ntn files create < file.png` | `--external-url` で外部 URL |
| アップロード状況 | `ntn files get <upload-id>` / `ntn files list` | |
| データソースをクエリ | `ntn datasources query <data-source-id>` | DB ID ではなく **data source ID** |
| DB → data source 解決 | `ntn datasources resolve <database-id>` | |
| worker 一覧/作成/デプロイ/実行 | `ntn workers ls` / `create` / `deploy` / `exec` | 詳細は `ntn workers <sub> --help` |

`--parent` の参照形式: `page:<id>` / `database:<id>` / `data-source:<id>`。

## `ntn api` 入力構文(必ず help でも再確認)

`ntn api <PATH>` の後ろの引数はリクエスト入力として解釈される。

```
Header:Value    ヘッダー              Accept:application/json
name==value     クエリパラメータ       page_size==100
path=value      ボディ(文字列)        parent[page_id]=abc123
path:=json      ボディ(型付きJSON)     archived:=true
```

- `:=` は数値・真偽・配列・オブジェクト・null に使う。`=` は常に JSON 文字列として格納。
- ネスト: `properties[count]:=10`、`children[][paragraph][rich_text][0][text][content]=Hello`
- ボディは「stdin JSON / `-d <JSON>` / インライン入力」のいずれか **1つだけ**。
- メソッドは GET 既定、ボディがあれば自動で POST、`-X/--method` が最優先。

例:
```
ntn api v1/search -d '{"query":"設計メモ"}'
ntn api v1/pages/<page-id>                       # ページ取得 (GET)
ntn api v1/data_sources/<id>/query page_size==50 # クエリ + ページサイズ
```

## 困ったら

- API 呼び出しでエラー → `-v`(verbose) を付けて再実行し、エラーチェーンを確認。
- 引数が不明 → `ntn api <PATH> --docs` で公式ドキュメントを読む。
- ページ取得が途中で切れる → `--json` で `unknown_block_ids` を確認(`ntn pages get` の注記)。
