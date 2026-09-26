"""Trade import: parsers (generic CSV, MT5 HTML report, EA Journal Sync JSON), normalisation
(broker server time → UTC → New York, symbol names) and deterministic enrichment (session,
killzone, macro, R multiple, plan compliance).

Everything here is a pure function: tested on fixtures, no database, no network. About 80 % of
the value of a journal is getting these details right (docs/CONCEPTION.md, Phase 1.5).
"""

from __future__ import annotations

import csv
import hashlib
import io
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Any

from hedgefund.strategy.library import ict_clock as clk

ENRICHMENT_VERSION = "enrich-v1"
HOUR_MS = 3_600_000


class ImportError_(ValueError):
    """Bad input file: the message is shown to the member."""


# ---------------------------------------------------------------- symbols
_ALIASES = {
    "XAUUSD": ("GOLD", "XAUUSD", "XAU/USD", "XAUUSDM", "GOLDSPOT", "XAUUSDSPOT"),
    "XAGUSD": ("SILVER", "XAGUSD", "XAG/USD"),
    "NAS100": ("NAS100", "USTEC", "US100", "NDX100", "NQ100", "NASDAQ", "NASDAQ100", "USTECH", "USTECH100", "NAS", "NQ", "NDX", "US_TECH100", "USTEC100"),
    "US30": ("US30", "DJ30", "WS30", "DOWJONES", "DJI", "US30CASH", "WALLSTREET30", "DOW"),
    "US500": ("US500", "SPX500", "SP500", "SPX", "US500CASH", "USSPX500", "ES"),
    "GER40": ("GER40", "DE40", "DAX40", "GER30", "DE30", "DAX", "GERMANY40"),
    "USOIL": ("USOIL", "WTI", "XTIUSD", "CL", "USCRUDE", "OILUS"),
    "UKOIL": ("UKOIL", "BRENT", "XBRUSD"),
    "BTCUSD": ("BTCUSD", "BTC/USD", "BITCOIN", "BTCUSDT"),
    "ETHUSD": ("ETHUSD", "ETH/USD", "ETHEREUM", "ETHUSDT"),
    "DXY": ("DXY", "USDX", "USDINDEX", "DOLLARINDEX"),
}
_ALIAS = {a: k for k, vals in _ALIASES.items() for a in vals}
_SUFFIX = re.compile(r"(\.[A-Za-z0-9]+|_[A-Za-z0-9]+|-[A-Za-z0-9]+|[+#!$]|\.?(CASH|CAS|PRO|ECN|RAW|STD|MICRO|MINI|SPOT|I|M|C|X|Z|R))$", re.I)


def normalize_symbol(raw: str) -> str:
    s = (raw or "").strip().upper().replace(" ", "")
    if not s:
        raise ImportError_("symbole vide")
    for _ in range(3):
        if s in _ALIAS:
            return _ALIAS[s]
        base = s.replace("/", "")
        if base in _ALIAS:
            return _ALIAS[base]
        if re.fullmatch(r"[A-Z]{6}", base):
            return base  # forex pair
        stripped = _SUFFIX.sub("", s)
        if stripped == s:
            break
        s = stripped
    m = re.match(r"^([A-Z]{6})", s.replace("/", ""))
    if m and m.group(1) not in _ALIAS:
        return m.group(1)
    return _ALIAS.get(s, s[:20])


# ---------------------------------------------------------------- time
def server_offset_ms(utc_ms: int, winter_offset_h: int = 2, dst_rule: str = "us") -> int:
    dst = clk.is_us_dst(utc_ms) if dst_rule == "us" else clk.is_eu_dst(utc_ms) if dst_rule == "eu" else False
    return (winter_offset_h + (1 if dst else 0)) * HOUR_MS


def server_to_utc(server_ms: int, winter_offset_h: int = 2, dst_rule: str = "us", measured_offset_min: int | None = None) -> int:
    """MT5 reports trade times in the broker server's wall-clock time, encoded like UTC. Most
    brokers run at UTC+2 in winter and UTC+3 during US daylight saving (New York close = 00:00);
    the EA Journal Sync measures the real offset (``TimeTradeServer() - TimeGMT()``)."""
    if measured_offset_min is not None:
        return server_ms - measured_offset_min * 60_000
    guess = server_ms - winter_offset_h * HOUR_MS
    return server_ms - server_offset_ms(guess, winter_offset_h, dst_rule)


