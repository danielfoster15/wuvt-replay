"""FastAPI service: WUVT DJ sets as ready-to-play archive.org clip plans.

The phone talks only to this service for metadata; audio bytes stream straight
from archive.org. See README for the endpoint contract.
"""
from __future__ import annotations

import asyncio
import logging
import os
import shutil
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from . import archive, wuvt
from .recency import build_recency
from .cache import (
    TTL_DJ_DETAIL,
    TTL_DJS,
    TTL_SET_FINISHED,
    TTL_SET_LIVE,
    cache,
)
from .models import (
    BackendHealth,
    Dj,
    DjDetail,
    DjList,
    Health,
    NextcloudHealth,
    SetDetail,
    SetSummary,
    Segment,
    StorageHealth,
    TopArtist,
    TrackLog,
)
from .planner import build_segments

TOP_ARTISTS_LIMIT = 15

# Health-check targets; see docker-compose.yml for the values used on the Pi.
NEXTCLOUD_STATUS_URL = os.environ.get("NEXTCLOUD_STATUS_URL", "")
EXPANSION_PATH = os.environ.get("EXPANSION_PATH", "")

_started_at = time.monotonic()

# App logging, emitted to stderr alongside uvicorn's own logs. Self-contained
# so it behaves whether launched by uvicorn or imported under pytest. Child
# loggers (e.g. "wuvt_replay.archive") propagate up to this handler.
logger = logging.getLogger("wuvt_replay")
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(levelname)s:     [%(name)s] %(message)s"))
    logger.addHandler(_handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.client = httpx.AsyncClient(follow_redirects=True)
    try:
        yield
    finally:
        await app.state.client.aclose()


app = FastAPI(title="wuvt-replay", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None


def _iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt is not None else None


def _is_placeholder_airname(airname: str) -> bool:
    """Upstream schedule errors leak into the DJ list as fake entries,
    e.g. "ERROR: <SHOW NOT FOUND>"."""
    name = airname.strip()
    return not name or name.upper().startswith("ERROR:")


@app.get("/healthz")
async def healthz() -> dict[str, bool]:
    return {"ok": True}


async def _check_nextcloud(client: httpx.AsyncClient) -> NextcloudHealth:
    if not NEXTCLOUD_STATUS_URL:
        return NextcloudHealth(ok=False, error="not configured")
    try:
        r = await client.get(NEXTCLOUD_STATUS_URL, timeout=5.0)
        r.raise_for_status()
        data = r.json()
    except Exception as exc:  # report any failure as unhealthy, never 500
        return NextcloudHealth(ok=False, error=str(exc) or type(exc).__name__)
    maintenance = bool(data.get("maintenance"))
    return NextcloudHealth(
        ok=bool(data.get("installed")) and not maintenance,
        version=data.get("versionstring"),
        maintenance=maintenance,
    )


def _check_storage() -> StorageHealth:
    if not EXPANSION_PATH:
        return StorageHealth(ok=False, error="not configured")
    try:
        # A dropped USB drive leaves an empty directory behind the bind mount,
        # and disk_usage would then report the SD card — so check emptiness first.
        if not any(os.scandir(EXPANSION_PATH)):
            return StorageHealth(ok=False, error="drive not mounted")
        usage = shutil.disk_usage(EXPANSION_PATH)
    except OSError as exc:
        return StorageHealth(ok=False, error=str(exc))
    gb = 1024**3
    return StorageHealth(
        ok=True,
        free_gb=round(usage.free / gb, 1),
        total_gb=round(usage.total / gb, 1),
    )


@app.get("/health", response_model=Health)
async def health() -> Health:
    nextcloud = await _check_nextcloud(app.state.client)
    storage = _check_storage()
    backend = BackendHealth(
        ok=True,
        version=app.version,
        uptime_sec=int(time.monotonic() - _started_at),
    )
    return Health(
        ok=backend.ok and nextcloud.ok and storage.ok,
        checked_at=datetime.now(timezone.utc).isoformat(),
        backend=backend,
        nextcloud=nextcloud,
        storage=storage,
    )


@app.get("/djs", response_model=DjList)
async def list_djs() -> DjList:
    async def fetch() -> DjList:
        raw, recency = await asyncio.gather(
            wuvt.get_djs(app.state.client),
            build_recency(app.state.client),
        )
        djs = [
            Dj(
                id=d["id"],
                airname=d["airname"],
                last_set=_iso(recency.get(d["id"])),
            )
            for d in raw
            if d.get("visible", True)
            and not _is_placeholder_airname(d.get("airname") or "")
        ]
        # DJs with a recent set first (newest first); the rest alphabetical.
        recent = [d for d in djs if d.last_set]
        rest = [d for d in djs if not d.last_set]
        recent.sort(key=lambda d: d.last_set, reverse=True)
        rest.sort(key=lambda d: d.airname.lower())
        return DjList(djs=recent + rest)

    return await cache.get_or_set("djs", TTL_DJS, fetch)


@app.get("/djs/{dj_id}", response_model=DjDetail)
async def dj_detail(dj_id: int) -> DjDetail:
    async def fetch() -> DjDetail:
        try:
            sets_data, artists = await asyncio.gather(
                wuvt.get_dj_sets(app.state.client, dj_id),
                wuvt.get_dj_artists(app.state.client, dj_id),
            )
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 404:
                raise HTTPException(status_code=404, detail="DJ not found")
            logger.error("WUVT upstream error fetching dj %s: %s", dj_id, exc)
            raise

        dj_raw = sets_data.get("dj", {})
        summaries: list[SetSummary] = []
        for s in sets_data.get("sets", []):
            start = _parse_dt(s.get("dtstart"))
            end = _parse_dt(s.get("dtend"))
            duration = (
                int((end - start).total_seconds())
                if start and end and end > start
                else None
            )
            summaries.append(
                SetSummary(
                    id=s["id"],
                    dtstart=_iso(start),
                    dtend=_iso(end),
                    duration_sec=duration,
                )
            )
        # Newest first (API is usually already sorted, but be explicit).
        summaries.sort(key=lambda s: s.dtstart or "", reverse=True)

        top = [
            TopArtist(name=row[0], count=int(row[1]))
            for row in artists[:TOP_ARTISTS_LIMIT]
            if row and row[0]
        ]
        return DjDetail(
            dj=Dj(id=dj_raw.get("id", dj_id), airname=dj_raw.get("airname", "")),
            sets=summaries,
            top_artists=top,
        )

    return await cache.get_or_set(f"dj:{dj_id}", TTL_DJ_DETAIL, fetch)


@app.get("/sets/{set_id}", response_model=SetDetail)
async def set_detail(set_id: int) -> SetDetail:
    cache_key = f"set:{set_id}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        data = await wuvt.get_set(app.state.client, set_id)
    except httpx.HTTPStatusError as exc:
        if exc.response.status_code == 404:
            raise HTTPException(status_code=404, detail="Set not found")
        logger.error("WUVT upstream error fetching set %s: %s", set_id, exc)
        raise

    dtstart = _parse_dt(data.get("dtstart"))
    dtend = _parse_dt(data.get("dtend"))

    # Resolve archive hours -> streamable MP3s (concurrently).
    archive_urls = data.get("archives") or []
    resolved = await asyncio.gather(
        *(archive.resolve(app.state.client, u) for u in archive_urls)
    )
    items = [it for it in resolved if it is not None]

    segments: list[Segment] = []
    if items and dtstart and dtend and dtend > dtstart:
        segments = build_segments(items, dtstart, dtend)

    tracks: list[TrackLog] = []
    for t in data.get("tracks", []):
        played = _parse_dt(t.get("played"))
        offset = (
            int((played - dtstart).total_seconds() * 1000)
            if played and dtstart
            else None
        )
        track = t.get("track", {})
        tracks.append(
            TrackLog(
                offset_ms=offset,
                played=_iso(played),
                artist=track.get("artist", ""),
                title=track.get("title", ""),
                album=track.get("album", ""),
                is_new=bool(t.get("new")),
                is_request=bool(t.get("request")),
                is_vinyl=bool(t.get("vinyl")),
            )
        )

    detail = SetDetail(
        id=set_id,
        dj=data.get("dj", {}).get("airname", "") if isinstance(data.get("dj"), dict) else "",
        dtstart=_iso(dtstart),
        dtend=_iso(dtend),
        available=bool(segments),
        segments=segments,
        tracks=tracks,
    )

    # Finished sets are immutable; live sets keep accumulating tracks.
    ttl = TTL_SET_FINISHED if dtend is not None else TTL_SET_LIVE
    cache.set(cache_key, detail, ttl)
    return detail
