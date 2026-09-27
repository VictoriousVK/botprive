"""ICT analysis engine for the SaaS: the deterministic core ported from the EA
(``strategy/library/ict_core.py``) exposed as the Annex A contracts.

Point in time: the analysis only sees bars CLOSED at ``now`` (``MarketView``); a test shifts the
data to prove no future bar leaks in. Definitions are versioned (``DEFINITIONS``) and every
object carries the definition it was detected with, so a golden-set label and an engine output
can always be compared under the same rules. The score of a setup comes from the rules; no model
ever detects or scores anything.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from hedgefund.core.timeutil import MINUTE_MS
from hedgefund.data.series import MarketData
from hedgefund.saas.ingest import killzone_at
from hedgefund.saas.schemas import (
    FVG as FVGOut,
)
from hedgefund.saas.schemas import (
    DefinitionRef,
    ICTAnalysis,
    LiquidityPool,
    PDArray,
    SetupCandidate,
    StructureEvent,
    Swing,
    TimeContext,
)
from hedgefund.strategy.library import ict_clock as clk
from hedgefund.strategy.library.ict_core import (
    BUY,
    FVG,
    SELL,
    LiquidityMap,
    MBParams,
    Market,
    Rates,
    ReferenceLevels,
    SBParams,
    _open_at_or_after,
    find_mss,
    is_swing_high,
    is_swing_low,
    macro_breaker,
    silver_bullet,
    structure_bias,
)

VERSION = "victor-v0"
DEFINITIONS = {
    "swing": DefinitionRef(name="swing_fractal", version=VERSION, params={"left": 2, "right": 2}),
    "fvg": DefinitionRef(name="fvg_three_candles", version=VERSION, params={"min_size_atr": 0.12, "mitigation": "wick_through", "inversion": "close_through"}),
    "sweep": DefinitionRef(name="liquidity_sweep", version=VERSION, params={"min_pen_atr": 0.04, "confirm_bars": 3, "max_episode": 6}),
    "mss": DefinitionRef(name="market_structure_shift", version=VERSION, params={"disp_body_atr": 0.8, "max_bars": 15, "min_range_atr": 0.3}),
    "structure": DefinitionRef(name="bos_choch_close", version=VERSION, params={"swing_strength": 2, "disp_body_atr": 0.8}),
    "killzones": DefinitionRef(name="killzones_ny", version=VERSION, params={"Asia": "20:00-00:00", "London": "02:00-05:00", "NY_AM": "07:00-10:00", "NY_Lunch": "12:00-13:30", "NY_PM": "13:30-16:00"}),
    "premium_discount": DefinitionRef(name="ipda20_range", version=VERSION, params={"equilibrium_band": 0.05}),
}
SB_RULES = [
    ("htf", "Biais H1 aligné avec la direction"), ("rank3", "Sweep d'un niveau majeur (PDH/PDL, PWH/PWL, IPDA)"), ("rank2", "Sweep d'un niveau de session ou d'equal highs/lows"),
    ("disp", "Déplacement fort (corps ≥ 1,5 ATR)"), ("untouched", "FVG encore intact"), ("ote", "FVG dans la zone OTE (62-79 %)"), ("macro", "Dans une macro ICT"),
    ("rr3", "RR ≥ 3"), ("true_open", "Du bon côté du true open"), ("ref", "Sur un niveau de référence"), ("bpr", "BPR (FVG opposé qui se chevauche)"), ("dow", "Jour de semaine favorable"),
    ("no_eq", "Pas d'equal highs/lows juste derrière le stop"),
]


class InsufficientData(ValueError):
    pass


def _iso_ny(utc_ms: int) -> str:
    return datetime.fromtimestamp(clk.utc_to_ny(utc_ms) / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M") + " (NY)"


def _hhmm(minute: int) -> str:
    return f"{minute // 60:02d}:{minute % 60:02d}"


def _pd(price: float, lo: float, hi: float, band: float = 0.05) -> str:
    if hi <= lo:
        return "equilibrium"
    x = (price - lo) / (hi - lo)
    return "premium" if x > 0.5 + band else "discount" if x < 0.5 - band else "equilibrium"


def _bias_label(b: int) -> str:
    return "bullish" if b == BUY else "bearish" if b == SELL else "neutral"


# ---------------------------------------------------------------- objects
def swings(r: Rates, tf: str, s: int = 2, max_each: int = 12, max_look: int = 200) -> list[Swing]:
    out: list[Swing] = []
    nh = nl = 0
    for i in range(s + 1, min(r.n - s - 1, max_look) + 1):
        if nh < max_each and is_swing_high(r, i, s):
            out.append(Swing(kind="high", price=r.h[i], time_utc=r.t[i], timeframe=tf, definition=DEFINITIONS["swing"]))
            nh += 1
        if nl < max_each and is_swing_low(r, i, s):
            out.append(Swing(kind="low", price=r.l[i], time_utc=r.t[i], timeframe=tf, definition=DEFINITIONS["swing"]))
            nl += 1
    return sorted(out, key=lambda x: x.time_utc)


def _fvg_status(d: int, r: Rates, f: FVG) -> str:
    touched = mitigated = False
    for k in range(f.mid_idx - 2, 0, -1):  # later closed bars, oldest first
        if d == BUY:
            if r.c[k] < f.bottom:
                return "inverted"
            if r.l[k] < f.bottom:
                mitigated = True
            elif r.l[k] <= f.top:
                touched = True
        else:
            if r.c[k] > f.top:
                return "inverted"
            if r.h[k] > f.top:
                mitigated = True
            elif r.h[k] >= f.bottom:
                touched = True
    return "mitigated" if mitigated else "partially_mitigated" if touched else "open"


def fvgs(r: Rates, tf: str, atr: float, min_size_atr: float = 0.12, max_look: int = 120) -> list[FVGOut]:
    out: list[FVGOut] = []
    min_size = min_size_atr * atr
    for m in range(2, min(r.n - 2, max_look) + 1):
        for d in (BUY, SELL):
            if d == BUY:
                if r.l[m - 1] - r.h[m + 1] < min_size:
                    continue
                f = FVG(m, r.t[m], r.l[m - 1], r.h[m + 1])
            else:
                if r.l[m + 1] - r.h[m - 1] < min_size:
                    continue
                f = FVG(m, r.t[m], r.l[m + 1], r.h[m - 1])
            out.append(FVGOut(kind="BISI" if d == BUY else "SIBI", top=f.top, bottom=f.bottom, consequent_encroachment=f.ce, created_utc=r.t[m],
                              timeframe=tf, status=_fvg_status(d, r, f), definition=DEFINITIONS["fvg"]))
    return sorted(out, key=lambda x: x.created_utc)


def structure_events(r: Rates, tf: str, atr: float, s: int = 2, keep: int = 8) -> list[StructureEvent]:
    """BOS (continuation) and CHoCH (change of character) on closes beyond the last swing."""
    events: list[StructureEvent] = []
    trend = 0
    cur_sh = cur_sl = None
    for k in range(r.n - s - 2, 0, -1):  # chronological
        i = k + s
        if is_swing_high(r, i, s):
            cur_sh = r.h[i]
        if is_swing_low(r, i, s):
            cur_sl = r.l[i]
        disp = r.body(k) >= 0.8 * atr if atr > 0 else False
        if cur_sh is not None and r.c[k] > cur_sh:
            events.append(StructureEvent(kind="CHoCH" if trend == SELL else "BOS", direction="bullish", level=cur_sh, time_utc=r.t[k], timeframe=tf, displacement=disp))
            trend, cur_sh = BUY, None
        if cur_sl is not None and r.c[k] < cur_sl:
            events.append(StructureEvent(kind="CHoCH" if trend == BUY else "BOS", direction="bearish", level=cur_sl, time_utc=r.t[k], timeframe=tf, displacement=disp))
            trend, cur_sl = SELL, None
    return events[-keep:]


def pools(liq: LiquidityMap, r: Rates) -> list[LiquidityPool]:
    out = []
    for lv in liq.levels:
        swept_t = None
        for i in range(r.n - 1, 0, -1):  # oldest to newest closed bar
            if r.t[i] <= lv.time:
                continue
            if (lv.is_high and r.h[i] > lv.price) or (not lv.is_high and r.l[i] < lv.price):
                swept_t = r.t[i]
                break
        out.append(LiquidityPool(side="BSL" if lv.is_high else "SSL", level=lv.price, source=lv.type, rank=lv.rank, formed_utc=lv.time, swept=swept_t is not None, swept_utc=swept_t))
    return sorted(out, key=lambda p: (-p.rank, p.level))


# ---------------------------------------------------------------- setups
def _candidate(s: Any, bias: int, min_score: int, dr: tuple[float, float]) -> SetupCandidate:
    d = s.details
    zone = d.get("fvg") or d.get("zone") or (min(s.entry, s.sl), max(s.entry, s.sl))
    passed, failed = [], []
    if s.kind == "SB":
        checks = {
            "htf": bias == s.dir, "rank3": s.sweep.rank >= 3, "rank2": s.sweep.rank == 2, "disp": d.get("disp_atr", 0) >= 1.5, "untouched": True,
            "ote": bool(d.get("ote")), "macro": clk.macro_at(s.window_start) is not None, "rr3": s.rr >= 3.0, "true_open": None, "ref": bool(d.get("ref")),
            "bpr": bool(d.get("bpr")), "dow": clk.day_of_week_score(s.window_start) > 0, "no_eq": not d.get("eq_warning"),
        }
    else:
        checks = {
            "htf": bias == s.dir, "rank3": s.sweep.rank >= 3, "rank2": s.sweep.rank == 2, "disp": d.get("disp_atr", 0) >= 1.5, "macro": True,
            "rr3": s.rr >= 3.0, "ref": bool(d.get("ref")), "no_eq": not d.get("eq_warning"),
        }
        if s.unicorn:
            passed.append("Unicorn : FVG à l'intérieur du breaker")
    labels = dict(SB_RULES)
    for key, ok in checks.items():
        if ok is None or key not in labels:
            continue
        (passed if ok else failed).append(labels[key])
    passed.insert(0, f"Sweep {s.sweep.type} à {s.sweep.level:.5g}, puis {'MSS avec déplacement' if s.kind == 'SB' else 'breaker confirmé'}")
    return SetupCandidate(
        model="SilverBullet" if s.kind == "SB" else "MacroBreaker", direction="long" if s.dir == BUY else "short", htf_bias=_bias_label(bias),
        entry_zone=(float(min(zone)), float(max(zone))), entry=s.entry, invalidation=s.sl, targets=[s.tp], rr=round(s.rr, 2), rule_score=int(s.score), min_score=min_score,
        relaxed=bool(s.relaxed), rules_passed=passed, rules_failed=failed,
        evidence_ids=[f"sweep:{s.sweep.type}@{s.sweep.level:.5g}", f"zone:{min(zone):.5g}-{max(zone):.5g}", f"target:{s.tp_source}"],
        description=s.describe(),
    )


# ---------------------------------------------------------------- analysis
@dataclass
class Frames:
    m1: Rates
    m5: Rates
    h1: Rates
    d1: Rates
    entry: Rates


def frames(md: MarketData, symbol: str, now: int, tf_entry: str = "M5") -> Frames:
    view = md.view(now)
    m1 = Rates.from_view(view, symbol, 600)
    m5 = Rates.from_view(view.aux("5m"), symbol, 400)
    h1 = Rates.from_view(view.aux("1h"), symbol, 300)
    d1 = Rates.from_view(view.aux("1d"), symbol, 80)
    if m1 is None or m5 is None or h1 is None or d1 is None or m5.n < 60 or h1.n < 50 or d1.n < 6:
        raise InsufficientData("historique M1/M5/H1/D1 insuffisant pour l'analyse")
    entry = m5
    if tf_entry == "M15":
        e = Rates.from_view(view.aux("15m"), symbol, 300)
        entry = e if e is not None and e.n >= 60 else m5
    elif tf_entry == "M1":
        entry = m1
    return Frames(m1, m5, h1, d1, entry)


def analyze_data(md: MarketData, symbol: str, now: int, tf_entry: str = "M5", tf_htf: str = "H1", spread: float = 0.0, point: float = 0.01, synthetic: bool = False) -> ICTAnalysis:
    f = frames(md, symbol, now, tf_entry)
    atr, atr_m1, atr_d1 = f.m5.atr(1), (f.m1.atr(1) if f.m1.n > 20 else 0.0), f.d1.atr(1)
    if atr <= 0:
        raise InsufficientData("ATR M5 indisponible")
    price = f.m1.c[1]
    as_of = f.m1.t[1] + f.m1.step  # close time of the last closed bar
    liq = LiquidityMap()
    liq.build(now, f.m5, f.h1, f.d1, atr, (20, 40, 60), 2, 0.10, point)
    ref = ReferenceLevels()
    ref.build(now, f.m5, f.m1, f.h1, f.d1)
    ref.push_to(liq)
    if f.m1.n > 60:
        liq.add_swings(f.m1, 3, 12, "M1")
    htf = f.h1 if tf_htf == "H1" else f.d1
    bias = structure_bias(htf, 2)
    dr = (liq.dr_low, liq.dr_high)
    mk = Market(now, price + spread / 2, price - spread / 2, spread, liq, ref, bias, atr_d1)

    # time context
    minute = clk.ny_minute_of_day(now)
    macro = clk.macro_at(now)
    window = clk.window_at(now, set(clk.WINDOWS))
    d18 = clk.ny_minute_to_utc(now, 18 * 60, 0 if minute >= 18 * 60 else -1)
    open18 = _open_at_or_after(f.h1, d18, d18 + 60 * MINUTE_MS) or None
    kz = killzone_at(now)
    amd = "accumulation" if kz == "Asia" or minute < 120 else "manipulation" if kz == "London" else "distribution" if kz in ("NY_AM", "NY_PM") else "unknown"
    tctx = TimeContext(utc=now, ny_time=_iso_ny(now), killzone=kz, macro_window=f"{_hhmm(macro.start)}-{_hhmm(macro.end)} {macro.name}" if macro else None,
                       silver_bullet_window=clk.WINDOWS[window[0]][2] if window else None, midnight_open=ref.midnight_open or None, daily_open_18h=open18, amd_phase=amd)

    tf = tf_entry
    fv = fvgs(f.entry, tf, f.entry.atr(1) or atr)
    pd_arrays: list[PDArray] = []
    for g in fv:
        if g.status in ("open", "partially_mitigated", "inverted"):
            mid = (g.top + g.bottom) / 2
            pd_arrays.append(PDArray(kind="IFVG" if g.status == "inverted" else "FVG", zone_top=g.top, zone_bottom=g.bottom, premium_discount=_pd(mid, *dr), ref_range=dr))
    bisi = [g for g in fv if g.kind == "BISI" and g.status != "mitigated"]
    sibi = [g for g in fv if g.kind == "SIBI" and g.status != "mitigated"]
    for a in bisi:
        for b in sibi:
            top, bot = min(a.top, b.top), max(a.bottom, b.bottom)
            if top > bot:
                pd_arrays.append(PDArray(kind="BPR", zone_top=top, zone_bottom=bot, premium_discount=_pd((top + bot) / 2, *dr), ref_range=dr))
    for g in (ref.ndog, ref.nwog):
        if g[0] > 0:
            pd_arrays.append(PDArray(kind="OpeningGap", zone_top=g[0], zone_bottom=g[1], premium_discount=_pd((g[0] + g[1]) / 2, *dr), ref_range=dr))

    structure = structure_events(f.entry, tf, f.entry.atr(1) or atr) + structure_events(htf, tf_htf, htf.atr(1), keep=4)
    for d in (BUY, SELL):  # MSS after recent sweeps (the ICT reversal pattern)
        for sw in liq.find_sweeps(d, f.m5, atr, 48, 0.04, 3, 6, now - 6 * 60 * MINUTE_MS)[:3]:
            m = find_mss(d, f.m5, sw.extreme_idx, sw.extreme, 15, 0.3, 0.8, atr, 2)
            if m is not None:
                structure.append(StructureEvent(kind="MSS", direction="bullish" if d == BUY else "bearish", level=m.broken_level, time_utc=m.bar_time, timeframe="M5", displacement=True))

    setups: list[SetupCandidate] = []
    rejections: list[str] = []
    dirs = (BUY, SELL)
    if window is not None:
        name, ws, we = window
        sbp = SBParams()
        sb, why = silver_bullet(f.m5, mk, name, ws, we, atr, sbp, dirs)
        if sb is None:
            sb, _ = silver_bullet(f.m5, mk, name, ws, we, atr, sbp.relaxed(), dirs)
            if sb is not None:
                sb.relaxed = True
        if sb is not None:
            setups.append(_candidate(sb, bias, sbp.relaxed().min_score if sb.relaxed else sbp.min_score, dr))
        else:
            rejections.append(f"Silver Bullet : {why or 'aucun setup'}")
    macro_now = macro if macro is not None else clk.macro_recent(now, 25)
    if macro_now is not None and macro_now.id in clk.DEFAULT_MACROS and atr_m1 > 0:
        mbp = MBParams()
        ms, me = clk.macro_range_utc(now, macro_now)
        mb, why = macro_breaker(f.m1, mk, macro_now, ms, me, atr_m1, atr, mbp, dirs)
        if mb is None:
            mb, _ = macro_breaker(f.m1, mk, macro_now, ms, me, atr_m1, atr, mbp.relaxed(), dirs)
            if mb is not None:
                mb.relaxed = True
        if mb is not None:
            setups.append(_candidate(mb, bias, mbp.relaxed().min_score if mb.relaxed else mbp.min_score, dr))
        else:
            rejections.append(f"Macro Breaker ({macro_now.name}) : {why or 'aucun setup'}")
    if window is None and macro_now is None:
        rejections.append("hors fenêtre Silver Bullet et hors macro : aucun modèle d'entrée évalué")

    caveats = []
    if synthetic:
        caveats.append("PRIX SIMULÉS : analyse de démonstration, sans valeur de marché")
    if spread <= 0:
        caveats.append("spread inconnu : niveaux calculés au prix moyen")
    return ICTAnalysis(
        symbol=symbol, tf_entry=tf_entry, tf_htf=tf_htf, as_of=as_of, price=price, htf_bias=_bias_label(bias), dealing_range=dr, premium_discount=_pd(price, *dr),
        time=tctx, swings=swings(f.entry, tf), fvgs=fv[-20:], pools=pools(liq, f.m5)[:30], structure=structure, pd_arrays=pd_arrays[-20:], setups=setups,
        rejections=rejections, definitions=list(DEFINITIONS.values()), caveats=caveats,
    )


def analyze(market: Any, symbol: str, tf_entry: str = "M5", tf_htf: str = "H1", now: int | None = None) -> ICTAnalysis:
    """From the platform feed (MarketData service in ``service.py``)."""
    now = now or market.now()
    specs = market.specs()
    if symbol not in specs:
        raise LookupError(f"symbole inconnu du flux de prix : {symbol}")
    spec = specs[symbol]
    aux = {"M5": 400, "H1": 300, "D1": 80}
    if tf_entry == "M15":
        aux["M15"] = 300
    md = market.data(symbol, "M1", aux, 600, now)
    return analyze_data(md, symbol, now, tf_entry, tf_htf, spread=spec.spread_points * spec.point, point=spec.point, synthetic=market.synthetic)