def parse_time(text: str) -> int:
    """'2026.10.06 16:12:30', '2026-10-06 16:12', ISO 8601, or epoch seconds/ms → ms (the wall
    clock as written; the caller applies the server offset)."""
    t = (text or "").strip()
    if not t:
        raise ImportError_("heure manquante")
    if re.fullmatch(r"\d{9,13}", t):
        v = int(t)
        return v if v > 10**11 else v * 1000
    t = t.replace("T", " ").replace("Z", "").replace("/", ".").replace("-", ".")
    t = re.sub(r"\.\d{3}$", "", t) if re.search(r":\d{2}\.\d{3}$", t) else t
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d %H:%M", "%d.%m.%Y %H:%M:%S", "%d.%m.%Y %H:%M", "%Y.%m.%d"):
        try:
            return int(datetime.strptime(t, fmt).replace(tzinfo=timezone.utc).timestamp() * 1000)
        except ValueError:
            continue
    raise ImportError_(f"format d'heure non reconnu : {text[:40]}")


def _num(text: Any, default: float | None = None) -> float | None:
    if text is None:
        return default
    if isinstance(text, (int, float)):
        return float(text)
    s = str(text).strip().replace(" ", "").replace(" ", "")
    if s in ("", "-", "—"):
        return default
    if "," in s and "." in s:
        s = s.replace(",", "")
    else:
        s = s.replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return default


def _side(text: str) -> str:
    t = (text or "").strip().lower()
    if t in ("buy", "long", "achat", "b", "0", "buy limit", "buy stop"):
        return "long"
    if t in ("sell", "short", "vente", "s", "1", "sell limit", "sell stop"):
        return "short"
    raise ImportError_(f"sens de position inconnu : {text[:20]}")


# ---------------------------------------------------------------- normalised trade
@dataclass
class RawTrade:
    position_id: str
    symbol_raw: str
    side: str
    volume: float
    open_server_ms: int
    open_price: float
    close_server_ms: int | None = None
    close_price: float | None = None
    sl: float | None = None
    tp: float | None = None
    initial_sl: float | None = None
    commission: float = 0.0
    swap: float = 0.0
    profit: float = 0.0
    magic: int | None = None
    comment: str = ""
    deals: list[dict[str, Any]] = field(default_factory=list)
    times_are_utc: bool = False


# ---------------------------------------------------------------- generic CSV
_COLS = {
    "position_id": ("position", "ticket", "position_id", "id", "order", "deal", "ticket_id"),
    "symbol": ("symbol", "symbole", "instrument", "item", "asset"),
    "side": ("type", "side", "direction", "sens", "action"),
    "volume": ("volume", "lots", "size", "lot", "quantity", "quantite"),
    "open_time": ("open_time", "open time", "time", "entry_time", "heure_ouverture", "date_ouverture", "opened", "open date"),
    "open_price": ("open_price", "open price", "price", "entry_price", "prix_ouverture", "entry"),
    "sl": ("sl", "s/l", "s / l", "stop_loss", "stop loss", "stop"),
    "tp": ("tp", "t/p", "t / p", "take_profit", "take profit", "target"),
    "close_time": ("close_time", "close time", "exit_time", "heure_fermeture", "date_fermeture", "closed", "close date"),
    "close_price": ("close_price", "close price", "exit_price", "prix_fermeture", "exit"),
    "commission": ("commission", "commissions", "fees", "frais"),
    "swap": ("swap", "swaps", "rollover"),
    "profit": ("profit", "p/l", "pnl", "resultat", "gain", "net_profit"),
    "magic": ("magic", "magic_number", "expert_id"),
    "comment": ("comment", "commentaire", "note"),
    "initial_sl": ("initial_sl", "sl_initial", "stop_initial"),
}
REQUIRED = ("symbol", "side", "volume", "open_time", "open_price")


def _header_map(header: list[str]) -> dict[str, int]:
    norm = [re.sub(r"\s+", " ", h.strip().lower().replace("﻿", "")) for h in header]
    out: dict[str, int] = {}
    for key, names in _COLS.items():
        for i, h in enumerate(norm):
            if h in names and i not in out.values():
                out[key] = i
                break
    return out


