"""Tests for the /djs endpoint, with upstream WUVT calls stubbed out."""
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app import main
from app.cache import cache
from app.main import _is_placeholder_airname


def test_is_placeholder_airname():
    assert _is_placeholder_airname("ERROR: <SHOW NOT FOUND>")
    assert _is_placeholder_airname("error: upstream broke")
    assert _is_placeholder_airname("  ERROR: <SHOW NOT FOUND>  ")
    assert _is_placeholder_airname("")
    assert _is_placeholder_airname("   ")
    assert not _is_placeholder_airname("DJ Taldin")
    assert not _is_placeholder_airname("Erroneous Monk")


def test_djs_filters_error_placeholders(monkeypatch):
    raw_djs = [
        {"id": 1, "airname": "DJ Taldin", "visible": True},
        {"id": 2, "airname": "ERROR: <SHOW NOT FOUND>", "visible": True},
        {"id": 3, "airname": "   ", "visible": True},
        {"id": 4, "airname": "Hidden DJ", "visible": False},
    ]

    async def fake_get_djs(client):
        return raw_djs

    # Even with a recent set, the error placeholder must not appear.
    async def fake_build_recency(client):
        return {2: datetime(2026, 6, 9, 14, 0, tzinfo=timezone.utc)}

    monkeypatch.setattr(main.wuvt, "get_djs", fake_get_djs)
    monkeypatch.setattr(main, "build_recency", fake_build_recency)
    cache._data.clear()

    with TestClient(main.app) as client:
        resp = client.get("/djs")

    assert resp.status_code == 200
    names = [d["airname"] for d in resp.json()["djs"]]
    assert names == ["DJ Taldin"]
