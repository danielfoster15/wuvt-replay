from datetime import datetime, timezone

from app.archive import (
    ArchiveItem,
    hour_start_from_identifier,
    identifier_from_url,
    _parse_length,
)
from app.planner import build_segments


def _hour(h: int, duration: float = 3599.0) -> ArchiveItem:
    ident = f"WUVTFM_20260526_{h:02d}00Z"
    return ArchiveItem(
        identifier=ident,
        hour_start=datetime(2026, 5, 26, h, 0, 0, tzinfo=timezone.utc),
        mp3_url=f"https://archive.org/download/{ident}/file.mp3",
        duration_sec=duration,
    )


def test_identifier_parsing():
    url = "https://retrofling.apps.wuvt.vt.edu/WUVTFM_20260526_0400Z"
    assert identifier_from_url(url) == "WUVTFM_20260526_0400Z"
    assert hour_start_from_identifier("WUVTFM_20260526_0400Z") == datetime(
        2026, 5, 26, 4, 0, 0, tzinfo=timezone.utc
    )


def test_parse_length():
    assert _parse_length("59:59") == 3599.0
    assert _parse_length("1:00:00") == 3600.0
    assert _parse_length("12") == 12.0
    assert _parse_length(None) is None
    assert _parse_length("garbage") is None


def test_set_60624_spans_three_hours():
    # 210 Watts of DJ Taldin!, ran 04:12:18Z -> 06:02:07Z
    dtstart = datetime(2026, 5, 26, 4, 12, 18, tzinfo=timezone.utc)
    dtend = datetime(2026, 5, 26, 6, 2, 7, tzinfo=timezone.utc)
    items = [_hour(6), _hour(4), _hour(5)]  # deliberately out of order

    segs = build_segments(items, dtstart, dtend)

    assert len(segs) == 3
    # First hour: trimmed in, plays to natural end.
    assert segs[0].clip_start_ms == 738_000
    assert segs[0].clip_end_ms is None
    assert segs[0].duration_ms == 3_599_000 - 738_000  # to end of 59:59 file
    # Middle hour: full file.
    assert segs[1].clip_start_ms == 0
    assert segs[1].clip_end_ms is None
    assert segs[1].duration_ms == 3_599_000
    # Last hour: from the top, trimmed out at 02:07.
    assert segs[2].clip_start_ms == 0
    assert segs[2].clip_end_ms == 127_000
    assert segs[2].duration_ms == 127_000


def test_set_within_single_hour():
    dtstart = datetime(2026, 5, 26, 4, 10, 0, tzinfo=timezone.utc)
    dtend = datetime(2026, 5, 26, 4, 35, 30, tzinfo=timezone.utc)
    segs = build_segments([_hour(4)], dtstart, dtend)
    assert len(segs) == 1
    assert segs[0].clip_start_ms == 600_000
    assert segs[0].clip_end_ms == 2_130_000


def test_non_overlapping_hour_dropped():
    # Set is entirely within hour 5; an extra hour-7 file must be dropped.
    dtstart = datetime(2026, 5, 26, 5, 5, 0, tzinfo=timezone.utc)
    dtend = datetime(2026, 5, 26, 5, 45, 0, tzinfo=timezone.utc)
    segs = build_segments([_hour(5), _hour(7)], dtstart, dtend)
    assert len(segs) == 1
    assert segs[0].clip_start_ms == 300_000
    assert segs[0].clip_end_ms == 2_700_000
