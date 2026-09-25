from __future__ import annotations

from hedgefund.core.clock import Clock


class TokenBucket:
    """Venue request budget. ``acquire`` blocks (via the clock) until a token is free."""

    def __init__(self, rate_per_s: float, burst: int, clock: Clock):
        self.rate, self.burst, self.clock = rate_per_s, burst, clock
        self.tokens = float(burst)
        self.t = clock.now_ms()

    def _refill(self) -> None:
        now = self.clock.now_ms()
        self.tokens = min(self.burst, self.tokens + (now - self.t) / 1000.0 * self.rate)
        self.t = now

    def try_acquire(self) -> bool:
        self._refill()
        if self.tokens >= 1.0:
            self.tokens -= 1.0
            return True
        return False

    def acquire(self) -> None:
        while not self.try_acquire():
            self.clock.sleep(max((1.0 - self.tokens) / self.rate, 0.001))