def parse_csv(text: str, times_are_utc: bool = False) -> list[RawTrade]:
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel
    rows = list(csv.reader(io.StringIO(text), dialect))
    rows = [r for r in rows if any(c.strip() for c in r)]
    if len(rows) < 2:
        raise ImportError_("fichier vide ou sans ligne de données")
    cols = _header_map(rows[0])
    missing = [k for k in REQUIRED if k not in cols]
    if missing:
        raise ImportError_("colonnes manquantes : " + ", ".join(missing) + " (voir le modèle de fichier)")
    out = []
    for n, r in enumerate(rows[1:], start=2):
        def g(k: str, r: list[str] = r) -> str:
            i = cols.get(k)
            return r[i].strip() if i is not None and i < len(r) else ""

        try:
            side = _side(g("side"))
        except ImportError_:
            continue  # balance / deposit rows
        try:
            ot = parse_time(g("open_time"))
            ct = parse_time(g("close_time")) if g("close_time") else None
            pid = g("position_id") or hashlib.sha256(f"{g('symbol')}|{ot}|{g('open_price')}|{g('volume')}".encode()).hexdigest()[:16]
            out.append(RawTrade(
                position_id=pid[:40], symbol_raw=g("symbol"), side=side, volume=_num(g("volume"), 0.0) or 0.0, open_server_ms=ot, open_price=_num(g("open_price"), 0.0) or 0.0,
                close_server_ms=ct, close_price=_num(g("close_price")), sl=_num(g("sl")) or None, tp=_num(g("tp")) or None, initial_sl=_num(g("initial_sl")) or None,
                commission=_num(g("commission"), 0.0) or 0.0, swap=_num(g("swap"), 0.0) or 0.0, profit=_num(g("profit"), 0.0) or 0.0,
                magic=int(_num(g("magic"), 0) or 0) or None, comment=g("comment")[:120], times_are_utc=times_are_utc,
            ))
        except ImportError_ as e:
            raise ImportError_(f"ligne {n} : {e}") from e
    if not out:
        raise ImportError_("aucune position trouvée dans le fichier")
    return out


# ---------------------------------------------------------------- MT5 HTML report
class _Table(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.rows: list[list[str]] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None
        self._span = 1

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "tr":
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []
            span = dict(attrs).get("colspan") or "1"
            self._span = int(span) if str(span).isdigit() else 1

    def handle_endtag(self, tag: str) -> None:
        if tag in ("td", "th") and self._row is not None and self._cell is not None:
            txt = " ".join("".join(self._cell).split())
            self._row.append(txt)
            self._row.extend([""] * (self._span - 1))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self.rows.append(self._row)
            self._row = None

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)


def decode_report(raw: bytes) -> str:
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    if len(raw) > 4 and raw[1:2] == b"\x00" and raw[3:4] == b"\x00":
        return raw.decode("utf-16-le")
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def parse_mt5_report(html: str) -> tuple[list[RawTrade], dict[str, Any]]:
    """History report of the MT5 terminal (History tab → Report → HTML). Reads the
    "Positions" table: Time, Position, Symbol, Type, Volume, Price, S/L, T/P, Time, Price,
    Commission, Swap, Profit. Times are server times."""
    p = _Table()
    p.feed(html)
    info: dict[str, Any] = {}
    trades: list[RawTrade] = []
    section = ""
    for row in p.rows:
        cells = [c for c in row]
        first = next((c for c in cells if c), "")
        low = first.lower()
        if low in ("positions", "orders", "deals", "ordres", "transactions", "résultats", "results") and sum(1 for c in cells if c) <= 2:
            section = low
            continue
        if low.startswith(("account:", "compte :", "compte:")):
            info["account"] = " ".join(c for c in cells[1:] if c)[:120]
        if low.startswith(("company:", "société :", "societe:")):
            info["company"] = " ".join(c for c in cells[1:] if c)[:120]
        if section != "positions":
            continue
        vals = [c for c in cells]
        while vals and vals[-1] == "":
            vals.pop()
        if len(vals) < 13 or not re.match(r"\d{4}\.\d{2}\.\d{2}", vals[0]):
            continue
        try:
            side = _side(vals[3])
        except ImportError_:
            continue
        vol = _num(vals[4].split("/")[0], 0.0) or 0.0
        trades.append(RawTrade(
            position_id=vals[1][:40], symbol_raw=vals[2], side=side, volume=vol, open_server_ms=parse_time(vals[0]), open_price=_num(vals[5], 0.0) or 0.0,
            sl=_num(vals[6]) or None, tp=_num(vals[7]) or None, close_server_ms=parse_time(vals[8]) if vals[8] else None, close_price=_num(vals[9]),
            commission=_num(vals[10], 0.0) or 0.0, swap=_num(vals[11], 0.0) or 0.0, profit=_num(vals[12], 0.0) or 0.0,
        ))
    if not trades:
        raise ImportError_("aucune position trouvée : exportez l'onglet Historique en rapport HTML (clic droit → Rapport → HTML)")
    return trades, info


