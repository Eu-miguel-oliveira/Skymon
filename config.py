"""Configuração central do SkyMon, lida de variáveis de ambiente ou .env."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _load_dotenv() -> None:
    """Carregador pequeno para não exigir dependência extra no Raspberry."""
    env_file = Path(".env")
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


_load_dotenv()


@dataclass(frozen=True)
class Settings:
    center_lat: float = float(os.getenv("CENTER_LAT", "-23.0074"))
    center_lon: float = float(os.getenv("CENTER_LON", "-47.1345"))
    default_radius_km: int = int(os.getenv("DEFAULT_RADIUS_KM", "200"))
    poll_interval_seconds: int = max(5, int(os.getenv("POLL_INTERVAL_SECONDS", "10")))
    history_interval_seconds: int = max(10, int(os.getenv("HISTORY_INTERVAL_SECONDS", "60")))
    database_path: str = os.getenv("DATABASE_PATH", "data/skymon.db")
    opensky_client_id: str = os.getenv("OPENSKY_CLIENT_ID", "")
    opensky_client_secret: str = os.getenv("OPENSKY_CLIENT_SECRET", "")


settings = Settings()
