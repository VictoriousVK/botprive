"""Clocks. Components never call time.time() directly so backtests are deterministic."""

from __future__ import annotations

import time
from typing import Protocol


class Clock(Protocol):
    def now_ms(self) -> int: ...

    def sleep(self, seconds: float) -> None: ...


class SystemClock:
    def now_ms(self) -> int:
        return int(time.time() * 1000)

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


class SimClock:
    def __init__(self, start_ms: int = 0):
        self._t = start_ms

    def now_ms(self) -> int:
        return self._t

    def set(self, t_ms: int) -> None:
        self._t = t_ms

    def advance(self, ms: int) -> None:
        self._t += ms

    def sleep(self, seconds: float) -> None:
        self._t += int(seconds * 1000)
