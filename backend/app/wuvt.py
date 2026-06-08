"""Thin async client for the public WUVT playlists API.

All endpoints return JSON when asked with an Accept: application/json header.
"""
from __future__ import annotations

import os
from typing import Any

import httpx

WUVT_BASE = os.environ.get("WUVT_BASE", "https://www.wuvt.vt.edu").rstrip("/")

_HEADERS = {
    "Accept": "application/json",
    "User-Agent": "wuvt-replay/0.1 (personal archive player)",
}


async def _get(client: httpx.AsyncClient, path: str) -> Any:
    r = await client.get(f"{WUVT_BASE}{path}", headers=_HEADERS, timeout=20.0)
    r.raise_for_status()
    return r.json()


async def get_djs(client: httpx.AsyncClient) -> list[dict[str, Any]]:
    """All DJs. Returns list of {airname, id, visible}."""
    data = await _get(client, "/playlists/dj")
    return data.get("djs", [])


async def get_dj_sets(client: httpx.AsyncClient, dj_id: int) -> dict[str, Any]:
    """A DJ and their sets: {dj: {...}, sets: [{id, dtstart, dtend, ...}]}."""
    return await _get(client, f"/playlists/dj/{dj_id}")


async def get_dj_artists(client: httpx.AsyncClient, dj_id: int) -> list[list[Any]]:
    """A DJ's most-played artists: list of [artist, count, rank]."""
    data = await _get(client, f"/playlists/charts/dj/{dj_id}/artists")
    return data.get("results", [])


async def get_set(client: httpx.AsyncClient, set_id: int) -> dict[str, Any]:
    """A single set: {dtstart, dtend, archives: [url, ...], tracks: [...], ...}.

    Note: requested as JSON, `archives` is a list of bare retrofling URLs.
    """
    return await _get(client, f"/playlists/set/{set_id}")


async def get_date(
    client: httpx.AsyncClient, year: int, month: int, day: int
) -> dict[str, Any]:
    """Sets aired on a given (GMT) day: {sets: [{dj, dj_id, dtstart, dtend, id}]}."""
    return await _get(client, f"/playlists/date/{year}/{month}/{day}")
