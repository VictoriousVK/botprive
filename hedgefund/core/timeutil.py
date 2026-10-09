from __future__ import annotations

import time
from datetime import datetime, timezone

MINUTE_MS = 60_000
HOUR_MS = 60 * MINUTE_MS
DAY_MS = 24 * HOUR_MS
YEAR_DAYS = 365

INTERVAL_MS = {
    "1m": MINUTE_MS,
    "5m": 5 * MINUTE_MS,
    "15m": 15 * MINUTE_MS,
    "1h": HOUR_MS,
    "4h": 4 * HOUR_MS,
    "1d": DAY_MS,
}


def interval_ms(interval: str) -> int:
    try:
        return INTERVAL_MS[interval]
    except KeyError:
        raise ValueError(f"unsupported interval {interval!r}; use one of {sorted(INTERVAL_MS)}") from None


def bars_per_day(interval: str) -> int:
    return DAY_MS // interval_ms(interval)


def bars_per_year(interval: str) -> float:
    return YEAR_DAYS * DAY_MS / interval_ms(interval)


def now_ms() -> int:
    return int(time.time() * 1000)


def utc_iso(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def utc_date(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d")


def utc_day(ms: int) -> int:
    return ms // DAY_MS
