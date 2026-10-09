"""New York session clock for the ICT strategies (port of CSessionClock from ICT Ultimate Pro).

Everything on the platform is in UTC, so there is no broker-server offset to measure: New York
time is UTC-5, or UTC-4 during US daylight saving (second Sunday of March 07:00 UTC to the first
Sunday of November 06:00 UTC). Standard library only, so it behaves the same on Windows
(where Python ships without the IANA time-zone database).

"NY ms" values are wall-clock New York times encoded like UTC epoch milliseconds; they are only
used to read the hour/minute/weekday, never compared with real timestamps.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from hedgefund.core.timeutil import DAY_MS, HOUR_MS, MINUTE_MS


def _utc_ms(y: int, m: int, d: int, h: int = 0) -> int:
    return int(datetime(y, m, d, h, tzinfo=timezone.utc).timestamp() * 1000)


def _dow(days: int) -> int:
    """Day of week of an epoch day number, 0 = Sunday (MQL5 convention)."""
    return (days + 4) % 7  # 1970-01-01 was a Thursday


def _nth_sunday(y: int, m: int, n: int) -> int:
    first = datetime(y, m, 1, tzinfo=timezone.utc)
    dow1 = _dow(int(first.timestamp() // 86400))
    return 1 + (7 - dow1) % 7 + 7 * (n - 1)


def _last_sunday(y: int, m: int) -> int:
    nxt = datetime(y + (m == 12), m % 12 + 1, 1, tzinfo=timezone.utc)
    last_day = int(nxt.timestamp() // 86400) - 1
    return datetime.fromtimestamp(last_day * 86400, tz=timezone.utc).day - _dow(last_day)


def _year(utc_ms: int) -> int:
    return datetime.fromtimestamp(utc_ms / 1000, tz=timezone.utc).year


def is_us_dst(utc_ms: int) -> bool:
    y = _year(utc_ms)
    return _utc_ms(y, 3, _nth_sunday(y, 3, 2), 7) <= utc_ms < _utc_ms(y, 11, _nth_sunday(y, 11, 1), 6)


def is_eu_dst(utc_ms: int) -> bool:
    y = _year(utc_ms)
    return _utc_ms(y, 3, _last_sunday(y, 3), 1) <= utc_ms < _utc_ms(y, 10, _last_sunday(y, 10), 1)


def utc_to_ny(utc_ms: int) -> int:
    return utc_ms - (4 if is_us_dst(utc_ms) else 5) * HOUR_MS


def ny_to_utc(ny_ms: int) -> int:
    guess = ny_ms + 5 * HOUR_MS
    return ny_ms + 4 * HOUR_MS if is_us_dst(guess) else guess


def ny_minute_of_day(utc_ms: int) -> int:
    return int(utc_to_ny(utc_ms) % DAY_MS // MINUTE_MS)


def ny_day_of_week(utc_ms: int) -> int:
    return _dow(int(utc_to_ny(utc_ms) // DAY_MS))


def ny_day_key(utc_ms: int) -> int:
    return int(utc_to_ny(utc_ms) // DAY_MS)


def ny_week_key(utc_ms: int) -> int:
    """Weeks start on Monday (as in the EA)."""
    return (ny_day_key(utc_ms) + 3) // 7


def ny_minute_to_utc(utc_ms: int, minute_of_day: int, day_offset: int = 0) -> int:
    """UTC instant of a New York wall-clock minute on the NY day of ``utc_ms`` (+ day_offset)."""
    day_start_ny = utc_to_ny(utc_ms) // DAY_MS * DAY_MS
    return ny_to_utc(day_start_ny + day_offset * DAY_MS + minute_of_day * MINUTE_MS)


def ny_range_to_utc(utc_ms: int, start_min: int, end_min: int) -> tuple[int, int]:
    return ny_minute_to_utc(utc_ms, start_min), ny_minute_to_utc(utc_ms, end_min)


def server_hour(utc_ms: int, winter_offset_h: int = 2, follows_eu_dst: bool = True) -> int:
    """Hour on a typical MT5 server clock (UTC+2 in winter, UTC+3 in EU summer): the v6 EA
    expressed its Silver Bullet windows in server hours."""
    off = winter_offset_h + (1 if follows_eu_dst and is_eu_dst(utc_ms) else 0)
    return int((utc_ms + off * HOUR_MS) % DAY_MS // HOUR_MS)


def server_day_of_week(utc_ms: int, winter_offset_h: int = 2, follows_eu_dst: bool = True) -> int:
    off = winter_offset_h + (1 if follows_eu_dst and is_eu_dst(utc_ms) else 0)
    return _dow(int((utc_ms + off * HOUR_MS) // DAY_MS))


def day_of_week_score(utc_ms: int) -> int:
    """Weekly profile: Tue/Wed/Thu +1, Monday 0, Friday -1, weekend -2."""
    d = ny_day_of_week(utc_ms)
    return 1 if d in (2, 3, 4) else 0 if d == 1 else -1 if d == 5 else -2


# ---- Silver Bullet windows (NY time) ----
WINDOWS = {"london": (180, 240, "Londres 03:00-04:00"), "ny_am": (600, 660, "NY AM 10:00-11:00"), "ny_pm": (840, 900, "NY PM 14:00-15:00")}


def window_at(utc_ms: int, enabled: set[str]) -> tuple[str, int, int] | None:
    """(name, start_utc, end_utc) of the Silver Bullet window active at utc_ms."""
    m = ny_minute_of_day(utc_ms)
    for name, (s, e, _) in WINDOWS.items():
        if name in enabled and s <= m < e:
            start, end = ny_range_to_utc(utc_ms, s, e)
            return name, start, end
    return None


# ---- ICT macros (NY time) ----
@dataclass(frozen=True)
class Macro:
    id: int
    start: int  # minute of the NY day
    end: int
    high_prob: bool
    name: str
    group: str  # london | ny_am | ny_pm (for the platform's on/off switches)


MACROS = (
    Macro(150, 110, 130, False, "01:50 manipulation", "london"),
    Macro(250, 170, 190, False, "02:50 power hour / expansion", "london"),
    Macro(320, 200, 220, True, "03:20 reversal / retracement", "london"),
    Macro(350, 230, 250, False, "03:50 continuation de 03:20", "london"),
    Macro(420, 260, 280, False, "04:20", "london"),
    Macro(650, 410, 430, False, "06:50 early NY", "ny_am"),
    Macro(750, 470, 490, False, "07:50 early NY", "ny_am"),
    Macro(820, 500, 520, True, "08:20 manipulation / spooling (MSS)", "ny_am"),
    Macro(850, 530, 550, False, "08:50 accumulation (low prob)", "ny_am"),
    Macro(920, 560, 580, True, "09:20 manipulation high prob", "ny_am"),
    Macro(950, 590, 610, False, "09:50 continuation de 09:20", "ny_am"),
    Macro(1020, 620, 640, True, "10:20 reversal / retracement high prob", "ny_am"),
    Macro(1050, 650, 670, False, "10:50 continuation de 10:20", "ny_am"),
    Macro(1120, 680, 700, False, "11:20 changement de tendance", "ny_am"),
    Macro(1150, 710, 730, False, "11:50 changement / continuation", "ny_am"),
    Macro(1220, 740, 760, False, "12:20 volatilite", "ny_pm"),
    Macro(1250, 770, 790, False, "12:50 pre-lunch", "ny_pm"),
    Macro(1320, 800, 820, True, "13:20 high prob + opening range PM", "ny_pm"),
    Macro(1350, 830, 850, False, "13:50", "ny_pm"),
    Macro(1420, 860, 880, False, "14:20 volatilite + livraison swing", "ny_pm"),
    Macro(1450, 890, 910, False, "14:50", "ny_pm"),
    Macro(1515, 915, 940, True, "15:15 spooling high prob", "ny_pm"),
    Macro(1550, 950, 970, True, "15:50 final hour high prob", "ny_pm"),
)
# The EA's default InpMBMacros list.
DEFAULT_MACROS = frozenset({320, 350, 820, 920, 950, 1020, 1050, 1120, 1320, 1420, 1515, 1550})


def macro_at(utc_ms: int) -> Macro | None:
    m = ny_minute_of_day(utc_ms)
    return next((x for x in MACROS if x.start <= m < x.end), None)


def macro_recent(utc_ms: int, grace_min: int) -> Macro | None:
    """Last macro that ended less than ``grace_min`` minutes ago."""
    m = ny_minute_of_day(utc_ms)
    return next((x for x in MACROS if x.end <= m < x.end + grace_min), None)


def macro_range_utc(utc_ms: int, macro: Macro) -> tuple[int, int]:
    return ny_range_to_utc(utc_ms, macro.start, macro.end)


def ny_label(utc_ms: int) -> str:
    return datetime.fromtimestamp(utc_to_ny(utc_ms) / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M NY")
