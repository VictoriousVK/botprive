"""Thread-safe wrapper around the official ``MetaTrader5`` Python package.

The package only works on Windows, talking to a MetaTrader 5 terminal running on the same
machine. It is not thread-safe, so every call goes through one re-entrant lock. The module
can be injected (tests use a fake) and is imported lazily so the rest of the platform runs
anywhere.
"""

from __future__ import annotations

import os
import threading
from typing import Any


class MT5Unavailable(RuntimeError):
    pass


TRADE_MODES = {0: "demo", 1: "contest", 2: "real"}
MARGIN_MODES = {0: "netting", 1: "exchange", 2: "hedging"}


class MT5Client:
    def __init__(self, module: Any = None, path: str | None = None, login: int | None = None, password: str | None = None, server: str | None = None, timeout_ms: int = 10_000):
        self._mt5 = module
        self._lock = threading.RLock()
        self.path, self.login, self.password, self.server, self.timeout_ms = path, login, password, server, timeout_ms
        self.connected = False
        self.last_error = ""

    @classmethod
    def from_env(cls, module: Any = None) -> "MT5Client":
        login = os.environ.get("MT5_LOGIN")
        return cls(
            module=module,
            path=os.environ.get("MT5_PATH") or None,
            login=int(login) if login else None,
            password=os.environ.get("MT5_PASSWORD") or None,
            server=os.environ.get("MT5_SERVER") or None,
        )

    @property
    def mt5(self) -> Any:
        if self._mt5 is None:
            try:
                import MetaTrader5 as mt5  # type: ignore[import-not-found]
            except ImportError as e:
                raise MT5Unavailable("MetaTrader5 package not installed (pip install MetaTrader5; Windows only)") from e
            self._mt5 = mt5
        return self._mt5

    def const(self, name: str, default: int) -> int:
        return getattr(self.mt5, name, default)

    def connect(self) -> bool:
        with self._lock:
            kwargs: dict[str, Any] = {"timeout": self.timeout_ms}
            if self.path:
                kwargs["path"] = self.path
            if self.login:
                kwargs.update(login=self.login, password=self.password or "", server=self.server or "")
            try:
                ok = bool(self.mt5.initialize(**kwargs))
            except MT5Unavailable as e:
                self.connected, self.last_error = False, str(e)
                return False
            self.connected = ok
            self.last_error = "" if ok else f"initialize failed: {self.mt5.last_error()}"
            return ok

    def ensure(self) -> bool:
        with self._lock:
            if self.connected:
                info = self.call("terminal_info")
                if info is not None and getattr(info, "connected", False):
                    return True
            return self.connect()

    def call(self, name: str, *args: Any, **kwargs: Any) -> Any:
        with self._lock:
            return getattr(self.mt5, name)(*args, **kwargs)

    def error(self) -> str:
        with self._lock:
            try:
                return str(self.mt5.last_error())
            except Exception:  # noqa: BLE001
                return "unknown"

    def shutdown(self) -> None:
        with self._lock:
            if self._mt5 is not None:
                self._mt5.shutdown()
            self.connected = False

    def status(self) -> dict[str, Any]:
        """Connection and account summary for the dashboard. Never raises."""
        try:
            if not self.ensure():
                return {"connected": False, "error": self.last_error or self.error()}
            term = self.call("terminal_info")
            acc = self.call("account_info")
            if acc is None:
                return {"connected": False, "error": f"no account: {self.error()}"}
            return {
                "connected": bool(getattr(term, "connected", False)),
                "algo_trading_enabled": bool(getattr(term, "trade_allowed", False)),
                "login": acc.login,
                "server": acc.server,
                "company": getattr(acc, "company", ""),
                "name": getattr(acc, "name", ""),
                "currency": acc.currency,
                "account_type": TRADE_MODES.get(acc.trade_mode, str(acc.trade_mode)),
                "margin_mode": MARGIN_MODES.get(acc.margin_mode, str(acc.margin_mode)),
                "leverage": acc.leverage,
                "balance": acc.balance,
                "equity": acc.equity,
                "margin_free": acc.margin_free,
                "trade_allowed": bool(getattr(acc, "trade_allowed", True)),
            }
        except MT5Unavailable as e:
            return {"connected": False, "error": str(e)}
        except Exception as e:  # noqa: BLE001
            return {"connected": False, "error": f"{type(e).__name__}: {e}"}
