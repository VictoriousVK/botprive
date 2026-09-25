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

TIMEFRAMES = {"1m": "1 minute", "5m": "5 minutes", "15m": "15 minutes", "1h": "1 heure", "4h": "4 heures", "1d": "1 jour"}
DIRECTIONS = {"both": "Achat et vente", "long": "Achat uniquement", "short": "Vente uniquement"}


@dataclass(frozen=True)
class Param:
    default: float
    min: float
    max: float
    label: str
    kind: str = "number"  # "number" | "bool" (0/1, shown as a checkbox)
    group: str = ""


def Flag(default: bool, label: str, group: str = "") -> Param:  # noqa: N802 - reads like Param
    return Param(1.0 if default else 0.0, 0.0, 1.0, label, "bool", group)


DAILY_TIMEFRAMES = ("15m", "1h", "4h", "1d")


@dataclass(frozen=True)
class Template:
    key: str
    label: str
    description: str
    impl: str
    n_symbols: int
    profile: str
    allowed_regimes: tuple[str, ...]
    horizon_days: float
    params: dict[str, Param] = field(default_factory=dict)
    timeframes: tuple[str, ...] = DAILY_TIMEFRAMES
    default_timeframe: str = "4h"
    backtest_bars: int = 2000
    allow_scale_in: bool = True
    holding: str = ""
    exit_rules: tuple[str, ...] = ("règles de sortie du modèle", "état de risque Jev flat / crise")
    origin: str = ""  # e.g. the EA a template was ported from (shown as a badge)

    def public(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "label": self.label,
            "origin": self.origin,
            "description": self.description,
            "n_symbols": self.n_symbols,
            "timeframes": list(self.timeframes),
            "default_timeframe": self.default_timeframe,
            "params": {k: vars(v) for k, v in self.params.items()},
        }


