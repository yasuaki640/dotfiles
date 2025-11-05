---
allowed-tools: Bash(git add:*), Bash(git diff:*), Bash(git status:*)
description: 現在の差分をcommitしてpushします
---

## Your task

現在の差分を確認し、commitメッセージを生成してcommit & pushを実行してください。

1. `git status` で現在の状態を確認
2. `git diff` で差分を確認
3. すべての変更をステージング: `git add -A`
4. commitメッセージを生成してcommit
5. リモートにpush: `git push`

コミットメッセージは引数として渡された場合はそれを使用し、渡されていない場合は差分から適切なメッセージを生成してください。

引数: `$ARGUMENTS`
