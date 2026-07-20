"""Persistência local leve para consultas e futuras estatísticas."""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


class Database:
    def __init__(self, path: str) -> None:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path, check_same_thread=False)
        self.connection.row_factory = sqlite3.Row

    def initialize(self) -> None:
        self.connection.execute("""
            CREATE TABLE IF NOT EXISTS aircraft_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                captured_at TEXT NOT NULL,
                aircraft_count INTEGER NOT NULL,
                payload TEXT NOT NULL
            )
        """)
        self.connection.execute("CREATE INDEX IF NOT EXISTS idx_snapshots_time ON aircraft_snapshots(captured_at)")
        self.connection.commit()

    def save_snapshot(self, aircraft: Iterable[dict]) -> None:
        rows = list(aircraft)
        self.connection.execute(
            "INSERT INTO aircraft_snapshots(captured_at, aircraft_count, payload) VALUES (?, ?, ?)",
            (datetime.now(timezone.utc).isoformat(), len(rows), json.dumps(rows, separators=(",", ":"))),
        )
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()
