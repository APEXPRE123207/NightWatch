"""
Night Watch — SQLite Database (Section 4)

Stores session metadata and event records.  Audio clips are saved as
.wav files on disk; the database only stores the path.
"""

import os
import sqlite3
from datetime import datetime


class NightWatchDB:
    """Thin wrapper around the SQLite event database."""

    def __init__(self, db_path: str):
        self._db_path = db_path
        os.makedirs(os.path.dirname(db_path) or ".", exist_ok=True)
        self._conn = sqlite3.connect(db_path)
        self._conn.row_factory = sqlite3.Row
        self._create_tables()

    def _create_tables(self) -> None:
        self._conn.executescript("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY,
                started_at TEXT,
                ended_at TEXT,
                total_monitoring_seconds INTEGER
            );

            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY,
                session_id INTEGER REFERENCES sessions(id),
                start_time TEXT,
                end_time TEXT,
                duration_seconds REAL,
                peak_score REAL,
                clip_path TEXT,
                event_type TEXT
            );
        """)
        self._conn.commit()

    # ── Sessions ────────────────────────────────────────────────────────────

    def create_session(self) -> int:
        cur = self._conn.execute(
            "INSERT INTO sessions (started_at) VALUES (?)",
            (datetime.now().isoformat(),),
        )
        self._conn.commit()
        return cur.lastrowid

    def end_session(self, session_id: int, total_seconds: int) -> None:
        self._conn.execute(
            "UPDATE sessions SET ended_at = ?, total_monitoring_seconds = ? WHERE id = ?",
            (datetime.now().isoformat(), total_seconds, session_id),
        )
        self._conn.commit()

    # ── Events ──────────────────────────────────────────────────────────────

    def insert_event(
        self,
        session_id: int,
        start_time: str,
        end_time: str,
        duration_seconds: float,
        peak_score: float,
        clip_path: str,
        event_type: str | None = None,
    ) -> int:
        cur = self._conn.execute(
            """INSERT INTO events
               (session_id, start_time, end_time, duration_seconds,
                peak_score, clip_path, event_type)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (session_id, start_time, end_time, duration_seconds,
             peak_score, clip_path, event_type),
        )
        self._conn.commit()
        return cur.lastrowid

    def get_session_events(self, session_id: int) -> list[dict]:
        rows = self._conn.execute(
            "SELECT * FROM events WHERE session_id = ? ORDER BY start_time",
            (session_id,),
        ).fetchall()
        return [dict(row) for row in rows]

    def get_all_sessions(self) -> list[dict]:
        rows = self._conn.execute(
            "SELECT * FROM sessions ORDER BY started_at DESC"
        ).fetchall()
        return [dict(row) for row in rows]

    # ── Cleanup ─────────────────────────────────────────────────────────────

    def close(self) -> None:
        self._conn.close()
