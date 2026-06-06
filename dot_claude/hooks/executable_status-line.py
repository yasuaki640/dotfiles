#!/usr/bin/env python3
"""Claude Code status line.

stdin から JSON セッションデータを受け取り、2 行を出力する:
  1 行目: [モデル名] 📁 ディレクトリ | 🌿 ブランチ
  2 行目: Claude プラン 5 時間窓の使用率バー 42% (reset 4h51m)

rate_limits は Claude.ai サブスク (Pro/Max) で、セッション最初の API 応答後に
のみ現れる。それまでは使用率を "--" と表示する。
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

BAR_WIDTH = 10


def git_branch() -> str:
    try:
        return subprocess.check_output(
            ["git", "branch", "--show-current"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""


def fmt_remaining(resets_at) -> str:
    """リセットまでの残り時間を ' (reset 4h51m)' 形式で返す。"""
    if not resets_at:
        return ""
    diff = int(resets_at) - int(time.time())
    if diff <= 0:
        return ""
    h, m = diff // 3600, (diff % 3600) // 60
    return f" (reset {h}h{m:02d}m)"


def main() -> None:
    data = json.load(sys.stdin)

    model = data.get("model", {}).get("display_name", "Claude")
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
        line2 = "5h --"
    else:
        pct = int(raw_pct)
        if pct >= 80:
            bar_color = RED
        elif pct >= 50:
            bar_color = YELLOW
        else:
            bar_color = GREEN
        filled = min(pct * BAR_WIDTH // 100, BAR_WIDTH)
        empty = BAR_WIDTH - filled
        bar = f"{bar_color}{'▰' * filled}{RESET}{DIM}{'▱' * empty}{RESET}"
        remain = fmt_remaining(five_hour.get("resets_at"))
        line2 = f"5h {bar} {pct}%{remain}"

    print(line1)
    print(line2)


if __name__ == "__main__":
    main()
