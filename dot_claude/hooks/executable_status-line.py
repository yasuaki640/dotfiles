#!/usr/bin/env python3
"""Claude Code status line.

stdin から JSON セッションデータを受け取り、2 行を出力する:
  1 行目: [モデル名] 📁 ディレクトリ | 🌿 ブランチ
  2 行目: Claude プラン 5 時間窓の使用率 42% (reset 13:23) | ctx 8%

rate_limits は Claude.ai サブスク (Pro/Max) で、セッション最初の API 応答後に
のみ現れる。それまでは使用率を "--" と表示する。
ctx は現在のコンテキストウィンドウ占有率 (context_window.used_percentage)。
こちらも最初の API 応答前は null なので "--" と表示する。
"""
import json
import os
import subprocess
import sys
import time

# ANSI カラー
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
DIM = "\033[2m"
RESET = "\033[0m"


def git_branch() -> str:
    try:
        return subprocess.check_output(
            ["git", "branch", "--show-current"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""


def fmt_reset_time(resets_at) -> str:
    """リセット時刻を ' (reset 13:23)' 形式（24時間制・ローカル時刻）で返す。"""
    if not resets_at:
        return ""
    t = time.localtime(int(resets_at))
    return f" (reset {t.tm_hour}:{t.tm_min:02d})"


def main() -> None:
    data = json.load(sys.stdin)

    model = data.get("model", {}).get("display_name", "Claude")
    # "(1M context)" は冗長なので "1M" に短縮
    model = model.replace("(1M context)", "1M")
    directory = os.path.basename(data.get("workspace", {}).get("current_dir", "") or "")

    # 1 行目: モデル・ディレクトリ・ブランチ
    line1 = f"{CYAN}[{model}]{RESET} 📁 {directory}"
    branch = git_branch()
    if branch:
        line1 += f" | 🌿 {branch}"

    # 2 行目: 5 時間窓の使用率
    five_hour = (data.get("rate_limits", {}) or {}).get("five_hour", {}) or {}
    raw_pct = five_hour.get("used_percentage")

    if raw_pct is None:
        # まだ rate_limits が来ていない（最初の API 応答前 など）
        line2 = "--"
    else:
        pct = int(raw_pct)
        if pct >= 80:
            pct_color = RED
        elif pct >= 50:
            pct_color = YELLOW
        else:
            pct_color = GREEN
        remain = fmt_reset_time(five_hour.get("resets_at"))
        line2 = f"{pct_color}{pct}%{RESET}{remain}"

    # 2 行目末尾: 現在のコンテキストウィンドウ占有率
    ctx_pct = (data.get("context_window", {}) or {}).get("used_percentage")
    if ctx_pct is None:
        line2 += f" {DIM}|{RESET} ctx --"
    else:
        cp = int(ctx_pct)
        if cp >= 80:
            ctx_color = RED
        elif cp >= 50:
            ctx_color = YELLOW
        else:
            ctx_color = GREEN
        line2 += f" {DIM}|{RESET} ctx {ctx_color}{cp}%{RESET}"

    print(line1)
    print(line2)


if __name__ == "__main__":
    main()
