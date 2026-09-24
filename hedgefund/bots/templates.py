"""Strategy templates the platform can run on any MT5 symbol, and the conversion of a bot's
settings into a full, validated StrategySpec (so every bot goes through the same Jev gates,
policy, risk engine and execution as the rest of the fund).

Look-backs are expressed in "days" of bars (24h / bar length). On markets that close at
weekends they therefore span somewhat more calendar time; that is intended and harmless.
"""

from __future__ import annotations

import re
import secrets
from dataclasses import dataclass, field
from typing import Any

from hedgefund.core.timeutil import bars_per_day
from hedgefund.mt5.catalog import SymbolSpec
from hedgefund.strategy.spec import StrategySpec, spec_from_dict

TIMEFRAMES = {"15m": "15 minutes", "1h": "1 heure", "4h": "4 heures", "1d": "1 jour"}
DIRECTIONS = {"both": "Achat et vente", "long": "Achat uniquement", "short": "Vente uniquement"}


@dataclass(frozen=True)
class Param:
    default: float
    min: float
    max: float
    label: str


@dataclass(frozen=True)
class Template:
    key: str
    label: str
    description: str
    impl: str
    n_symbols: int
    profile: str
    allowed_regimes: tuple[str, ...]
    horizon_days: int
    params: dict[str, Param] = field(default_factory=dict)

    def public(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "label": self.label,
            "description": self.description,
            "n_symbols": self.n_symbols,
            "params": {k: vars(v) for k, v in self.params.items()},
        }


TEMPLATES: dict[str, Template] = {
    "trend": Template(
        "trend",
        "Suivi de tendance",
        "Entre quand les tendances à 20, 60 et 120 jours vont dans le même sens et que le mouvement est régulier ; sort quand la majorité s'inverse. Adapté à l'or, aux indices et à la crypto sur 1h à 1j.",
        "hedgefund.strategy.library.trend:TimeSeriesMomentum",
        1,
        "directional",
        ("trending", "high_vol"),
        10,
        {
            "lookback_short_days": Param(20, 5, 60, "Horizon court (jours)"),
            "lookback_mid_days": Param(60, 20, 120, "Horizon moyen (jours)"),
            "lookback_long_days": Param(120, 60, 250, "Horizon long (jours)"),
            "min_efficiency": Param(0.25, 0.05, 0.6, "Régularité minimale du mouvement (0-1)"),
            "stop_vol_mult": Param(2.0, 1.0, 5.0, "Stop en multiples de volatilité"),
            "stop_horizon_days": Param(10, 1, 30, "Horizon du stop (jours)"),
            "min_stop_pct": Param(0.01, 0.002, 0.1, "Stop minimum (fraction du prix)"),
        },
    ),
    "mean_reversion": Template(
        "mean_reversion",
        "Retour à la moyenne",
        "Vend les excès à la hausse et achète les excès à la baisse par rapport à la moyenne récente, seulement quand le marché n'est pas en tendance. Adapté au forex, à l'or et aux indices en range.",
        "hedgefund.strategy.library.reversion:ZScoreReversion",
        1,
        "mean_reversion",
        ("mean_reverting",),
        5,
        {
            "z_window_days": Param(20, 5, 60, "Fenêtre de la moyenne (jours)"),
            "entry_z": Param(2.0, 1.0, 4.0, "Écart d'entrée (écarts-types)"),
            "exit_z": Param(0.5, 0.0, 1.5, "Écart de sortie (écarts-types)"),
            "stop_z": Param(3.5, 2.0, 6.0, "Écart d'arrêt (écarts-types)"),
            "max_er": Param(0.3, 0.05, 0.8, "Tendance maximale tolérée (0-1)"),
            "max_hold_days": Param(10, 1, 60, "Durée maximale (jours)"),
            "stop_vol_mult": Param(2.5, 1.0, 6.0, "Stop en multiples de volatilité journalière"),
            "min_stop_pct": Param(0.005, 0.001, 0.1, "Stop minimum (fraction du prix)"),
        },
    ),
    "pair": Template(
        "pair",
        "Paire (valeur relative)",
        "Achète l'actif relativement bon marché et vend l'autre quand leur rapport s'écarte fortement de sa moyenne (ex. or/argent, Nasdaq/S&P 500, ETH/BTC). Position neutre au marché.",
        "hedgefund.strategy.library.relative_value:EthBtcRelativeValue",
        2,
        "relative_value",
        ("mean_reverting", "trending"),
        10,
        {
            "z_window_days": Param(30, 10, 90, "Fenêtre du rapport (jours)"),
            "entry_z": Param(2.0, 1.0, 4.0, "Écart d'entrée (écarts-types)"),
            "exit_z": Param(0.5, 0.0, 1.5, "Écart de sortie (écarts-types)"),
            "stop_z": Param(3.5, 2.0, 6.0, "Écart d'arrêt (écarts-types)"),
            "max_ratio_er": Param(0.3, 0.05, 0.8, "Tendance maximale du rapport (0-1)"),
            "max_hold_days": Param(20, 1, 90, "Durée maximale (jours)"),
            "stop_distance_pct": Param(0.05, 0.01, 0.2, "Risque supposé du paquet (fraction)"),
        },
    ),
}

