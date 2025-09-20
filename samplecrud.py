import sqlite3
from datetime import datetime
from tabulate import tabulate

# データベース接続（無ければ作成）
conn = sqlite3.connect("blog.db")
cur = conn.cursor()

# テーブル作成
cur.execute("""
CREATE TABLE IF NOT EXISTS posts (
    post_id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    author TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    tags TEXT,
    status TEXT NOT NULL
)
""")
conn.commit()

# 投稿作成
def create_post(title, content, author, tags=[], status="draft"):
    now = datetime.now().isoformat()
    cur.execute("""
        INSERT INTO posts (title, content, author, created_at, updated_at, tags, status)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (title, content, author, now, now, ",".join(tags), status))
    conn.commit()

# 投稿一覧表示
def list_posts(show_all=False):
    if show_all:
        cur.execute("SELECT * FROM posts ORDER BY created_at DESC")
    else:
        cur.execute("SELECT * FROM posts WHERE status='published' ORDER BY created_at DESC")
    rows = cur.fetchall()
    print(tabulate(rows, headers=["ID","Title","Content","Author","Created","Updated","Tags","Status"], tablefmt="grid"))

# 投稿更新
def update_post(post_id, **kwargs):
    fields = []
    values = []
    for key, value in kwargs.items():
        if key in ["title","content","author","tags","status"]:
            if key == "tags":
                value = ",".join(value)  # リストを文字列に変換
            fields.append(f"{key}=?")
            values.append(value)
    values.append(datetime.now().isoformat())  # updated_at
    values.append(post_id)
    cur.execute(f"UPDATE posts SET {', '.join(fields)}, updated_at=? WHERE post_id=?", values)
    conn.commit()

# 投稿削除
def delete_post(post_id):
    cur.execute("DELETE FROM posts WHERE post_id=?", (post_id,))
    conn.commit()

# サンプル投稿追加
create_post("初めてのブログ投稿", "これは私の最初のブログです。", "山田太郎", ["はじめて", "自己紹介"], "published")
create_post("Pythonの魅力", "Pythonは学びやすく便利です。", "佐藤花子", ["Python","プログラミング"], "published")
create_post("ブログのデザイン変更", "ブログデザインを変更しました。", "山田太郎", ["ブログ","デザイン"], "draft")

# 投稿一覧表示
list_posts(show_all=True)

# 投稿更新例
# update_post(3, status="published", title="ブログデザインを改善")

# 投稿削除例
# delete_post(2)
