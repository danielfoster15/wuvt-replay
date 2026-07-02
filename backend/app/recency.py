"""Derive each DJ's most-recent set time so the DJ list can be sorted by it.

The DJ-list endpoints carry no timestamps, so we walk back over recent days of
``/playlists/date/{y}/{m}/{d}`` (one request per day). Past days are immutable and
cached aggressively, so after a warm-up only "today" is re-fetched.
"""
from __future__ import annotations

import asyncio
import os
from datetime import date, datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

import httpx

from . import wuvt
from .cache import TTL_ARCHIVE_META, TTL_SET_LIVE, cache

LOOKBACK_DAYS = int(os.environ.get("RECENCY_LOOKBACK_DAYS", "45"))
_CONCURRENCY = 6


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None


async def _day_latest(client: httpx.AsyncClient, day: date) -> dict[int, datetime]:
    """Map dj_id -> latest set start for a single day (cached)."""
    key = f"day:{day.isoformat()}"
    cached = cache.get(key)
    if cached is not None:
        return cached

    try:
        data = await wuvt.get_date(client, day.year, day.month, day.day)
    except (httpx.HTTPError, ValueError):
        # Never cache a failure: a past day caches for a month, so one transient
        # upstream error would otherwise masquerade as "no sets that day" and
        # poison DJ recency until the entry expires.
        return {}

    latest: dict[int, datetime] = {}
    for s in data.get("sets", []):
        dj = s.get("dj") or {}
        if not dj.get("visible", True):
            continue  # skip hidden DJs (e.g. Automation)
        dj_id = s.get("dj_id") or dj.get("id")
        dt = _parse_dt(s.get("dtstart"))
        if dj_id is None or dt is None:
            continue
        if dj_id not in latest or dt > latest[dj_id]:
            latest[dj_id] = dt

    # Today is still accumulating; earlier days never change.
    ttl = TTL_SET_LIVE if day >= datetime.now(timezone.utc).date() else TTL_ARCHIVE_META
    cache.set(key, latest, ttl)
    return latest


async def build_recency(
    client: httpx.AsyncClient, days: int = LOOKBACK_DAYS
) -> dict[int, datetime]:
    """Map dj_id -> most-recent set start across the last ``days`` days."""
    today = datetime.now(timezone.utc).date()
    wanted = [today - timedelta(days=i) for i in range(days)]

    sem = asyncio.Semaphore(_CONCURRENCY)

    async def guarded(d: date) -> dict[int, datetime]:
        async with sem:
            return await _day_latest(client, d)

    per_day = await asyncio.gather(*(guarded(d) for d in wanted))

    merged: dict[int, datetime] = {}
    for day_map in per_day:
        for dj_id, dt in day_map.items():
            if dj_id not in merged or dt > merged[dj_id]:
                merged[dj_id] = dt
    return merged
