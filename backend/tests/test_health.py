"""Tests for the /health endpoint and its component checks."""
import asyncio

import httpx
from fastapi.testclient import TestClient

from app import main
from app.main import _check_storage
from app.models import NextcloudHealth, StorageHealth


def test_storage_not_configured(monkeypatch):
    monkeypatch.setattr(main, "EXPANSION_PATH", "")
    result = _check_storage()
    assert not result.ok
    assert result.error == "not configured"


def test_storage_empty_dir_means_unmounted(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "EXPANSION_PATH", str(tmp_path))
    result = _check_storage()
    assert not result.ok
    assert result.error == "drive not mounted"


def test_storage_mounted_reports_space(tmp_path, monkeypatch):
    (tmp_path / "some_file").write_text("data")
    monkeypatch.setattr(main, "EXPANSION_PATH", str(tmp_path))
    result = _check_storage()
    assert result.ok
    assert result.free_gb is not None and result.free_gb > 0
    assert result.total_gb is not None and result.total_gb >= result.free_gb


def test_storage_missing_path(monkeypatch):
    monkeypatch.setattr(main, "EXPANSION_PATH", "/does/not/exist")
    result = _check_storage()
    assert not result.ok
    assert result.error


def test_health_endpoint_aggregates(monkeypatch, tmp_path):
    (tmp_path / "some_file").write_text("data")
    monkeypatch.setattr(main, "EXPANSION_PATH", str(tmp_path))

    async def fake_check_nextcloud(client):
        return NextcloudHealth(ok=True, version="33.0.5", maintenance=False)

    monkeypatch.setattr(main, "_check_nextcloud", fake_check_nextcloud)

    with TestClient(main.app) as client:
        resp = client.get("/health")

    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert body["backend"]["ok"] is True
    assert body["backend"]["uptime_sec"] >= 0
    assert body["nextcloud"]["version"] == "33.0.5"
    assert body["storage"]["ok"] is True


def test_health_endpoint_unhealthy_nextcloud(monkeypatch, tmp_path):
    (tmp_path / "some_file").write_text("data")
    monkeypatch.setattr(main, "EXPANSION_PATH", str(tmp_path))

    async def fake_check_nextcloud(client):
        return NextcloudHealth(ok=False, error="connection refused")

    monkeypatch.setattr(main, "_check_nextcloud", fake_check_nextcloud)

    with TestClient(main.app) as client:
        resp = client.get("/health")

    body = resp.json()
    assert body["ok"] is False
    assert body["nextcloud"]["error"] == "connection refused"
    assert body["storage"]["ok"] is True


def test_check_nextcloud_maintenance_mode(monkeypatch):
    monkeypatch.setattr(main, "NEXTCLOUD_STATUS_URL", "http://example/status.php")

    def fake_handler(request):
        return httpx.Response(
            200, json={"installed": True, "maintenance": True, "versionstring": "33.0.5"}
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(fake_handler))
    result = asyncio.run(main._check_nextcloud(client))
    assert isinstance(result, NextcloudHealth)
    assert not result.ok
    assert result.maintenance is True