# ---------------------------------------------------------------- EA Journal Sync (deals)
DEAL_ENTRY = {0: "in", 1: "out", 2: "inout", 3: "out"}


def trades_from_deals(deals: list[dict[str, Any]], meta: dict[str, dict[str, Any]] | None = None) -> list[RawTrade]:
    """Positions rebuilt from MT5 deals (``history_deals_get``): entries give the open, exits
    the close, amounts are summed. ``meta`` carries the initial SL/TP read from the entry orders."""
    meta = meta or {}
    by_pos: dict[str, list[dict[str, Any]]] = {}
    for d in deals:
        if int(d.get("type", -1)) not in (0, 1):
            continue  # balance, credit, commission rows
        pid = str(d.get("position_id") or d.get("position") or "")
        if not pid or pid == "0":
            continue
        by_pos.setdefault(pid, []).append(d)
    out = []
    for pid, ds in by_pos.items():
        ds.sort(key=lambda d: (int(d.get("time_msc") or int(d.get("time", 0)) * 1000), str(d.get("ticket"))))
        ins = [d for d in ds if DEAL_ENTRY.get(int(d.get("entry", 0))) == "in"]
        outs = [d for d in ds if DEAL_ENTRY.get(int(d.get("entry", 0))) in ("out", "inout")]
        if not ins:
            continue
        t_ms = lambda d: int(d.get("time_msc") or int(d.get("time", 0)) * 1000)  # noqa: E731
        vin = sum(float(d.get("volume", 0)) for d in ins)
        vout = sum(float(d.get("volume", 0)) for d in outs)
        open_price = sum(float(d["price"]) * float(d.get("volume", 0)) for d in ins) / vin if vin > 0 else float(ins[0]["price"])
        closed = outs and vout >= vin - 1e-9
        close_price = (sum(float(d["price"]) * float(d.get("volume", 0)) for d in outs) / vout) if closed and vout > 0 else None
        m = meta.get(pid, {})
        out.append(RawTrade(
            position_id=pid[:40], symbol_raw=str(ins[0].get("symbol", "")), side="long" if int(ins[0].get("type")) == 0 else "short", volume=round(vin, 6),
            open_server_ms=t_ms(ins[0]), open_price=open_price, close_server_ms=t_ms(outs[-1]) if closed else None, close_price=close_price,
            sl=_num(m.get("sl")) or None, tp=_num(m.get("tp")) or None, initial_sl=_num(m.get("initial_sl")) or None,
            commission=sum(float(d.get("commission", 0) or 0) for d in ds) + sum(float(d.get("fee", 0) or 0) for d in ds),
            swap=sum(float(d.get("swap", 0) or 0) for d in ds), profit=sum(float(d.get("profit", 0) or 0) for d in ds),
            magic=int(ins[0].get("magic") or 0) or None, comment=str(ins[0].get("comment", ""))[:120],
            deals=[{"deal_id": str(d.get("ticket")), "time_server_ms": t_ms(d), "entry": DEAL_ENTRY.get(int(d.get("entry", 0)), "in"), "side": "long" if int(d.get("type")) == 0 else "short",
                    "price": float(d["price"]), "volume": float(d.get("volume", 0)), "profit": float(d.get("profit", 0) or 0), "commission": float(d.get("commission", 0) or 0), "swap": float(d.get("swap", 0) or 0)} for d in ds],
        ))
    return out


