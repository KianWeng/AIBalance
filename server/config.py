"""配置管理 - 从 .env 文件加载 API Key 和 Cookie"""

import os
import sqlite3
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()


def _read_cursor_token_from_local() -> str:
    """尝试从本地 Cursor 应用数据中自动读取 accessToken"""
    db_path = Path.home() / "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    if not db_path.exists():
        return ""
    try:
        conn = sqlite3.connect(str(db_path))
        cursor = conn.execute(
            "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
        )
        row = cursor.fetchone()
        conn.close()
        return row[0] if row else ""
    except Exception:
        return ""


class Config:
    # Anthropic
    ANTHROPIC_SESSION_COOKIE: str = os.getenv("ANTHROPIC_SESSION_COOKIE", "")

    # OpenAI
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_SESSION_TOKEN: str = os.getenv("OPENAI_SESSION_TOKEN", "")

    # Cursor - 支持手动配置 accessToken 或自动从本地 Cursor 应用读取
    CURSOR_ACCESS_TOKEN: str = os.getenv("CURSOR_ACCESS_TOKEN", "") or _read_cursor_token_from_local()
    CURSOR_SESSION_COOKIE: str = os.getenv("CURSOR_SESSION_COOKIE", "")  # 已弃用，保留兼容
    CURSOR_TOTAL_QUOTA: float = float(os.getenv("CURSOR_TOTAL_QUOTA", "0") or "0")  # 手动配置总额度 (美元)

    # Google
    GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")

    # DeepSeek
    DEEPSEEK_API_KEY: str = os.getenv("DEEPSEEK_API_KEY", "")

    # 服务配置
    REFRESH_INTERVAL: int = int(os.getenv("REFRESH_INTERVAL", "300"))
    SERVER_PORT: int = int(os.getenv("SERVER_PORT", "8787"))
