#!/usr/bin/env python3
"""サイトの時間帯ブロック（許可時間帯以外は見られない）。

許可時間帯（既定 15:00〜21:00）以外は /etc/hosts に 0.0.0.0 を書いて指定ドメインを引けなくする。
root の LaunchDaemon が 60 秒ごとに `run` を叩き、現在時刻から決まる「あるべき状態」に
/etc/hosts を合わせる（冪等）。スリープ明け・再起動・手で行を消した場合も次の 1 分で戻る。

SelfControl を使わない理由: selfcontrol-cli の開始権限 org.eyebeam.SelfControl.startBlock は
allow-root: false で、root から起動しても毎回パスワードを求める。無人では回せないので、
SelfControl が google/youtube 系ドメインに実際にやっていること（hosts だけでのブロック）を直接やる。
SelfControl の手動ブロックとは hosts 上の節（マーカー）が別なので併用できる。

chezmoi 管理: ソースは dotfiles の dot_local/src/site-curfew/site_curfew.py で、
~/.local/src/site-curfew/ に配置される。このファイルが変わると
run_onchange_after_install-site-curfew.sh.tmpl が `install` を叩き直す（sudo のパスワードを聞く）。
root が実行するのは /usr/local/libexec のコピーなので、ソースを編集しただけでは反映されない。

使い方（手で叩く場合）:
  sudo /usr/bin/python3 ~/.local/src/site-curfew/site_curfew.py install    # root 所有の場所へコピーして launchd に登録
  sudo /usr/bin/python3 ~/.local/src/site-curfew/site_curfew.py uninstall  # 登録解除し、hosts の節も消す
  /usr/bin/python3 ~/.local/src/site-curfew/site_curfew.py status          # いまの状態と次の切り替え時刻

標準ライブラリのみ・/usr/bin/python3（3.9）で動くこと。
"""
import datetime as dt
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

DOMAINS = [
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
]
ALLOW_FROM = dt.time(15, 0)  # この時刻から
ALLOW_UNTIL = dt.time(21, 0)  # この時刻までは見られる

HOSTS = "/etc/hosts"
BEGIN = "# BEGIN SITE CURFEW"  # 前方一致で判定（旧版は末尾に " (life-dashboard)" を付けていた）
END = "# END SITE CURFEW"
LABEL = "com.yasuaki640.site-curfew"
INSTALLED_SCRIPT = "/usr/local/libexec/site_curfew.py"
PLIST = f"/Library/LaunchDaemons/{LABEL}.plist"
LOG = "/var/log/site-curfew.log"
PYTHON = "/usr/bin/python3"
INTERVAL_SEC = 60


def is_blocked_at(now):
    return not (ALLOW_FROM <= now.time() < ALLOW_UNTIL)


def next_switch(now):
    """次に状態が切り替わる時刻。"""
    candidates = []
    for days in (0, 1):
        day = now.date() + dt.timedelta(days=days)
        for t in (ALLOW_FROM, ALLOW_UNTIL):
            at = dt.datetime.combine(day, t)
            if at > now:
                candidates.append(at)
    return min(candidates)


def strip_section(text):
    """hosts 本文からこのスクリプトの節を取り除く。"""
    out, inside = [], False
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if s.startswith(BEGIN):
            inside = True
            continue
        if s == END:
            inside = False
            continue
        if not inside:
            out.append(line)
    return "".join(out)


def render(text, block):
    """block なら節を末尾に付け直し、そうでなければ節を消した hosts 本文を返す。"""
    base = strip_section(text)
    if not block:
        return base
    if base and not base.endswith("\n"):
        base += "\n"
    lines = [BEGIN]
    for d in DOMAINS:
        lines.append(f"0.0.0.0\t{d}")
        lines.append(f"::\t{d}")
    lines.append(END)
    return base + "\n".join(lines) + "\n"


def read_hosts():
    with open(HOSTS, encoding="utf-8") as f:
        return f.read()


def write_hosts(content):
    """同じディレクトリの一時ファイルに書いてから置き換える（書きかけの hosts を作らない）。"""
    path = os.path.realpath(HOSTS)
    st = os.stat(path)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".hosts.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(tmp, st.st_mode & 0o777)
        os.chown(tmp, st.st_uid, st.st_gid)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def flush_dns():
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)
    subprocess.run(["/usr/bin/killall", "-HUP", "mDNSResponder"], check=False)


def log(msg):
    print(f"{dt.datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


def apply(block):
    cur = read_hosts()
    new = render(cur, block)
    if new == cur:
        return False
    write_hosts(new)
    flush_dns()
    return True


def require_root():
    if os.geteuid() != 0:
        sys.exit(f"root で実行してください: sudo {PYTHON} {os.path.abspath(__file__)} {sys.argv[1]}")


def launchctl(*args):
    return subprocess.run(["/bin/launchctl", *args], capture_output=True, text=True)


def cmd_run():
    block = is_blocked_at(dt.datetime.now())
    if apply(block):
        log(f"{'block' if block else 'allow'}: {', '.join(DOMAINS)}")


def cmd_status():
    now = dt.datetime.now()
    block = is_blocked_at(now)
    in_hosts = BEGIN in read_hosts()
    loaded = os.path.exists(PLIST)
    print(f"時間帯: {'ブロック' if block else '許可'}（許可 {ALLOW_FROM:%H:%M}〜{ALLOW_UNTIL:%H:%M}）")
    print(f"hosts: {'ブロック行あり' if in_hosts else 'ブロック行なし'}")
    print(f"launchd: {'登録済み' if loaded else '未登録'}（{PLIST}）")
    print(f"次の切り替え: {next_switch(now):%m-%d %H:%M}")
    print(f"対象: {', '.join(DOMAINS)}")


def cmd_install():
    require_root()
    os.makedirs(os.path.dirname(INSTALLED_SCRIPT), exist_ok=True)
    shutil.copyfile(os.path.abspath(__file__), INSTALLED_SCRIPT)
    os.chown(INSTALLED_SCRIPT, 0, 0)
    os.chmod(INSTALLED_SCRIPT, 0o755)

    job = {
        "Label": LABEL,
        "ProgramArguments": [PYTHON, INSTALLED_SCRIPT, "run"],
        "RunAtLoad": True,
        "StartInterval": INTERVAL_SEC,
        "StandardOutPath": LOG,
        "StandardErrorPath": LOG,
    }
    with open(PLIST, "wb") as f:
        plistlib.dump(job, f)
    os.chown(PLIST, 0, 0)
    os.chmod(PLIST, 0o644)

    launchctl("bootout", f"system/{LABEL}")  # 再 install 時の差し替え。未登録なら失敗してよい
    r = launchctl("bootstrap", "system", PLIST)
    if r.returncode != 0:
        sys.exit(f"launchctl bootstrap に失敗: {r.stderr.strip()}")
    cmd_run()
    cmd_status()


def cmd_uninstall():
    require_root()
    launchctl("bootout", f"system/{LABEL}")
    for path in (PLIST, INSTALLED_SCRIPT):
        if os.path.exists(path):
            os.remove(path)
    if apply(False):
        log("uninstall: hosts の節を削除")
    cmd_status()


COMMANDS = {
    "run": cmd_run,
    "status": cmd_status,
    "install": cmd_install,
    "uninstall": cmd_uninstall,
}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"usage: {sys.argv[0]} {{{'|'.join(COMMANDS)}}}")
    COMMANDS[sys.argv[1]]()
