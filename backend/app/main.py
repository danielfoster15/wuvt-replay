"""FastAPI service: WUVT DJ sets as ready-to-play archive.org clip plans.

The phone talks only to this service for metadata; audio bytes stream straight
from archive.org. See README for the endpoint contract.
"""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from datetime import datetime
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
    Dj,
    DjDetail,
    DjList,
    SetDetail,
    SetSummary,
    Segment,
    TopArtist,
    TrackLog,
)
from .planner import build_segments

TOP_ARTISTS_LIMIT = 15


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


@app.get("/healthz")
async def healthz() -> dict[str, bool]:
    return {"ok": True}


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
