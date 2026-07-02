"""Resolve a WUVT aircheck link to a directly-streamable archive.org MP3.

The WUVT API hands back ``retrofling`` URLs whose last path segment is the
archive.org identifier, e.g.::

    https://retrofling.apps.wuvt.vt.edu/WUVTFM_20260526_0400Z
                                        ^^^^^^^^^^^^^^^^^^^^^^^ identifier

We look up the item's metadata to find its VBR MP3 file and length, and build a
download URL that supports HTTP range requests (so the player can seek/clip).
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from urllib.parse import quote

import httpx

from .cache import TTL_ARCHIVE_META, cache

logger = logging.getLogger("wuvt_replay.archive")

_IDENT_RE = re.compile(r"WUVTFM_(\d{8})_(\d{4})Z", re.IGNORECASE)
_ARCHIVE_META = "https://archive.org/metadata/{ident}"
_ARCHIVE_DOWNLOAD = "https://archive.org/download/{ident}/{name}"

_HEADERS = {"User-Agent": "wuvt-replay/0.1 (personal archive player)"}


class ArchiveItem:
    """A resolved archive.org aircheck: its hour, MP3 URL, and duration."""

    def __init__(self, identifier: str, hour_start: datetime, mp3_url: str, duration_sec: float):
        self.identifier = identifier
        self.hour_start = hour_start
        self.mp3_url = mp3_url
        self.duration_sec = duration_sec


def identifier_from_url(url: str) -> str | None:
    """Extract the archive.org identifier from a retrofling/details URL."""
    m = _IDENT_RE.search(url)
    return m.group(0) if m else None


def hour_start_from_identifier(identifier: str) -> datetime:
    """Parse the broadcast hour (UTC) encoded in the identifier."""
    m = _IDENT_RE.search(identifier)
    if not m:
        raise ValueError(f"not a WUVT aircheck identifier: {identifier!r}")
    date_part, time_part = m.group(1), m.group(2)
    dt = datetime.strptime(date_part + time_part, "%Y%m%d%H%M")
    return dt.replace(tzinfo=timezone.utc)


def _parse_length(value: str | None) -> float | None:
    """Parse an archive.org length field (``SS(.s)``, ``MM:SS``, ``H:MM:SS``)."""
    if not value:
        return None
    parts = value.split(":")
    try:
        nums = [float(p) for p in parts]
    except ValueError:
        return None
    seconds = 0.0
    for n in nums:
        seconds = seconds * 60 + n
    return seconds


async def resolve(client: httpx.AsyncClient, url: str) -> ArchiveItem | None:
    """Resolve a retrofling/aircheck URL to an ArchiveItem, or None if not found."""
    identifier = identifier_from_url(url)
    if identifier is None:
        return None

    async def fetch() -> dict | None:
        try:
            r = await client.get(
                _ARCHIVE_META.format(ident=identifier), headers=_HEADERS, timeout=25.0
            )
            r.raise_for_status()
        except httpx.HTTPError as exc:
            # Re-raise (preserving current behavior); just leave a trace first.
            logger.warning("archive.org metadata fetch failed for %s: %s", identifier, exc)
            raise
        data = r.json()
        files = data.get("files") or []
        if not files:
            logger.info("archive item %s not yet derived (no files)", identifier)
            return None  # not yet derived/available — don't cache as permanent
        # Prefer the VBR MP3 derivative; fall back to any .mp3.
        mp3 = next((f for f in files if f.get("format") == "VBR MP3"), None)
        if mp3 is None:
            mp3 = next(
                (f for f in files if str(f.get("name", "")).lower().endswith(".mp3")),
                None,
            )
        if mp3 is None:
            logger.warning("archive item %s has files but no MP3 derivative", identifier)
            return None
        return {
            "name": mp3["name"],
            "duration": _parse_length(mp3.get("length")),
        }

    cache_key = f"archive_meta:{identifier}"
    resolved = cache.get(cache_key)
    if resolved is None:
        resolved = await fetch()
        if resolved is not None:
            cache.set(cache_key, resolved, TTL_ARCHIVE_META)
    if resolved is None:
        return None

    mp3_url = _ARCHIVE_DOWNLOAD.format(
        ident=identifier, name=quote(resolved["name"])
    )
    duration = resolved["duration"] or 3600.0
    return ArchiveItem(
        identifier=identifier,
        hour_start=hour_start_from_identifier(identifier),
        mp3_url=mp3_url,
        duration_sec=duration,
    )
