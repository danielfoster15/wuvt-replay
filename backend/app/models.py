"""Response models for the backend's clean, phone-friendly contract."""
from __future__ import annotations

from pydantic import BaseModel


class Dj(BaseModel):
    id: int
    airname: str
    last_set: str | None = None  # ISO start of the DJ's most recent set, if known


class DjList(BaseModel):
    djs: list[Dj]


class SetSummary(BaseModel):
    id: int
    dtstart: str | None
    dtend: str | None
    duration_sec: int | None


class TopArtist(BaseModel):
    name: str
    count: int


class DjDetail(BaseModel):
    dj: Dj
    sets: list[SetSummary]
    top_artists: list[TopArtist]


class Segment(BaseModel):
    url: str
    clip_start_ms: int
    clip_end_ms: int | None  # null => play to natural end of file
    duration_ms: int  # playable length of this segment (for whole-set progress)


class TrackLog(BaseModel):
    offset_ms: int | None  # ms from set start; null if played time missing
    played: str | None
    artist: str
    title: str
    album: str
    is_new: bool
    is_request: bool
    is_vinyl: bool


class SetDetail(BaseModel):
    id: int
    dj: str
    dtstart: str | None
    dtend: str | None
    available: bool  # false => no archives yet (set not ended/uploaded)
    segments: list[Segment]
    tracks: list[TrackLog]


class BackendHealth(BaseModel):
    ok: bool
    version: str
    uptime_sec: int


class NextcloudHealth(BaseModel):
    ok: bool
    version: str | None = None
    maintenance: bool | None = None
    error: str | None = None


class StorageHealth(BaseModel):
    ok: bool
    free_gb: float | None = None
    total_gb: float | None = None
    error: str | None = None


class Health(BaseModel):
    ok: bool  # all components ok
    checked_at: str
    backend: BackendHealth
    nextcloud: NextcloudHealth
    storage: StorageHealth
