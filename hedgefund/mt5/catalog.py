"""Symbol catalogue: categorises broker symbols (gold, indices, crypto, forex, energy...) and
converts broker contract specs into the platform's Instrument model.

Quantities inside the platform are "units" such that notional (account currency) is
``units * price``. For a CFD, one lot moves ``tick_value / tick_size`` account-currency per
1.0 of price, so ``units = lots * tick_value / tick_size``. The venue converts back to lots
and rounds down to the broker's volume step.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass

from hedgefund.config import Instrument

CATEGORY_LABELS = {
    "metals": "Métaux (or, argent)",
    "indices": "Indices (Nasdaq, S&P 500…)",
    "crypto": "Crypto",
    "forex": "Forex",
    "energy": "Énergie (pétrole, gaz)",
    "stocks": "Actions",
    "other": "Autres",
}

_CRYPTO = ("BTC", "ETH", "XRP", "SOL", "LTC", "BCH", "ADA", "DOT", "DOGE", "BNB", "AVAX", "LINK", "XLM", "TRX", "MATIC", "UNI", "ATOM")
_METALS = ("XAU", "XAG", "XPT", "XPD", "GOLD", "SILVER", "PLATINUM", "PALLADIUM")
_ENERGY = ("USOIL", "UKOIL", "WTI", "BRENT", "XTI", "XBR", "NGAS", "NATGAS", "XNG", "CL-OIL", "OIL")
_INDICES = ("NAS100", "USTEC", "US100", "NDX", "NQ", "US500", "SPX", "SP500", "US30", "DJ30", "DJI", "WS30", "GER40", "DE40", "GER30", "DAX",
            "UK100", "FTSE", "FRA40", "CAC", "JP225", "JPN225", "NIK", "HK50", "AUS200", "EU50", "STOXX", "ESP35", "US2000", "RUSSELL", "VIX")
_CCY = {"USD", "EUR", "GBP", "JPY", "CHF", "AUD", "NZD", "CAD", "SEK", "NOK", "DKK", "SGD", "HKD", "ZAR", "MXN", "TRY", "PLN", "CZK", "HUF", "CNH", "XOF"}


def _core(name: str) -> str:
    """Strip broker suffixes like '.m', '_i', '-ecn', '#'."""
    n = name.upper()
    for sep in (".", "_", "-", "#", "!", "+"):
        if sep in n:
            n = n.split(sep)[0]
    return n


def categorize(name: str, path: str = "", description: str = "") -> str:
    p = f"{path} {description}".lower()
    n = _core(name)
    if "crypto" in p or any(n.startswith(c) for c in _CRYPTO):
        return "crypto"
    if "metal" in p or any(n.startswith(m) for m in _METALS):
        return "metals"
    if "energ" in p or "oil" in p or any(n.startswith(e) for e in _ENERGY):
        return "energy"
    if "indic" in p or "index" in p or "indices" in p or any(n.startswith(i) for i in _INDICES):
        return "indices"
    if "forex" in p or (len(n) == 6 and n[:3] in _CCY and n[3:] in _CCY):
        return "forex"
    if "stock" in p or "share" in p or "equit" in p or "action" in p:
        return "stocks"
    return "other"


@dataclass(frozen=True)
class SymbolSpec:
    name: str
    description: str
    category: str
    digits: int
    point: float
    contract_size: float
    tick_value: float
    tick_size: float
    volume_min: float
    volume_step: float
    volume_max: float
    spread_points: float
    filling_mode: int
    trade_mode: int
    swap_long: float
    swap_short: float
    currency_profit: str

    @property
    def multiplier(self) -> float:
        if self.tick_size > 0 and self.tick_value > 0:
            return self.tick_value / self.tick_size
        return self.contract_size or 1.0

    def to_lots(self, units: float) -> float:
        """Round DOWN to the volume step (never trade more than approved)."""
        lots = abs(units) / self.multiplier
        step = self.volume_step or 0.01
        rounded = math.floor(lots / step + 1e-9) * step
        return round(min(rounded, self.volume_max or rounded), 8)

    def to_units(self, lots: float) -> float:
        return lots * self.multiplier

    def half_spread_bps(self, price: float) -> float:
        return self.spread_points * self.point / price / 2 * 1e4 if price > 0 else 0.0

    def to_dict(self) -> dict:
        d = asdict(self)
        d["category_label"] = CATEGORY_LABELS[self.category]
        d["multiplier"] = self.multiplier
        return d


def spec_from_info(info) -> SymbolSpec:
    return SymbolSpec(
        name=info.name,
        description=getattr(info, "description", "") or "",
        category=categorize(info.name, getattr(info, "path", "") or "", getattr(info, "description", "") or ""),
        digits=int(getattr(info, "digits", 2)),
        point=float(getattr(info, "point", 0.01)),
        contract_size=float(getattr(info, "trade_contract_size", 1.0)),
        tick_value=float(getattr(info, "trade_tick_value", 0.0)),
        tick_size=float(getattr(info, "trade_tick_size", 0.0)),
        volume_min=float(getattr(info, "volume_min", 0.01)),
        volume_step=float(getattr(info, "volume_step", 0.01)),
        volume_max=float(getattr(info, "volume_max", 100.0)),
        spread_points=float(getattr(info, "spread", 0)),
        filling_mode=int(getattr(info, "filling_mode", 0)),
        trade_mode=int(getattr(info, "trade_mode", 4)),
        swap_long=float(getattr(info, "swap_long", 0.0)),
        swap_short=float(getattr(info, "swap_short", 0.0)),
        currency_profit=getattr(info, "currency_profit", "USD") or "USD",
    )


def instrument_from_spec(spec: SymbolSpec, price: float, commission_bps: float = 0.0) -> Instrument:
    return Instrument(
        symbol=spec.name,
        kind="cfd",
        base=_core(spec.name),
        quote=spec.currency_profit,
        cluster=spec.category,
        taker_fee_bps=commission_bps,
        maker_fee_bps=commission_bps,
        half_spread_bps=max(spec.half_spread_bps(price), 0.1),
        impact_k_bps=1.0,
        min_notional=spec.volume_min * spec.multiplier * price,
        venue_symbol=spec.name,
    )


# Built-in catalogue for SIMULATION mode (no MT5 terminal): name, description, category,
# reference price, annualised volatility, contract size, typical spread in points, point.
SIMULATED = (
    ("XAUUSD", "Or / Dollar US", "metals", 2400.0, 0.15, 100, 20, 0.01),
    ("XAGUSD", "Argent / Dollar US", "metals", 29.0, 0.25, 5000, 25, 0.001),
    ("NAS100", "Nasdaq 100", "indices", 19000.0, 0.22, 1, 150, 0.01),
    ("US500", "S&P 500", "indices", 5500.0, 0.17, 1, 50, 0.01),
    ("US30", "Dow Jones 30", "indices", 40000.0, 0.16, 1, 200, 0.01),
    ("GER40", "DAX 40", "indices", 18500.0, 0.18, 1, 150, 0.01),
    ("BTCUSD", "Bitcoin / Dollar US", "crypto", 60000.0, 0.55, 1, 3000, 0.01),
    ("ETHUSD", "Ethereum / Dollar US", "crypto", 3000.0, 0.70, 1, 300, 0.01),
    ("EURUSD", "Euro / Dollar US", "forex", 1.08, 0.07, 100000, 10, 0.00001),
    ("GBPUSD", "Livre / Dollar US", "forex", 1.27, 0.08, 100000, 12, 0.00001),
    ("USDJPY", "Dollar US / Yen", "forex", 150.0, 0.09, 100000, 12, 0.001),
    ("USOIL", "Pétrole WTI", "energy", 75.0, 0.35, 100, 30, 0.01),
)


def simulated_specs() -> dict[str, SymbolSpec]:
    out = {}
    for name, desc, cat, _price, _vol, contract, spread, point in SIMULATED:
        out[name] = SymbolSpec(name, desc, cat, max(0, round(-math.log10(point))), point, contract, contract * point, point, 0.01, 0.01, 100.0, spread, 1, 4, -5.0, -5.0, "USD")
    return out
