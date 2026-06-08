"""Compute the clip plan that turns hour-long airchecks into exactly one DJ set.

Given a set's wall-clock start/end and the archive hours that overlap it, produce
ordered segments with per-file trim offsets so playback begins when the DJ
started and ends when they ended — no leftover minutes of the adjacent show.
"""
from __future__ import annotations

from datetime import datetime

from .archive import ArchiveItem
from .models import Segment

# Tolerance (s) for treating a clip end as "the whole rest of the file".
_END_EPS = 0.5


def build_segments(
    items: list[ArchiveItem], dtstart: datetime, dtend: datetime
) -> list[Segment]:
    """Build ordered, trimmed segments covering [dtstart, dtend].

    ``items`` are resolved archive hours (any order). Each segment that overlaps
    the set is clipped to the set's bounds; non-overlapping hours are dropped.
    """
    segments: list[Segment] = []
    for item in sorted(items, key=lambda i: i.hour_start):
        dur = item.duration_sec
        start_in = (dtstart - item.hour_start).total_seconds()
        end_in = (dtend - item.hour_start).total_seconds()

        clip_start = _clamp(start_in, 0.0, dur)
        clip_end = _clamp(end_in, 0.0, dur)

        if clip_end - clip_start <= 0:
            continue  # this hour doesn't actually contain any of the set

        clip_end_ms: int | None
        if clip_end >= dur - _END_EPS:
            clip_end_ms = None  # play to the natural end of the file
        else:
            clip_end_ms = round(clip_end * 1000)

        segments.append(
            Segment(
                url=item.mp3_url,
                clip_start_ms=round(clip_start * 1000),
                clip_end_ms=clip_end_ms,
                duration_ms=round((clip_end - clip_start) * 1000),
            )
        )
    return segments


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(value, high))
