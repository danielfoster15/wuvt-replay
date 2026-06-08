"""A tiny in-memory TTL cache.

Single-process only — fine for a personal-scale service. Values are stored with
an absolute expiry; lookups past expiry behave as a miss.
"""
from __future__ import annotations

import threading
import time
from typing import Any, Awaitable, Callable, TypeVar

T = TypeVar("T")


class TTLCache:
    def __init__(self) -> None:
        self._data: dict[str, tuple[float, Any]] = {}
        self._lock = threading.Lock()

    def get(self, key: str) -> Any | None:
        with self._lock:
            entry = self._data.get(key)
            if entry is None:
                return None
            expires_at, value = entry
            if expires_at < time.monotonic():
                self._data.pop(key, None)
                return None
            return value

    def set(self, key: str, value: Any, ttl: float) -> None:
        with self._lock:
            self._data[key] = (time.monotonic() + ttl, value)

    async def get_or_set(
        self, key: str, ttl: float, factory: Callable[[], Awaitable[T]]
    ) -> T:
        cached = self.get(key)
        if cached is not None:
            return cached
        value = await factory()
        self.set(key, value, ttl)
        return value


cache = TTLCache()

# TTLs (seconds)
TTL_DJS = 300            # DJ list changes rarely
TTL_DJ_DETAIL = 300      # a DJ's sets list
TTL_ARCHIVE_META = 30 * 24 * 3600  # archive.org items are immutable once uploaded
TTL_SET_FINISHED = 30 * 24 * 3600  # a finished set's tracks/archives don't change
TTL_SET_LIVE = 15        # an in-progress set is still accumulating tracks