# ---------------------------------------------------------------- enrichment
KILLZONES = (("Asia", 1200, 1440), ("London", 120, 300), ("NY_AM", 420, 600), ("NY_Lunch", 720, 810), ("NY_PM", 810, 960))
SESSIONS = (("asia", 1140, 1440), ("asia", 0, 120), ("london", 120, 420), ("new_york", 420, 960))
_SETUP_HINTS = (("SilverBullet", r"\b(sb|silver ?bullet)\b"), ("MacroBreaker", r"\b(mb|macro)\b"), ("DailyOpenSweep", r"\b(do|daily ?open|18h)\b"), ("OTE", r"\bote\b"), ("Venom", r"\bvenom\b"))


def killzone_at(utc_ms: int) -> str | None:
    m = clk.ny_minute_of_day(utc_ms)
    return next((k for k, s, e in KILLZONES if s <= m < e), None)


def session_at(utc_ms: int) -> str:
    m = clk.ny_minute_of_day(utc_ms)
    return next((k for k, s, e in SESSIONS if s <= m < e), "off")


def setup_from_comment(comment: str) -> str | None:
    c = (comment or "").lower()
    return next((name for name, rx in _SETUP_HINTS if re.search(rx, c)), None)


@dataclass
class Enriched:
    open_utc: int
    close_utc: int | None
    net: float
    session: str
    killzone: str | None
    macro: str | None
    weekday: int
    r_multiple: float | None
    r_source: str
    risk_amount: float | None
    setup_model: str | None
    plan_respected: bool | None
    plan_issues: list[str]


def enrich(t: RawTrade, account: dict[str, Any], plan: dict[str, Any], balance: float | None) -> Enriched:
    conv = (lambda ms: ms) if t.times_are_utc else (lambda ms: server_to_utc(ms, int(account.get("server_winter_offset_h") or 2), account.get("server_dst_rule") or "us", account.get("server_utc_offset_min")))
    open_utc = conv(t.open_server_ms)
    close_utc = conv(t.close_server_ms) if t.close_server_ms else None
    net = t.profit + t.commission + t.swap
    macro = clk.macro_at(open_utc)
    sign = 1 if t.side == "long" else -1
    r = None
    source = "none"
    risk_amount = None
    stop = t.initial_sl or t.sl
    if stop and t.close_price is not None and t.open_price > 0:
        dist = abs(t.open_price - stop)
        wrong_side = (sign == 1 and stop >= t.open_price) or (sign == -1 and stop <= t.open_price)
        if dist > t.open_price * 1e-4 and not wrong_side:  # a stop moved to break-even says nothing about the initial risk
            r = sign * (t.close_price - t.open_price) / dist
            source = "sl"
            if abs(r) > 1e-9 and t.profit:
                risk_amount = abs(t.profit / r)
    if r is None and t.close_price is not None and balance and plan.get("risk_per_trade_pct"):
        risk_amount = balance * float(plan["risk_per_trade_pct"]) / 100
        if risk_amount > 0:
            r = net / risk_amount
            source = "plan"
    kz = killzone_at(open_utc)
    issues = []
    sym = normalize_symbol(t.symbol_raw)
    if plan.get("markets") and sym not in plan["markets"]:
        issues.append(f"marché hors plan ({sym})")
    if plan.get("killzones") and kz not in plan["killzones"]:
        issues.append("hors des killzones du plan")
    if source == "sl" and balance and risk_amount and plan.get("risk_per_trade_pct"):
        if risk_amount / balance * 100 > float(plan["risk_per_trade_pct"]) * 1.25:
            issues.append(f"risque {risk_amount / balance * 100:.2f} % > plan {float(plan['risk_per_trade_pct']):.2f} %")
    if plan.get("min_rr") and t.tp and stop and t.open_price:
        rr = abs(t.tp - t.open_price) / max(1e-12, abs(t.open_price - stop))
        if rr < float(plan["min_rr"]) - 1e-9:
            issues.append(f"RR prévu {rr:.1f} < {float(plan['min_rr']):.1f}")
    return Enriched(
        open_utc=open_utc, close_utc=close_utc, net=round(net, 2), session=session_at(open_utc), killzone=kz,
        macro=macro.name if macro else None, weekday=clk.ny_day_of_week(open_utc), r_multiple=round(r, 3) if r is not None else None,
        r_source=source, risk_amount=round(risk_amount, 2) if risk_amount else None, setup_model=setup_from_comment(t.comment),
        plan_respected=(not issues) if plan else None, plan_issues=issues,
    )
