#!/usr/bin/env python3
"""時間帯に応じて macOS Night Shift の色温度を合わせる。

launchd から時刻発火・定期実行・ログイン時の 3 系統で呼ばれる前提で、
「今が何時か」から期待値を計算して現在値と違うときだけ適用する冪等な作りにしてある。
スリープやシャットダウンで発火を取りこぼしても、次に走った時点で正しい状態へ収束する。
"""

import argparse
import datetime as dt
import shutil
import subprocess
import sys

# (開始時刻, 色温度) を開始時刻の昇順で並べる。
# 06:00-17:00 は弱め、それ以外の夜間は強め。
SCHEDULE = [
    (dt.time(6, 0), 30),
    (dt.time(17, 0), 50),
]


def expected_temp(now: dt.time) -> int:
    """now が属する区間の色温度を返す。

    最初の区間より前（=深夜）は日付をまたいだ最終区間の続きなので末尾の値を使う。
    """
    result = SCHEDULE[-1][1]
    for start, temp in SCHEDULE:
        if now >= start:
            result = temp
    return result


def nightlight(binary: str, *args: str) -> str:
    proc = subprocess.run(
        [binary, *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


def current_temp(binary: str) -> int | None:
    """`nightlight temp` の出力から現在の色温度を取り出す。"""
    out = nightlight(binary, "temp")
    digits = "".join(c for c in out if c.isdigit())
    return int(digits) if digits else None


def find_binary() -> str:
    # launchd の PATH は最小限なので Homebrew の場所も直接見る。
    for candidate in ("nightlight", "/opt/homebrew/bin/nightlight", "/usr/local/bin/nightlight"):
        found = shutil.which(candidate) or (candidate if candidate.startswith("/") else None)
        if found and shutil.os.path.exists(found):
            return found
    raise SystemExit("nightlight が見つからない。brew install smudge/smudge/nightlight を実行すること")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="適用せず、期待値と現在値だけを表示する",
    )
    args = parser.parse_args()

    binary = find_binary()
    now = dt.datetime.now()
    want = expected_temp(now.time())
    have = current_temp(binary)

    stamp = now.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{stamp}] expected={want} current={have}")

    if args.dry_run:
        return 0

    # スケジュール機能は使わず常時オンで温度だけ変える方式なので、
    # 何かの拍子に切れていても毎回オンへ寄せておく。
    nightlight(binary, "schedule", "off")
    nightlight(binary, "on")

    if have != want:
        nightlight(binary, "temp", str(want))
        print(f"[{stamp}] applied temp {have} -> {want}")
    else:
        print(f"[{stamp}] already {want}, no change")

    return 0


if __name__ == "__main__":
    sys.exit(main())
