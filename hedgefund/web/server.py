"""Wiring: config + store + price feed + engine + web app.

Feed selection (HF_FEED): "mt5" uses the MetaTrader 5 terminal on this machine, "simulation"
uses simulated prices; "auto" (default) picks MT5 when the MetaTrader5 package is installed.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path

from hedgefund.bots.engine import BotEngine
from hedgefund.bots.simfeed import SimulatedFeed
from hedgefund.bots.store import PlatformStore
from hedgefund.config import load_config
from hedgefund.web.app import WebSettings, create_app
from hedgefund.web.security import AuthService

log = logging.getLogger("hedgefund.web")


def make_feed(kind: str = "auto"):
    kind = (kind or "auto").lower()
    if kind in ("auto", "mt5"):
        try:
            import MetaTrader5  # type: ignore[import-not-found]  # noqa: F401
        except ImportError:
            if kind == "mt5":
                raise SystemExit("HF_FEED=mt5 but the MetaTrader5 package is not installed (Windows: pip install MetaTrader5)") from None
        else:
            from hedgefund.mt5.client import MT5Client
            from hedgefund.mt5.data import MT5Feed

            client = MT5Client.from_env()
            if not client.connect():
                log.warning("MT5 terminal not reachable yet (%s); the dashboard will show it disconnected", client.last_error)
            return MT5Feed(client), client
    return SimulatedFeed(), None


def build_platform(config_path: str | None = None, data_dir: str | None = None, feed: str | None = None, settings: WebSettings | None = None, start_engine: bool = True):
    cfg = load_config(config_path)
    data = Path(data_dir or os.environ.get("HF_DATA_DIR") or cfg.var_dir)
    store = PlatformStore(data / "platform.db")
    settings = settings or WebSettings.from_env()
    price_feed, client = make_feed(feed or os.environ.get("HF_FEED", "auto"))
    engine = BotEngine(cfg, store, price_feed, mt5_client=client, data_dir=data, allow_real_env=settings.allow_real_trading)
    auth = AuthService(store, session_hours=settings.session_hours)
    return create_app(engine, auth, settings, start_engine=start_engine), engine, auth
