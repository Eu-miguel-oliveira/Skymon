"""Cliente assíncrono para estados de voo do OpenSky."""
from __future__ import annotations

import math
import time
from typing import Any

import httpx

from config import Settings

API_URL = "https://opensky-network.org/api/states/all"
TOKEN_URL = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
METERS_TO_FEET = 3.28084
MPS_TO_KNOTS = 1.94384


class OpenSkyClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.http = httpx.AsyncClient(timeout=20.0, headers={"User-Agent": "SkyMon/1.0"})
        self._token: str | None = None
        self._token_expires_at = 0.0
        self.last_rate_limit: str | None = None

    async def close(self) -> None:
        await self.http.aclose()

    async def _headers(self) -> dict[str, str]:
        if not (self.settings.opensky_client_id and self.settings.opensky_client_secret):
            return {}
        if time.monotonic() >= self._token_expires_at:
            response = await self.http.post(TOKEN_URL, data={
                "grant_type": "client_credentials",
                "client_id": self.settings.opensky_client_id,
                "client_secret": self.settings.opensky_client_secret,
            })
            response.raise_for_status()
            token = response.json()
            self._token = token["access_token"]
            self._token_expires_at = time.monotonic() + max(30, token.get("expires_in", 1800) - 60)
        return {"Authorization": f"Bearer {self._token}"}

    @staticmethod
    def bounding_box(lat: float, lon: float, radius_km: float) -> dict[str, float]:
        # Conversão suficiente para a área local e mantém a requisição barata.
        lat_delta = radius_km / 111.32
        lon_delta = radius_km / (111.32 * max(0.1, math.cos(math.radians(lat))))
        return {"lamin": lat - lat_delta, "lamax": lat + lat_delta, "lomin": lon - lon_delta, "lomax": lon + lon_delta}

    async def fetch_states(self) -> tuple[list[dict[str, Any]], int | None]:
        params = self.bounding_box(self.settings.center_lat, self.settings.center_lon, self.settings.default_radius_km)
        response = await self.http.get(API_URL, params=params, headers=await self._headers())
        self.last_rate_limit = response.headers.get("X-Rate-Limit-Remaining")
        response.raise_for_status()
        payload = response.json()
        aircraft = [self._normalize(state) for state in (payload.get("states") or [])]
        return [item for item in aircraft if item is not None], payload.get("time")

    @staticmethod
    def _normalize(state: list[Any]) -> dict[str, Any] | None:
        # Esquema oficial: https://openskynetwork.github.io/opensky-api/rest.html
        if len(state) < 17 or state[5] is None or state[6] is None:
            return None
        altitude_m = state[7] if state[7] is not None else state[13]
        return {
            "icao24": state[0], "callsign": (state[1] or "").strip() or state[0].upper(),
            "country": state[2], "last_contact": state[4], "longitude": state[5], "latitude": state[6],
            "altitude_ft": round(altitude_m * METERS_TO_FEET) if altitude_m is not None else None,
            "on_ground": bool(state[8]), "velocity_kt": round(state[9] * MPS_TO_KNOTS) if state[9] is not None else None,
            "track": round(state[10]) if state[10] is not None else None,
            "vertical_rate_fpm": round(state[11] * METERS_TO_FEET * 60) if state[11] is not None else None,
            "squawk": state[14], "position_source": state[16],
        }
