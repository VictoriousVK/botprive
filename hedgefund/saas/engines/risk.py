"""Risk gate: position sizing, daily and maximum loss room (prop firm profiles or the member's
plan), trades per day, news windows. Deterministic and with a veto: a model never sizes a
position and never overrides a BLOCK.

Asymmetry (book, chapter 8): the analyst proposes without knowing the limits; the gate applies
them and records the disagreement when the proposal asked for more than allowed.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from hedgefund.core.timeutil import DAY_MS, HOUR_MS
from hedgefund.strategy.library import ict_clock as clk

CONFIG = Path(__file__).resolve().parents[3] / "config" / "prop_firms.yaml"
FUTURES = Path(__file__).resolve().parents[3] / "config" / "futures_specs.yaml"
SAFETY = 0.95  # keep 5 % of the room as a buffer against slippage
MONTH_CODE = "FGHJKMNQUVXZ"


def load_profiles(path: Path | None = None) -> dict[str, dict[str, Any]]:
    return yaml.safe_load((path or CONFIG).read_text(encoding="utf-8"))["profiles"]


_FUT: dict[str, dict[str, Any]] | None = None


def futures_contracts() -> dict[str, dict[str, Any]]:
    global _FUT
    if _FUT is None:
        _FUT = yaml.safe_load(FUTURES.read_text(encoding="utf-8"))["contracts"]
    return _FUT


def futures_root(symbol: str) -> str | None:
    """CME root of a futures symbol as platforms write it: MNQ, MNQZ5, MNQZ25, "MNQ 12-25",
    CON.F.US.MNQ.Z25 (TopstepX). None when the symbol is not a known futures contract."""
    s = (symbol or "").strip().upper()
    table = futures_contracts()
    tokens = [t for t in re.split(r"[.\s:/]+", s) if t] or [s]
    for tok in [s, *tokens]:
        for root in sorted(table, key=len, reverse=True):
            if tok == root or re.fullmatch(re.escape(root) + f"[{MONTH_CODE}]\\d{{1,2}}", tok) or re.fullmatch(re.escape(root) + r"\d{2}-\d{2}", tok):
                return root
    return None


@dataclass
class SymbolSpec:
    volume_min: float = 0.01
    volume_step: float = 0.01
    volume_max: float = 100.0
    tick_value: float = 0.0
    tick_size: float = 0.0
    contract_size: float = 1.0
    minis_per_contract: float = 1.0  # a micro future counts as 1/10 of a mini in contract caps
    futures: bool = False

    @property
    def money_per_point_per_lot(self) -> float:
        if self.tick_value > 0 and self.tick_size > 0:
            return self.tick_value / self.tick_size
        return self.contract_size or 1.0

    @classmethod
    def from_platform(cls, spec: Any) -> "SymbolSpec":
        return cls(spec.volume_min, spec.volume_step, spec.volume_max, spec.tick_value, spec.tick_size, spec.contract_size)

    @classmethod
    def for_futures(cls, root: str) -> "SymbolSpec":
        c = futures_contracts()[root]
        pv, ts = float(c["point_value"]), float(c["tick_size"])
        return cls(1.0, 1.0, 1000.0, pv * ts, ts, pv, 0.1 if c.get("micro") else 1.0, True)


@dataclass
class AccountState:
    balance: float
    equity: float
    initial_balance: float
    start_of_day_balance: float
    start_of_day_equity: float
    peak_equity: float
    open_risk: float = 0.0
    open_risk_unknown: int = 0
    trades_today: int = 0
    source: str = "snapshot"
    peak_eod_balance: float | None = None  # highest end-of-day balance (EOD trailing drawdowns)
    best_day: float = 0.0  # best day's net profit (consistency rules)
    total_profit: float = 0.0  # net profit since the start (profit target, consistency)
    positive_days_profit: float = 0.0
    trading_days: int = 0


@dataclass
class Proposal:
    symbol: str
    direction: str  # long | short
    entry: float
    stop: float
    target: float | None = None
    requested_lots: float | None = None
    killzone: str | None = None


@dataclass
class GateResult:
    decision: str
    max_lots: float
    risk_amount: float
    risk_pct: float
    profile: str
    profile_verified: bool
    rules_applied: list[str] = field(default_factory=list)
    violations: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    disagreement_logged: bool = False
    room: dict[str, float] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return {k: getattr(self, k) for k in ("decision", "max_lots", "risk_amount", "risk_pct", "profile", "profile_verified", "rules_applied", "violations", "warnings", "disagreement_logged", "room")}


def day_start(now: int, reset: str) -> int:
    """Start of the firm's trading day containing ``now`` (UTC ms). ny_17: 17:00 New York (forex
    brokers); ny_18: 18:00 New York = 17:00 Chicago (CME futures day, Topstep); cet_0: midnight
    CE(S)T (FTMO); utc3_0: midnight UTC+3 (MT5 platform time); utc_0."""
    if reset == "cet_0":
        off = (2 if clk.is_eu_dst(now) else 1) * HOUR_MS
        local = now + off
        return local - local % DAY_MS - off
    if reset == "utc3_0":
        local = now + 3 * HOUR_MS
        return local - local % DAY_MS - 3 * HOUR_MS
    if reset == "utc_0":
        return now - now % DAY_MS
    minute = 18 * 60 if reset == "ny_18" else 17 * 60
    start = clk.ny_minute_to_utc(now, minute, 0)
    return start if start <= now else clk.ny_minute_to_utc(now, minute, -1)


def size_rules(profile: dict[str, Any], initial: float) -> dict[str, Any] | None:
    """Dollar rules of the account size (futures firms publish amounts per size, not percentages)."""
    for k, v in (profile.get("sizes") or {}).items():
        if initial > 0 and abs(float(k) - initial) <= 0.01 * float(k):
            return dict(v)
    return None


def _floor_step(x: float, step: float) -> float:
    if step <= 0:
        return x
    return math.floor(x / step + 1e-9) * step


def _money(x: float) -> str:
    return f"{x:,.2f}".replace(",", " ").replace(".", ",")


def limits(state: AccountState, plan: dict[str, Any], profile: dict[str, Any]) -> dict[str, float | None]:
    """Remaining room before the daily and the maximum loss limits (money, after open risk).

    max_loss_type: static (floor under the initial balance), trailing (under the highest equity,
    intraday) or trailing_eod (under the highest end-of-day balance). trailing_lock: where a
    trailing floor stops rising: initial, initial_plus_100, or null (it never stops)."""
    current = state.equity if profile.get("includes_floating", True) else state.balance
    sz = size_rules(profile, state.initial_balance)
    pct = plan.get("max_daily_loss_pct") if profile.get("daily_loss_pct") == "plan" else profile.get("daily_loss_pct")
    daily_room = daily_limit = daily_level = None
    base = max(state.start_of_day_balance, state.start_of_day_equity) if profile.get("daily_loss_base") == "max_balance_equity_start_of_day" else state.start_of_day_balance
    if sz and sz.get("daily_loss"):
        daily_limit = float(sz["daily_loss"])
    elif pct:
        ref = state.initial_balance if profile.get("daily_loss_ref") == "initial_balance" else base
        daily_limit = float(pct) / 100 * ref
    if daily_limit:
        daily_level = base - daily_limit
        daily_room = current - daily_level - state.open_risk
    max_room = max_floor = max_amount = None
    if sz and sz.get("max_loss"):
        max_amount = float(sz["max_loss"])
    elif profile.get("max_loss_pct"):
        max_amount = float(profile["max_loss_pct"]) / 100 * state.initial_balance
    if max_amount:
        kind = profile.get("max_loss_type", "static")
        if kind == "trailing":
            max_floor = state.peak_equity - max_amount
            lock = profile.get("trailing_lock", "initial")
        elif kind == "trailing_eod":
            max_floor = max(state.initial_balance, state.peak_eod_balance or state.initial_balance) - max_amount
            lock = profile.get("trailing_lock")
        else:
            max_floor, lock = state.initial_balance - max_amount, None
        if lock == "initial":
            max_floor = min(max_floor, state.initial_balance)
        elif lock == "initial_plus_100":
            max_floor = min(max_floor, state.initial_balance + 100)
        max_room = current - max_floor - state.open_risk
    return {"daily_limit": daily_limit, "daily_level": daily_level, "daily_room": daily_room, "max_floor": max_floor, "max_room": max_room, "max_amount": max_amount, "current": current}


def status(state: AccountState, plan: dict[str, Any], profile: dict[str, Any]) -> dict[str, Any]:
    lim = limits(state, plan, profile)
    out: dict[str, Any] = {"limits": lim, "alerts": []}
    if lim["daily_limit"]:
        used = max(0.0, (lim["daily_limit"] - (lim["daily_room"] + state.open_risk)) / lim["daily_limit"])
        out["daily_used_pct"] = round(used * 100, 1)
        for level in (50, 80, 100):
            if used * 100 >= level:
                out["alerts"].append({"kind": "daily_loss", "level": level})
    if lim["max_floor"] is not None:
        span = lim["max_amount"] or 0.0
        used = max(0.0, (span - (lim["max_room"] + state.open_risk)) / span) if span > 0 else 0.0
        out["max_used_pct"] = round(used * 100, 1)
        for level in (50, 80, 100):
            if used * 100 >= level:
                out["alerts"].append({"kind": "max_loss", "level": level})
    out["objectives"] = objectives(state, profile)
    return out


def objectives(state: AccountState, profile: dict[str, Any]) -> dict[str, Any]:
    """Progress towards the evaluation's rules that are not loss limits: profit target, minimum
    trading days, best-day consistency, contract cap. Information for the member, never a trade."""
    sz = size_rules(profile, state.initial_balance)
    out: dict[str, Any] = {"size_known": sz is not None or not profile.get("sizes"), "warnings": []}
    target = (sz or {}).get("profit_target")
    if target is None and profile.get("profit_target_pct"):
        first = profile["profit_target_pct"][0] if isinstance(profile["profit_target_pct"], list) else profile["profit_target_pct"]
        target = float(first) / 100 * state.initial_balance
    if target:
        out["target"] = {"amount": round(float(target), 2), "progress_pct": round(max(0.0, state.total_profit) / float(target) * 100, 1)}
    if profile.get("min_trading_days"):
        out["trading_days"] = {"done": state.trading_days, "required": int(profile["min_trading_days"])}
    cons = profile.get("consistency")
    if cons and state.best_day > 0:
        ref = {"target": float(target or 0), "total_profit": max(0.0, state.total_profit), "positive_days": state.positive_days_profit}.get(cons.get("base", "total_profit"), 0.0)
        if ref > 0:
            share = state.best_day / ref * 100
            out["consistency"] = {"best_day": round(state.best_day, 2), "share_pct": round(share, 1), "limit_pct": float(cons["pct"]), "base": cons.get("base", "total_profit")}
            if share > float(cons["pct"]):
                out["warnings"].append(f"meilleur jour = {share:.0f} % ({cons.get('base')}) : au-delà de la règle de régularité ({float(cons['pct']):g} %)")
    if sz and sz.get("max_contracts"):
        out["max_contracts"] = int(sz["max_contracts"])
    if profile.get("sizes") and sz is None:
        out["warnings"].append("taille de compte absente du profil : renseignez le solde de départ exact (ex. 50000)")
    return out


def gate(p: Proposal, state: AccountState, plan: dict[str, Any], profile_key: str, profile: dict[str, Any], spec: SymbolSpec,
         events: list[dict[str, Any]] | None = None, now: int = 0) -> GateResult:
    verified = bool(profile.get("verified_at"))
    res = GateResult("PASS", 0.0, 0.0, 0.0, profile_key, verified)
    if not verified and profile_key != "generic":
        res.warnings.append("profil de prop firm à vérifier sur le règlement officiel")
    sign = 1 if p.direction == "long" else -1
    dist = abs(p.entry - p.stop)
    if dist <= 0 or (p.stop - p.entry) * sign >= 0:
        res.decision = "BLOCK"
        res.violations.append("stop absent ou du mauvais côté de l'entrée")
        return res
    per_lot = dist * spec.money_per_point_per_lot
    risk_pct = float(plan.get("risk_per_trade_pct") or 1.0)
    planned_amount = state.balance * risk_pct / 100
    res.rules_applied.append(f"risque prévu par le plan : {risk_pct:g} % du solde ({_money(planned_amount)})")
    if risk_pct > 2.0:
        res.warnings.append(f"risque par trade élevé ({risk_pct:g} %) : réglage du membre")
    lim = limits(state, plan, profile)
    res.room = {k: round(v, 2) for k, v in lim.items() if v is not None}
    rooms = []
    if lim["daily_room"] is not None:
        res.rules_applied.append(f"perte journalière : niveau {_money(lim['daily_level'])}, marge {_money(max(0.0, lim['daily_room']))}")
        rooms.append(lim["daily_room"])
    if lim["max_room"] is not None:
        res.rules_applied.append(f"perte maximale ({profile.get('max_loss_type')}) : plancher {_money(lim['max_floor'])}, marge {_money(max(0.0, lim['max_room']))}")
        rooms.append(lim["max_room"])
    if state.open_risk_unknown:
        res.warnings.append(f"{state.open_risk_unknown} position(s) ouverte(s) sans stop connu : risque ouvert sous-estimé")
    max_day = int(plan.get("max_trades_per_day") or 0)
    if max_day and state.trades_today >= max_day:
        res.violations.append(f"{state.trades_today} trades aujourd'hui : limite du plan ({max_day}) atteinte")
    news = int(profile.get("news_minutes") or 0)
    for e in events or []:
        if e.get("impact") != "high":
            continue
        gap = abs(e["time_utc"] - now) / 60_000
        if news and gap <= news:
            res.violations.append(f"annonce à fort impact ({e.get('title', '')[:60]}) dans la fenêtre interdite de {news} min")
        elif gap <= 15:
            res.warnings.append(f"annonce à fort impact dans {gap:.0f} min : {e.get('title', '')[:60]}")
    allowed = planned_amount
    if rooms:
        room = min(rooms) * SAFETY
        if room <= 0:
            res.violations.append("plus aucune marge avant une limite de perte")
        allowed = min(allowed, max(0.0, room))
    lots_plan = min(_floor_step(planned_amount / per_lot, spec.volume_step), spec.volume_max)
    lots = min(_floor_step(allowed / per_lot, spec.volume_step), spec.volume_max)
    sz = size_rules(profile, state.initial_balance)
    if sz and sz.get("max_contracts") and spec.futures:
        cap = float(sz["max_contracts"]) / spec.minis_per_contract
        if lots > cap:
            lots, lots_plan = cap, min(lots_plan, cap)
            res.rules_applied.append(f"plafond de contrats du compte : {int(sz['max_contracts'])} minis ({int(cap)} contrats de ce type)")
    if spec.futures:
        res.rules_applied.append(f"contrat à terme : {spec.contract_size:g} $ par point et par contrat")
    if p.target is not None:
        rr = abs(p.target - p.entry) / dist
        if plan.get("min_rr") and rr < float(plan["min_rr"]) - 1e-9:
            res.warnings.append(f"RR {rr:.2f} sous le minimum du plan ({float(plan['min_rr']):g})")
    if plan.get("markets") and p.symbol not in plan["markets"]:
        res.warnings.append(f"{p.symbol} n'est pas dans les marchés du plan")
    if plan.get("killzones") and p.killzone is not None and p.killzone not in plan["killzones"]:
        res.warnings.append("hors des killzones du plan")
    if p.requested_lots is not None and p.requested_lots > lots + 1e-9:
        res.disagreement_logged = True
        res.warnings.append(f"taille demandée {p.requested_lots:g} lot(s) > taille autorisée {lots:g}")
    if lots < spec.volume_min - 1e-12:
        res.violations.append(f"taille calculée {lots:g} < minimum du symbole {spec.volume_min:g} : stop trop large pour la marge de risque")
        lots = 0.0
    res.max_lots = round(lots, 6)
    res.risk_amount = round(lots * per_lot, 2)
    res.risk_pct = round(res.risk_amount / state.balance * 100, 3) if state.balance > 0 else 0.0
    if res.violations:
        res.decision = "BLOCK"
        res.max_lots = 0.0
        res.risk_amount = 0.0
        res.risk_pct = 0.0
    elif lots + 1e-9 < lots_plan or res.disagreement_logged:
        res.decision = "REDUCE"
    return res
