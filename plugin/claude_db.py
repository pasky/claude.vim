#!/usr/bin/env python3

import argparse
import json
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

def get_db_path():
    import os
    xdg_data = Path.home() / ".local/share"
    if "XDG_DATA_HOME" in os.environ:
        xdg_data = Path(os.environ["XDG_DATA_HOME"])
    db_dir = xdg_data / "claude-vim"
    db_dir.mkdir(parents=True, exist_ok=True)
    return db_dir / "chats.db"

def init_db(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            archived_at TIMESTAMP
        );
        
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY,
            chat_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (chat_id) REFERENCES chats(id)
        );
    """)
    conn.commit()

def save_chat(conn, title, messages):
    cursor = conn.cursor()
    cursor.execute("INSERT INTO chats (title) VALUES (?)", (title,))
    chat_id = cursor.lastrowid
    
    for msg in messages:
        # Ensure content is properly serialized
        content = msg["content"]
        if isinstance(content, (list, dict)):
            content = json.dumps(content)
        elif not isinstance(content, str):
            content = str(content)

        cursor.execute(
            "INSERT INTO messages (chat_id, role, content) VALUES (?, ?, ?)",
            (chat_id, msg["role"], content)
        )
    
    conn.commit()
    return chat_id

def load_chat(conn, chat_id):
    cursor = conn.cursor()
    chat = cursor.execute("SELECT title FROM chats WHERE id = ?", (chat_id,)).fetchone()
    if not chat:
        return None
        
    messages = cursor.execute(
        "SELECT role, content FROM messages WHERE chat_id = ? ORDER BY created_at",
        (chat_id,)
    ).fetchall()
    
    return {
        "title": chat[0],
        "messages": [{"role": m[0], "content": m[1]} for m in messages]
    }

def list_chats(conn, include_archived=False):
    cursor = conn.cursor()
    if include_archived:
        chats = cursor.execute(
            "SELECT id, title, created_at, archived_at FROM chats ORDER BY created_at DESC"
        ).fetchall()
    else:
        chats = cursor.execute(
            "SELECT id, title, created_at, archived_at FROM chats WHERE archived_at IS NULL ORDER BY created_at DESC"
        ).fetchall()
    return [{"id": c[0], "title": c[1], "created_at": c[2], "archived_at": c[3]} for c in chats]

def archive_chat(conn, chat_id):
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE chats SET archived_at = CURRENT_TIMESTAMP WHERE id = ?",
        (chat_id,)
    )
    conn.commit()

def delete_chat(conn, chat_id):
    cursor = conn.cursor()
    cursor.execute("DELETE FROM messages WHERE chat_id = ?", (chat_id,))
    cursor.execute("DELETE FROM chats WHERE id = ?", (chat_id,))
    conn.commit()

def main():
    parser = argparse.ArgumentParser(description="Claude Chat DB Helper")
    parser.add_argument("action", choices=["save", "load", "list", "archive", "delete"])
    parser.add_argument("--title", help="Chat title for save action")
    parser.add_argument("--messages", help="JSON messages for save action")
    parser.add_argument("--chat-id", type=int, help="Chat ID for load/archive/delete actions")
    parser.add_argument("--include-archived", action="store_true", help="Include archived chats in list")
    args = parser.parse_args()

    conn = sqlite3.connect(get_db_path())
    init_db(conn)

    try:
        if args.action == "save":
            if not args.title or not args.messages:
                print("Error: title and messages required for save", file=sys.stderr)
                sys.exit(1)
            chat_id = save_chat(conn, args.title, json.loads(args.messages))
            print(json.dumps({"chat_id": chat_id}))
            
        elif args.action == "load":
            if not args.chat_id:
                print("Error: chat_id required for load", file=sys.stderr)
                sys.exit(1)
            chat = load_chat(conn, args.chat_id)
            if chat:
                print(json.dumps(chat))
            else:
                print("Error: chat not found", file=sys.stderr)
                sys.exit(1)
                
        elif args.action == "list":
            chats = list_chats(conn, args.include_archived)
            print(json.dumps({"chats": chats}))
            
        elif args.action == "archive":
            if not args.chat_id:
                print("Error: chat_id required for archive", file=sys.stderr)
                sys.exit(1)
            archive_chat(conn, args.chat_id)
            
        elif args.action == "delete":
            if not args.chat_id:
                print("Error: chat_id required for delete", file=sys.stderr)
                sys.exit(1)
            delete_chat(conn, args.chat_id)
            
    finally:
        conn.close()

if __name__ == "__main__":
    main()