G_STRAT, G_WIN, G_SETUP, G_FILTER, G_MANAGE = "Stratégies", "Fenêtres et macros", "Setup", "Filtres et plafonds", "Gestion de la position"
ICT_EXITS = (
    "stop et objectif virtuels vérifiés à chaque bougie et entre les bougies sur le prix live",
    "break-even, clôture partielle unique, stop suiveur, time stop (comme l'EA)",
    "état de risque Jev flat / crise",
)


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
    "ict_pro": Template(
        "ict_pro",
        "ICT Ultimate Pro v6.20 (Silver Bullet + Macro Breaker)",
        "Votre EA « ICT Ultimate Pro AllInOne » : Silver Bullet sur M5 (fenêtres 03-04, 10-11, 14-15 heure de New York : sweep de liquidité, MSS avec displacement, entrée sur la 1ère FVG) et Macro Breaker sur M1 (macros ICT : stop hunt, breaker confirmé, retest). Passe stricte puis passe relâchée, score, stop derrière le sweep, objectif sur le pool de liquidité opposé (RR ≥ 2). Calibré pour l'or (XAUUSD). Tourne en bougies de 1 minute.",
        "hedgefund.strategy.library.ict:IctProV620",
        1,
        "ict",
        ("trending", "mean_reverting"),
        0.1,
        {
            "enable_sb": Flag(True, "Silver Bullet (M5)", G_STRAT),
            "enable_mb": Flag(True, "Macro Breaker (M1)", G_STRAT),
            "sb_london": Flag(True, "Silver Bullet Londres 03:00-04:00 NY", G_WIN),
            "sb_ny_am": Flag(True, "Silver Bullet NY matin 10:00-11:00 NY", G_WIN),
            "sb_ny_pm": Flag(True, "Silver Bullet NY après-midi 14:00-15:00 NY", G_WIN),
            "mb_london": Flag(True, "Macros de Londres (03:20, 03:50 NY)", G_WIN),
            "mb_ny_am": Flag(True, "Macros NY matin (08:20 à 11:20 NY)", G_WIN),
            "mb_ny_pm": Flag(True, "Macros NY après-midi (13:20 à 15:50 NY)", G_WIN),
            "min_rr": Param(2.0, 1.0, 5.0, "RR minimum planifié", group=G_SETUP),
            "sb_min_score": Param(3, 0, 12, "Score minimal Silver Bullet", group=G_SETUP),
            "mb_min_score": Param(2, 0, 12, "Score minimal Macro Breaker", group=G_SETUP),
            "sb_min_retrace": Param(0.35, 0.0, 1.0, "SB : retracement minimal de la jambe à l'entrée (0-1)", group=G_SETUP),
            "sb_take_first_fvg": Flag(True, "SB : entrer sur la 1ère FVG du displacement", G_SETUP),
            "mb_allow_retested": Flag(True, "MB : accepter un breaker déjà touché (non violé)", G_SETUP),
            "mb_require_unicorn": Flag(False, "MB : exiger un FVG dans le breaker (Unicorn)", G_SETUP),
            "require_htf_align": Flag(False, "Exiger l'alignement avec le biais H1", G_SETUP),
            "sb_relax_after_min": Param(30, 0, 60, "SB : 2e passe relâchée N min après le début de fenêtre (0 = off)", group=G_SETUP),
            "mb_relax_after_min": Param(8, 0, 20, "MB : 2e passe relâchée N min après le début de macro (0 = off)", group=G_SETUP),
            "sb_max_stop_atr": Param(6.0, 1.0, 15.0, "SB : distance de stop maximale (ATR M5)", group=G_SETUP),
            "mb_max_stop_atr": Param(12.0, 2.0, 30.0, "MB : distance de stop maximale (ATR M1)", group=G_SETUP),
            "max_trades_per_day": Param(8, 0, 20, "Trades max par jour NY (0 = illimité)", group=G_FILTER),
            "max_trades_per_window": Param(1, 0, 5, "Trades max par fenêtre / macro (0 = illimité)", group=G_FILTER),
            "max_spread_atr": Param(0.15, 0.0, 1.0, "Spread max en fraction de l'ATR M5 (0 = off)", group=G_FILTER),
            "friday_last_entry_hour": Param(12, 0, 23, "Vendredi : plus d'entrée après cette heure NY (0 = off)", group=G_FILTER),
            "max_adr_used_pct": Param(0, 0, 300, "Pas d'entrée si le jour a déjà fait ce % de l'ADR(5) (0 = off)", group=G_FILTER),
            "flatten_at_ny_minute": Param(0, 0, 1439, "Tout fermer à cette minute NY (720 = 12:00 ; 0 = off)", group=G_FILTER),
            "be_at_r": Param(1.0, 0.0, 5.0, "Break-even à partir de ce R (0 = off)", group=G_MANAGE),
            "partial_pct": Param(40, 0, 90, "Clôture partielle unique : % du volume (0 = off)", group=G_MANAGE),
            "partial_at_r": Param(2.0, 0.5, 10.0, "… à ce R", group=G_MANAGE),
            "trailing_start_r": Param(2.0, 0.0, 10.0, "Stop suiveur à partir de ce R (0 = off)", group=G_MANAGE),
            "trailing_atr_mult": Param(2.5, 0.5, 10.0, "… distance en ATR M5", group=G_MANAGE),
            "trail_by_swing": Flag(True, "… ou sous le dernier swing M5 si plus proche", G_MANAGE),
            "time_stop_min": Param(75, 0, 600, "Time stop : minutes après la fin de fenêtre / macro (0 = off)", group=G_MANAGE),
            "time_stop_min_r": Param(0.3, -1.0, 3.0, "… si le trade n'a pas atteint ce R", group=G_MANAGE),
            "max_hold_min": Param(0, 0, 1440, "Durée maximale d'une position en minutes (0 = off)", group=G_MANAGE),
        },
        timeframes=("1m",),
        default_timeframe="1m",
        backtest_bars=7200,
        allow_scale_in=False,
        holding="intraday (quelques minutes à quelques heures)",
        exit_rules=ICT_EXITS,
        origin="Votre EA · ICT_Ultimate_Pro_AllInOne v6.20",
    ),
    "ict_v6": Template(
        "ict_v6",
        "ICT Ultimate Pro v6 (croisement EMA + Silver Bullet)",
        "Votre EA « ICT Ultimate Pro v6 » : croisement EMA 7/21 filtré par la EMA 50 (stop au-delà des 2 dernières bougies ± 0,25 ATR, borné entre 0,8 et 2,5 ATR, objectif RR 2 plafonné à 3) et Silver Bullet v6 prioritaire dans les fenêtres (heure serveur 02-05, 09-12, 13-16, 18-21 : displacement ≥ 1,2 ATR, retracement ≤ 0,618, FVG, objectif sur le pool de liquidité le plus proche). Filtres de phase AMD, de volatilité et de spread ; break-even, 50 % fermé à 1R, stop suiveur ATR.",
        "hedgefund.strategy.library.ict:IctV6",
        1,
        "ict",
        ("trending", "mean_reverting"),
        1,
        {
            "use_ema_cross": Flag(True, "Stratégie croisement EMA", G_STRAT),
            "use_silver_bullet": Flag(True, "Silver Bullet v6 (prioritaire dans les fenêtres)", G_STRAT),
            "sb_window_1": Flag(True, "Fenêtre 02:00-05:00 heure serveur", G_WIN),
            "sb_window_2": Flag(True, "Fenêtre 09:00-12:00 heure serveur", G_WIN),
            "sb_window_3": Flag(True, "Fenêtre 13:00-16:00 heure serveur", G_WIN),
            "sb_window_4": Flag(True, "Fenêtre 18:00-21:00 heure serveur", G_WIN),
            "ema_fast": Param(7, 2, 50, "EMA rapide", group=G_SETUP),
            "ema_slow": Param(21, 5, 200, "EMA lente", group=G_SETUP),
            "ema_filter": Param(50, 10, 400, "EMA de tendance", group=G_SETUP),
            "use_ema_filter": Flag(True, "Filtrer par la EMA de tendance", G_SETUP),
            "reward_ratio": Param(2.0, 1.0, 5.0, "Objectif risque/rendement", group=G_SETUP),
            "max_tp_rr": Param(3.0, 1.0, 10.0, "RR maximum de l'objectif", group=G_SETUP),
            "min_sl_atr": Param(0.8, 0.2, 5.0, "Stop minimum (ATR)", group=G_SETUP),
            "max_sl_atr": Param(2.5, 0.5, 10.0, "Stop maximum (ATR)", group=G_SETUP),
            "sb_displacement_atr": Param(1.2, 0.2, 5.0, "SB : displacement minimum (ATR)", group=G_SETUP),
            "sb_retracement_max": Param(0.618, 0.1, 1.0, "SB : retracement maximum", group=G_SETUP),
            "fvg_min_gap_points": Param(30, 0, 1000, "SB : gap minimum du FVG (points)", group=G_SETUP),
            "use_phase_filter": Flag(True, "Filtre de phase AMD (pas d'entrée en accumulation)", G_FILTER),
            "atr_max_mult": Param(2.5, 1.0, 10.0, "Pas d'entrée si ATR > moyenne x", group=G_FILTER),
            "max_spread_atr": Param(0.25, 0.0, 1.0, "Spread max en fraction de l'ATR (0 = off)", group=G_FILTER),
            "max_trades_per_day": Param(4, 0, 20, "Positions max par jour (0 = illimité)", group=G_FILTER),
            "max_trades_per_window": Param(1, 0, 5, "Trades Silver Bullet max par fenêtre", group=G_FILTER),
            "min_minutes_between_trades": Param(15, 0, 240, "Délai minimum entre deux entrées (minutes)", group=G_FILTER),
            "be_at_r": Param(1.0, 0.0, 5.0, "Break-even à partir de ce R (0 = off)", group=G_MANAGE),
            "partial_pct": Param(50, 0, 90, "Allègement partiel : % du volume (0 = off)", group=G_MANAGE),
            "partial_at_r": Param(1.0, 0.5, 10.0, "… à partir de ce R", group=G_MANAGE),
            "trailing_start_r": Param(1.5, 0.0, 10.0, "Stop suiveur à partir de ce R (0 = off)", group=G_MANAGE),
            "trailing_atr_mult": Param(1.5, 0.5, 10.0, "… distance en ATR", group=G_MANAGE),
        },
        timeframes=("5m", "15m", "1h"),
        default_timeframe="15m",
        backtest_bars=4000,
        allow_scale_in=False,
        holding="intraday à quelques jours",
        exit_rules=ICT_EXITS,
        origin="Votre EA · ICT_Ultimate_Pro_v6",
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
    if bot.get("timeframe") not in t.timeframes:
        p.append(f"unité de temps invalide pour cette stratégie ({', '.join(TIMEFRAMES[x] for x in t.timeframes)})")
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
        elif spec.kind == "bool" and v not in (0, 1):
            p.append(f"{spec.label}: 0 ou 1")
    return p


def build_spec(bot: dict[str, Any], catalog: dict[str, SymbolSpec], prices: dict[str, float]) -> StrategySpec:
    t = TEMPLATES[bot["strategy"]]
    syms = bot["symbols"]
    params = {k: v.default for k, v in t.params.items()} | dict(bot.get("params") or {})
    params["point"] = catalog[syms[0]].point  # price step, for settings the EAs express in points
    spread_bps = sum(catalog[s].half_spread_bps(prices.get(s, 0.0)) * 2 for s in syms) or 1.0
    directions = {"both": ["long", "short"], "long": ["long"], "short": ["short"]}[bot["direction"]]
    horizon_bars = max(1, int(t.horizon_days * bars_per_day(bot["timeframe"])))
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
        "exit_rules": list(t.exit_rules),
        "expected_holding": t.holding or f"jusqu'à {int(params.get('max_hold_days', t.horizon_days))} jours",
        "params": params,
        "risk": {
            "risk_per_trade_pct_nav": bot["risk_per_trade_pct"] / 100.0,
            "max_package_notional_pct_nav": bot["max_position_pct"] / 100.0,
            "rebalance_threshold": 0.35,
            "exit_on_crisis": True,
            "allow_scale_in": t.allow_scale_in,
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
        "failure_modes": ["Coûts de swap sur positions longues", "Écarts de prix le week-end", "Spread élargi hors séance"]
        + (["Stops virtuels : exécution au marché, glissement possible au-delà du stop", "Annonces économiques non filtrées (pas de calendrier)"] if t.profile == "ict" else []),
        "capacity_usd": 0,
    }
    return spec_from_dict(raw)


def min_trade_notional(spec: SymbolSpec, price: float) -> float:
    return spec.volume_min * spec.multiplier * price
