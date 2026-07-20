from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.requests import Request

from config import settings
from database import Database
from opensky import OpenSkyClient
from websocket import ConnectionManager

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("skymon")
BASE_DIR = Path(__file__).parent


async def collector(app: FastAPI) -> None:
    while True:
        try:
            aircraft, source_time = await app.state.opensky.fetch_states()
            snapshot = {
                "type": "aircraft_update", "aircraft": aircraft, "source_time": source_time,
                "updated_at": datetime.now(timezone.utc).isoformat(),
                "rate_limit_remaining": app.state.opensky.last_rate_limit,
            }
            app.state.snapshot = snapshot
            # O display atualiza a cada coleta; o histórico é amostrado para
            # manter o banco pequeno em um cartão SD do Raspberry.
            if asyncio.get_running_loop().time() >= app.state.next_history_save:
                app.state.database.save_snapshot(aircraft)
                app.state.next_history_save = asyncio.get_running_loop().time() + settings.history_interval_seconds
            await app.state.connections.broadcast(snapshot)
            logger.info("Snapshot recebido: %d aeronaves", len(aircraft))
        except Exception as exc:
            logger.warning("Falha ao consultar OpenSky: %s", exc)
            await app.state.connections.broadcast({"type": "status", "level": "warning", "message": "Não foi possível atualizar o OpenSky; exibindo o último mapa."})
        await asyncio.sleep(settings.poll_interval_seconds)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.connections = ConnectionManager()
    app.state.database = Database(settings.database_path)
    app.state.database.initialize()
    app.state.opensky = OpenSkyClient(settings)
    app.state.snapshot = None
    app.state.next_history_save = 0.0
    task = asyncio.create_task(collector(app))
    yield
    task.cancel()
    with suppress(asyncio.CancelledError):
        await task
    await app.state.opensky.close()
    app.state.database.close()


app = FastAPI(title="SkyMon", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=BASE_DIR / "templates")


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html", {"center_lat": settings.center_lat, "center_lon": settings.center_lon, "radius": settings.default_radius_km})


@app.get("/api/status")
async def status():
    return {"snapshot": app.state.snapshot, "center": {"lat": settings.center_lat, "lon": settings.center_lon}, "interval_seconds": settings.poll_interval_seconds}


@app.websocket("/ws")
async def live_updates(websocket: WebSocket):
    manager: ConnectionManager = app.state.connections
    await manager.connect(websocket)
    try:
        if app.state.snapshot:
            await websocket.send_json(app.state.snapshot)
        while True:
            await websocket.receive_text()  # mantém conexão e detecta desconexão
    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(websocket)
