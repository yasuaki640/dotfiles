#!/usr/bin/env python3
"""セッション履歴 (conversations.db) を安全に検索・通読するヘルパ。

shell の引用符で SQL を組み立てると文字列が壊れやすい（過去に zsh の `!`
履歴展開で SQL が壊れた事故あり）。Python の sqlite3 プレースホルダで
組み立てることで、検索語に何が入っても壊れない。

使い方:
  search.py KEYWORD [KEYWORD ...]   # 複数語を OR 検索（横断）
  search.py --read SESSION_ID       # セッションを時系列で通読（先頭8桁でも可）
  search.py --recent [N]            # 直近セッション一覧（既定30）
  search.py --recap [DIR]           # 指定dir(既定: $PWD)の直近Nセッション日分を時系列で全取得（/recap 用）

オプション:
  --since YYYY-MM-DD / --until YYYY-MM-DD  期間で絞る
  --project SUBSTR                          project_dir 部分一致で絞る
  --limit N                                 検索結果の上限（既定20）
  --width N                                 各 content の表示幅（既定300, 0で全文）
"""
import argparse
import os
import sqlite3
import sys

DB = os.path.expanduser("~/.claude/conversation-logs/conversations.db")


def connect():
    if not os.path.exists(DB):
        sys.exit(f"DB が見つかりません: {DB}")
    # 読み取り専用で開く（WAL のまま壊さない）
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def clip(text, width):
    text = text or ""
    if width and len(text) > width:
        return text[:width] + "…"
    return text


def cmd_search(args):
    con = connect()
    # 各キーワードを OR でつなぐ。語ごとに LIKE 1 つ＝部分一致。
    likes = " OR ".join("content LIKE ?" for _ in args.keywords)
    params = [f"%{k}%" for k in args.keywords]
    where = [f"({likes})"]
    if args.since:
        where.append("created_at >= ?")
        params.append(args.since)
    if args.until:
        where.append("created_at < ?")
        params.append(args.until)
    if args.project:
        where.append("project_dir LIKE ?")
        params.append(f"%{args.project}%")
    sql = (
        "SELECT created_at, session_id, role, content FROM messages "
        f"WHERE {' AND '.join(where)} ORDER BY id DESC LIMIT ?"
    )
    params.append(args.limit)
    rows = con.execute(sql, params).fetchall()
    if not rows:
        print("該当する会話ログが見つかりませんでした。語を短く / 別表現で再検索してください。")
        return
    # セッションごとにグルーピング（時系列＝古い順に整形）
    groups = {}
    order = []
    for r in reversed(rows):
        sid = r["session_id"]
        if sid not in groups:
            groups[sid] = {"date": r["created_at"][:10], "msgs": []}
            order.append(sid)
        tag = "U" if r["role"] == "user" else "A"
        groups[sid]["msgs"].append((tag, clip(r["content"], args.width)))
    for sid in order:
        g = groups[sid]
        print(f"### セッション: {sid[:8]} ({g['date']})")
        for tag, text in g["msgs"]:
            print(f"- [{tag}] {text}")
        print()


def cmd_read(args):
    con = connect()
    sid = args.read
    # 先頭8桁などの前方一致も許容
    if len(sid) < 36:
        match = con.execute(
            "SELECT DISTINCT session_id FROM messages WHERE session_id LIKE ?",
            (sid + "%",),
        ).fetchall()
        if not match:
            sys.exit(f"session_id が見つかりません: {sid}")
        if len(match) > 1:
            print("複数の session_id にマッチ:", ", ".join(m["session_id"][:8] for m in match))
            sys.exit(1)
        sid = match[0]["session_id"]
    rows = con.execute(
        "SELECT role, content, created_at FROM messages WHERE session_id=? ORDER BY id",
        (sid,),
    ).fetchall()
    print(f"### セッション {sid[:8]} 通読 ({len(rows)} メッセージ)\n")
    for r in rows:
        tag = "U" if r["role"] == "user" else "A"
        print(f"--- [{tag}] {r['created_at']} ---")
        print(clip(r["content"], args.width))
        print()


def cmd_recent(args):
    con = connect()
    where = []
    params = []
    if args.project:
        where.append("project_dir LIKE ?")
        params.append(f"%{args.project}%")
    if args.since:
        where.append("created_at >= ?")
        params.append(args.since)
    sql = "SELECT substr(session_id,1,8) sid, MIN(created_at) started, project_dir, COUNT(*) msgs FROM messages"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " GROUP BY session_id ORDER BY started DESC LIMIT ?"
    params.append(args.n)
    for r in con.execute(sql, params).fetchall():
        print(f"{r['started']}  {r['sid']}  ({r['msgs']:>3} msgs)  {r['project_dir'] or ''}")


def cmd_recap(args):
    con = connect()
    # 指定 dir（既定 $PWD）に紐づく、ログが存在する直近 N 日分を時系列で全取得。
    # ログが無い日は自然にスキップされる（DISTINCT date の上位 N 日を採るため）。
    proj = args.recap if isinstance(args.recap, str) else os.getcwd()
    days = args.days
    rows = con.execute(
        """
        SELECT session_id, created_at, role, content FROM messages
        WHERE project_dir = ?
          AND date(created_at) IN (
            SELECT DISTINCT date(created_at) FROM messages
            WHERE project_dir = ? ORDER BY date(created_at) DESC LIMIT ?
          )
        ORDER BY created_at
        """,
        (proj, proj, days),
    ).fetchall()
    if not rows:
        print(f"このディレクトリ（{proj}）の会話ログが見つかりませんでした。")
        return
    cur = None
    for r in rows:
        sid = r["session_id"]
        if sid != cur:
            cur = sid
            print(f"\n### セッション: {sid[:8]} ({r['created_at'][:10]})")
        tag = "U" if r["role"] == "user" else "A"
        print(f"- [{tag}] {clip(r['content'], args.width)}")


def main():
    p = argparse.ArgumentParser(description="セッション履歴 検索・通読")
    p.add_argument("keywords", nargs="*", help="検索語（複数指定で OR 検索）")
    p.add_argument("--read", metavar="SID", help="セッションを通読（先頭8桁可）")
    p.add_argument("--recent", nargs="?", const=30, type=int, metavar="N", dest="n", help="直近セッション一覧")
    p.add_argument("--recap", nargs="?", const=True, metavar="DIR", help="指定dir(既定$PWD)の直近Nセッション日分を時系列で全取得")
    p.add_argument("--days", type=int, default=3, help="--recap で遡る日数（既定3）")
    p.add_argument("--since", help="YYYY-MM-DD 以降")
    p.add_argument("--until", help="YYYY-MM-DD 未満")
    p.add_argument("--project", help="project_dir 部分一致")
    p.add_argument("--limit", type=int, default=20, help="検索結果上限（既定20）")
    p.add_argument("--width", type=int, default=300, help="content 表示幅（既定300, 0で全文）")
    args = p.parse_args()

    if args.read:
        cmd_read(args)
    elif args.recap is not None:
        cmd_recap(args)
    elif args.n is not None:
        cmd_recent(args)
    elif args.keywords:
        cmd_search(args)
    else:
        p.print_help()
        sys.exit("\n検索語 / --read / --recent のいずれかを指定してください。")


if __name__ == "__main__":
    main()