BOT_ID_RE = re.compile(r"^bot_[a-f0-9]{8}$")


def new_bot_id() -> str:
    return f"bot_{secrets.token_hex(4)}"


def validate_bot(bot: dict[str, Any], catalog: dict[str, SymbolSpec]) -> list[str]:
    p: list[str] = []
    t = TEMPLATES.get(bot.get("strategy", ""))
    if t is None:
        return [f"stratégie inconnue: {bot.get('strategy')}"]
    if not BOT_ID_RE.match(bot.get("id", "")):
        p.append("identifiant de bot invalide")
    name = bot.get("name", "")
    if not 1 <= len(name) <= 60:
        p.append("le nom doit faire 1 à 60 caractères")
    syms = bot.get("symbols") or []
    if len(syms) != t.n_symbols:
        p.append(f"cette stratégie demande {t.n_symbols} actif(s)")
    if len(set(syms)) != len(syms):
        p.append("les deux actifs doivent être différents")
    for s in syms:
        if s not in catalog:
            p.append(f"actif inconnu chez le broker: {s}")
    if bot.get("timeframe") not in TIMEFRAMES:
        p.append("unité de temps invalide")
    if bot.get("direction") not in DIRECTIONS:
        p.append("sens invalide")
    if t.key == "pair" and bot.get("direction") != "both":
        p.append("une paire doit pouvoir être achetée et vendue (sens: les deux)")
    r = bot.get("risk_per_trade_pct")
    if not isinstance(r, (int, float)) or not 0.05 <= r <= 1.5:
        p.append("risque par trade: entre 0,05 % et 1,5 %")
    m = bot.get("max_position_pct")
    if not isinstance(m, (int, float)) or not 1 <= m <= 25:
        p.append("position maximale: entre 1 % et 25 % du capital")
    for k, v in (bot.get("params") or {}).items():
        spec = t.params.get(k)
        if spec is None:
            p.append(f"paramètre inconnu: {k}")
        elif not isinstance(v, (int, float)) or not spec.min <= v <= spec.max:
            p.append(f"{spec.label}: entre {spec.min} et {spec.max}")
    return p


def build_spec(bot: dict[str, Any], catalog: dict[str, SymbolSpec], prices: dict[str, float]) -> StrategySpec:
    t = TEMPLATES[bot["strategy"]]
    syms = bot["symbols"]
    params = {k: v.default for k, v in t.params.items()} | dict(bot.get("params") or {})
    spread_bps = sum(catalog[s].half_spread_bps(prices.get(s, 0.0)) * 2 for s in syms) or 1.0
    directions = {"both": ["long", "short"], "long": ["long"], "short": ["short"]}[bot["direction"]]
    horizon_bars = t.horizon_days * bars_per_day(bot["timeframe"])
    legs = [{"symbol": syms[0], "weight": 1.0}] + ([{"symbol": syms[1], "weight": -1.0}] if t.n_symbols == 2 else [])
    raw = {
        "id": bot["id"],
        "name": bot["name"],
        "version": 1,
        "owner_desk": "platform",
        "stage": "paper_trade",
        "impl": t.impl,
        "hypothesis": f"{t.label} sur {' / '.join(syms)} ({bot['timeframe']}). {t.description}",
        "edge_source": "behavioral",
        "universe": syms,
        "packages": [{"key": "-".join(syms), "legs": legs}],
        "timeframe": bot["timeframe"],
        "allowed_directions": directions,
        "features": [],
        "entry_rules": [t.description],
        "exit_rules": ["règles de sortie du modèle", "état de risque Jev flat / crise"],
        "expected_holding": f"jusqu'à {int(params.get('max_hold_days', t.horizon_days))} jours",
        "params": params,
        "risk": {
            "risk_per_trade_pct_nav": bot["risk_per_trade_pct"] / 100.0,
            "max_package_notional_pct_nav": bot["max_position_pct"] / 100.0,
            "rebalance_threshold": 0.35,
            "exit_on_crisis": True,
        },
        "costs": {"fee_bps_roundtrip": max(0.5, spread_bps), "slippage_bps_roundtrip": spread_bps, "funding_note": "Swaps overnight non inclus dans le modèle ; voir l'équité MT5."},
        "liquidity": {"min_bar_notional_volume": 0},
        "jev": {
            "profile": t.profile,
            "allowed_regimes": list(t.allowed_regimes),
            "min_setup_quality": 2,
            "min_liquidity_quality": 1,
            "max_toxic_flow": 2,
            "min_expected_edge": 55,
            "min_confidence": 0.62,
            "calibration_horizon_bars": horizon_bars,
        },
        "invalidation": [
            {"metric": "strategy_drawdown", "op": ">", "threshold": 0.05, "action": "halt"},
            {"metric": "rolling_sharpe_90d", "op": "<", "threshold": -0.5, "min_observations": 90 * bars_per_day(bot["timeframe"]), "action": "halt"},
        ],
        "data_sources": ["mt5"],
        "failure_modes": ["Coûts de swap sur positions longues", "Écarts de prix le week-end", "Spread élargi hors séance"],
        "capacity_usd": 0,
    }
    return spec_from_dict(raw)


def min_trade_notional(spec: SymbolSpec, price: float) -> float:
    return spec.volume_min * spec.multiplier * price
