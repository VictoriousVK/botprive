"""Feature modules of the SaaS. Each module exposes ``install(saas)``: it registers its tools,
job handlers and services on the container. The order matters only for dependencies."""

from __future__ import annotations

from typing import Any

MODULES: list[str] = ["journal", "stats", "ict", "risk", "coach", "analyste", "router", "mentor", "notify", "tradingview", "research", "scheduler", "lab", "sync", "ea_factory", "publicapi", "overview"]


def install_all(saas: Any) -> None:
    import importlib

    for name in MODULES:
        mod = importlib.import_module(f"hedgefund.saas.{name}")
        saas.modules[name] = mod.install(saas)
    saas.refresh_manifest()
