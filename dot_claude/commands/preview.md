---
allowed-tools: Bash(osascript *), Bash(git *), Bash(test *), Bash(pwd), Bash(echo *), Bash(command -v *)
description: git diff / Markdown / Mermaid / 画像 / git status などを Ghostty の右ペインにリッチ表示する（AppleScript 経由）
---

# プレビューを右ペインに表示する

ユーザーの曖昧な日本語指示（例「この差分見せて」「README プレビューして」「この図見せて」「今の状況見せて」）を読み取り、
**Ghostty の右隣ペインに適切なプレビューコマンドを AppleScript（`input text` / `send key`）で送り込む**。
Claude（このセッション）は左ペインで動いている前提。プレビューは右ペインで人間が眺める。

Ghostty ネイティブのスプリットは tmux と違い **Kitty graphics protocol の画像・Mermaid 図をフルリッチに描画できる**
（tmux の `allow-passthrough` 越しだと画像が潰れるため、プレビューは Ghostty 直のスプリットで出す）。

引数: `$ARGUMENTS`（無い場合は会話の直近の文脈から「何を見せたいか」を推測する）

## 前提チェック（必ず最初に実行）

```bash
# Ghostty に AppleScript で到達できるか。ウィンドウ数が取れれば OK。
osascript -e 'tell application "Ghostty" to count windows' 2>/dev/null \
  && echo "GHOSTTY_OK" || echo "NO_GHOSTTY"
```

`NO_GHOSTTY`（Ghostty に到達できない）なら、**プレビュー内容を Claude が直接ターミナルに出力する**
（`git diff | delta` 等を自分で実行して結果を見せる）にフォールバックし、その旨を一言伝える。
`GHOSTTY_OK` なら以降の手順で右ペインへ送り込む。

## プレビュー方式の鉄則（実証済み）

- **ペイン特定は `name` プロパティで行う**。Ghostty の terminal の `name` には「そのペインで最後に走ったコマンド文字列」が入る。
  Claude が動く左ペインの `name` には `skill` という語が含まれる（skill 起動中のため）。
  よって **「`name` に `skill` を含まない terminal ＝ プレビューペイン」** とみなして掃除・操作する。
- **古いプレビューは閉じてから作り直す**。`send key "q"` で TUI（mdv 等）を終了させるのは**効かない**ことが分かっている。
  プレビュー用途では終了させる必要はなく、**`close` でペインごと畳む**のが正解（TUI 実行中でも `close` は効く）。
- だから毎回のフローは「**既存プレビューペインを close → 右に split → input text でコマンド起動**」で固定する。

## 右ペインの確保（既存を畳んで作り直す）

```bash
osascript <<'APPLESCRIPT'
tell application "Ghostty"
    set w to front window
    -- 既存プレビューペイン（name に "skill" を含まない＝Claude以外）を閉じる
    repeat with t in (terminals of w)
        if (name of t) does not contain "skill" then close t
    end repeat
    delay 0.3
    -- Claudeペインを基点に右へ分割（split の戻り値が新ペイン）
    set previewTerm to split (front terminal of front window) direction right
    delay 0.5
end tell
APPLESCRIPT
```

split 直後に続けてコマンドを送るときは、同じ osascript ブロック内で `input text ... to previewTerm` まで一気に書く
（ブロックをまたぐと previewTerm 参照が切れるため）。下の実行例の形を使う。

## 何を出すか（指示 → コマンドの出し分け）

ユーザーの言葉から下記を判断して、対応するコマンドを右ペインに送る。
ファイルパスが指示に含まれていればそれを使い、無ければ文脈から補う。

| 指示の例 | 出すもの | 送るコマンド |
|---|---|---|
| 「差分」「diff」「変更見せて」 | 作業ツリーの git diff | `git diff \| delta --paging=always` |
| 「ステージ済みの差分」「コミット前の確認」 | staged の diff | `git --no-pager diff --cached \| delta --paging=always` |
| 「<file> の差分」 | 特定ファイルの diff | `git diff -- <file> \| delta --paging=always` |
| 「状況」「git status」「今どうなってる」 | git status | `git -c color.ui=always status \| less -R` |
| 「<file>.md プレビュー」「README 見せて」 | Markdown をリッチ表示（画像・Mermaid 図もインライン） | `mdv <file>.md` |
| 「この図見せて」「Mermaid 見せて」 | Mermaid 図を画像描画 | `mdv <file>.md`（md 内の Mermaid ブロックを図化）／単体 `.mmd` なら `mmp <file>.mmd` |
| 「<file>.png 見せて」「画像見せて」 | 画像をインライン表示 | `chafa <image>` |
| 「<file> 見せて」（md/画像以外） | シンタックスハイライト表示 | `bat <file>` |
| 「lazygit」「対話的に」「git 操作したい」 | lazygit 常駐 | `lazygit` |
| 「ログ」「コミット履歴」 | コミットグラフ | `git -c color.ui=always log --oneline --graph -30 \| less -R` |

迷ったら（指示が曖昧で何を見せるか不明なら）、AskUserQuestion で「diff / status / md・図プレビュー」のどれかを 1 問だけ確認する。
ファイルパスが必要なのに不明なときも同様に 1 問だけ確認する。勝手に重い lazygit を常駐させない。

`mdv` はインタラクティブ TUI（j/k スクロール）。画像・Mermaid 図がフルリッチで出る。終了は不要で、次のプレビュー時に close で畳まれる。

## 実行例

ユーザー「この差分見せて」→
```bash
PREVIEW_CMD='git diff | delta --paging=always'
osascript <<APPLESCRIPT
tell application "Ghostty"
    set w to front window
    repeat with t in (terminals of w)
        if (name of t) does not contain "skill" then close t
    end repeat
    delay 0.3
    set previewTerm to split (front terminal of front window) direction right
    delay 0.5
    input text "cd $(pwd) && $PREVIEW_CMD" to previewTerm
    send key "enter" to previewTerm
end tell
APPLESCRIPT
```

ユーザー「README 見せて」→ `PREVIEW_CMD='mdv README.md'` に差し替えて同じ形。
送り終えたら「右ペインに git diff を出しました」のように**一言だけ**報告する（プレビュー内容そのものは Claude が再掲しない）。

## 閉じる（「プレビュー消して」「閉じて」）

```bash
osascript <<'APPLESCRIPT'
tell application "Ghostty"
    set w to front window
    repeat with t in (terminals of w)
        if (name of t) does not contain "skill" then close t
    end repeat
end tell
APPLESCRIPT
```

TUI（mdv 等）実行中でも `close` でペインごと消える。閉じたら「プレビューを閉じました」と一言報告する。

## 注意

- AppleScript ヒアドキュメントは、変数展開が要るとき `<<APPLESCRIPT`（クォート無し）、不要なら `<<'APPLESCRIPT'`（クォート有り）を使い分ける。
- 送るコマンド文字列に `!` を含めない（zsh の履歴展開対策）。`pwd` はバックグラウンドジョブだとプレビューしたい cwd と違うことがあるので、対象ディレクトリが明確なら絶対パスで `cd` する。
- `front window` が必ずしも操作中ウィンドウとは限らないが、Claude が動くペインは `name` に `skill` を含むので、その判定でプレビューペインだけを安全に対象にできる。
- `mdv` `chafa` `mmp` `delta` `glow` `bat` `lazygit` は導入済み前提。万一 `command -v` で無ければ素の `git diff` / `cat` にフォールバックする。
- tmux 内では Kitty graphics の画像が潰れるため、このスキルは **Ghostty 直のスプリット**を前提にしている。tmux を使う運用に戻った場合は別途 tmux 版が必要。
```
