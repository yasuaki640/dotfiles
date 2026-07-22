# Neovim レビュー環境 チートシート

リーダーキー = **Space**。Space を押して少し待つと候補が出る（which-key）。

## 起動と移動
| 操作 | キー |
|---|---|
| ファイルを探す（あいまい） | `Space f f` |
| 全文検索（grep） | `Space f g` |
| カーソル下の語を検索 | `Space f w` |
| 最近開いたファイル | `Space f r` |
| 開いてるバッファ一覧 | `Space f b` |
| ファイルツリー開閉 | `Space e` |
| ウィンドウ間移動 | `Ctrl + h/j/k/l` |
| バッファ切替 | `Shift + h` / `Shift + l` |

## 読む（LSP）※ LSP が付いた言語で有効
| 操作 | キー |
|---|---|
| 定義へジャンプ | `g d` |
| 参照を一覧 | `g r` |
| ホバー（型・説明） | `K` |
| ファイル内シンボル一覧 | `Space d s` |
| 戻る（ジャンプ履歴） | `Ctrl + o` |

## git diff レビュー（主役）
| 操作 | キー |
|---|---|
| 差分レビュー（作業ツリー） | `Space g d` |
| main との差分（ブランチ全体） | `Space g m` |
| このファイルの変更履歴 | `Space g h` |
| リポ全体の履歴 | `Space g H` |
| 差分ビューを閉じる | `Space g x` |
| lazygit を開く | `Space g g` |

### diffview 画面内
- 左のファイルリストを `j/k` で選び `Enter` で開く
- `]h` / `[h` で次/前の変更ハンクへ
- `Space g x` で閉じる

### 行単位 git（gitsigns）
| 操作 | キー |
|---|---|
| 次/前の変更ハンク | `]h` / `[h` |
| ハンクの diff を覗く | `Space h p` |
| この行の blame | `Space h b` |

## PR レビュー（octo / GitHub）
| 操作 | キー |
|---|---|
| PR 一覧 | `Space o p` |
| PR を検索 | `Space o o` |
| PR レビュー開始 | `Space o r` |
| Issue 一覧 | `Space o i` |

## ターミナル単体でも使える（nvim 不要）
- `lazygit` … diff / ステージ / 履歴を TUI で
- `gh pr diff <番号>` … PR 差分をターミナルに表示（delta で色付き）
- `gh pr view <番号> --web` … ブラウザで PR を開く

## 困ったとき
- `:checkhealth` … 環境診断
- `:Lazy` … プラグイン管理画面（更新は `U`）
- `:Mason` … LSP サーバの追加/削除
- `:TSInstall <言語>` … シンタックスパーサ追加

## 元の AstroNvim に戻したいとき
退避先（消してない）:
- `~/.config/nvim.astro-bak-20260531-080450`
- `~/.local/share/nvim.astro-bak-20260531-080450`

戻し方:
```sh
rm -rf ~/.config/nvim ~/.local/share/nvim
mv ~/.config/nvim.astro-bak-20260531-080450 ~/.config/nvim
mv ~/.local/share/nvim.astro-bak-20260531-080450 ~/.local/share/nvim
```
