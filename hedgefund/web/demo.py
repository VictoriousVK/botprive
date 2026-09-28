"""Demonstration mode: the whole platform on fictitious data, to present it to a client.

``python -m hedgefund.web demo`` runs the site, the member space, the trading space, the admin
and the console on a separate data folder (``var/demo`` by default), with simulated prices. On
the first start it creates, through the platform's own routes:

* an operator (console and admin) and two members, each with a random password written to
  ``IDENTIFIANTS-DEMO.txt`` in the demo folder (there is still no default account);
* for the first member: the Quant Elite offer (every feature), a profile, a trading plan, an FTMO 100K account with about
  forty imported trades and a Topstep 50K futures account with trades entered by hand. The
  trades are fictitious and include the mistakes the Coach is built to find (overtrading, a
  revenge trade, a size-up after a loss, trades outside the killzones, early exits);
* for the second member: a Wave payment declared and waiting for validation in the admin;
* a course announced as "bientôt" in the academy.

Every page shows a banner saying the data is fictitious (HF_DEMO=1). Real trading stays off, no
order and no payment leaves the machine, and the real data folder is never touched."""

from __future__ import annotations

import base64
import json
import os
import random
import secrets
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from hedgefund.strategy.library import ict_clock as clk

MARKER = "demo.json"
CREDENTIALS = "IDENTIFIANTS-DEMO.txt"
OPERATOR = "demo"
TRADER = ("awa.demo@example.com", "Awa Ndiaye (démo)")
PROSPECT = ("moussa.demo@example.com", "Moussa Fall (démo)")

PLAN = {"markets": ["XAUUSD", "NAS100", "MNQ"], "killzones": ["London", "NY_AM"], "risk_per_trade_pct": 1.0, "max_daily_loss_pct": 2.0, "max_trades_per_day": 3,
        "revenge_minutes": 15, "size_up_factor": 1.5, "min_rr": 2.0, "setups": ["SilverBullet", "OTE"],
        "rules": ["Pas de trade pendant la pause de midi à New York", "Stop placé avant l'entrée, jamais déplacé contre moi"]}
PROFILE = {"level": "intermediaire", "experience_months": 24, "goals": ["Réussir une évaluation prop firm", "Respecter mon plan"], "prop_firm": "FTMO",
           "trades_manually": True, "uses_eas": False, "language": "fr"}

# CFD contracts as most MT5 brokers quote them: dollars per point for one lot.
POINT_VALUE = {"XAUUSD": 100.0, "NAS100": 1.0}
BASE_PRICE = {"XAUUSD": 2650.0, "NAS100": 20400.0, "MNQ": 20400.0}
STOPS = {"XAUUSD": (4.0, 5.0, 6.0), "NAS100": (30.0, 40.0, 50.0)}
KZ_WINDOWS = {"London": (120, 290), "NY_AM": (420, 590), "NY_Lunch": (725, 800), "NY_PM": (820, 950)}


def demo_dir(var_dir: str | Path, data_dir: str | None = None) -> Path:
    """The demo never uses HF_DATA_DIR: that is where the real data lives."""
    return Path(data_dir) if data_dir else Path(var_dir) / "demo"


def prepare_environment(data: Path) -> None:
    """Settings for a demo, before the platform is built."""
    data.mkdir(parents=True, exist_ok=True)
    os.environ["HF_DATA_DIR"] = str(data)
    os.environ["HF_FEED"] = "simulation"
    os.environ["HF_DEMO"] = "1"
    os.environ["HF_ALLOW_REAL_TRADING"] = "0"
    os.environ["HF_COOKIE_SECURE"] = "0"  # a demo is served over http (this machine, or a VPS without a domain)
    os.environ["HF_HSTS"] = "0"
    # Never the real database, never real Wave payments, never the production host or proxy settings.
    for key in ("HF_SAAS_DB", "LF_WAVE_API_KEY", "LF_WAVE_WEBHOOK_SECRET", "HF_PUBLIC_HOST", "HF_TRUST_PROXY", "HF_PUBLIC_URL", "LF_PUBLIC_URL"):
        os.environ.pop(key, None)


def reset(data: Path) -> None:
    """Deletes a demo folder, and only a demo folder (it must carry the demo marker)."""
    if not data.exists():
        return
    if not (data / MARKER).exists():
        raise SystemExit(f"{data} n'est pas un dossier de démonstration (pas de {MARKER}) : rien n'est supprimé")
    shutil.rmtree(data)


def credentials(data: Path) -> dict[str, Any] | None:
    f = data / MARKER
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else None


def _password() -> str:
    return "demo-" + secrets.token_urlsafe(12)


# ---------------------------------------------------------------- fictitious trades
def _ny(day: datetime, minute: int) -> int:
    """UTC milliseconds of a New York wall-clock minute on that day."""
    wall = datetime(day.year, day.month, day.day, tzinfo=timezone.utc) + timedelta(minutes=minute)
    return clk.ny_to_utc(int(wall.timestamp() * 1000))


def _fmt(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y.%m.%d %H:%M:%S")


def _trading_days(now: datetime, n: int) -> list[datetime]:
    days, d = [], now - timedelta(days=1)
    while len(days) < n:
        if d.weekday() < 5:
            days.append(d)
        d -= timedelta(days=1)
    return sorted(days)


def cfd_trades(now_ms: int, seed: int = 11) -> list[dict[str, Any]]:
    """About forty trades on an FTMO 100K account over the last seven weeks: mostly in the plan,
    with the mistakes the Coach looks for. Risk is 1 000 $ per trade (1 %) unless stated."""
    rng = random.Random(seed)
    days = _trading_days(datetime.fromtimestamp(now_ms / 1000, tz=timezone.utc), 36)
    out: list[dict[str, Any]] = []

    def trade(day: datetime, kz: str, r: float, symbol: str | None = None, risk: float = 1000.0, minute: int | None = None, hold: int | None = None,
              target_r: float = 2.5, stop: float | None = None) -> dict[str, Any]:
        sym = symbol or ("XAUUSD" if rng.random() < 0.6 else "NAS100")
        a, b = KZ_WINDOWS[kz]
        start = minute if minute is not None else rng.randint(a, b)
        side = rng.choice(["buy", "sell"])
        sign = 1 if side == "buy" else -1
        stop = stop or rng.choice(STOPS[sym])
        op = round(BASE_PRICE[sym] * (1 + rng.uniform(-0.03, 0.03)), 2)
        vol = round(risk / (stop * POINT_VALUE[sym]), 2)
        t0 = _ny(day, start)
        t1 = t0 + (hold or rng.randint(15, 110)) * 60_000
        cp = round(op + sign * r * stop, 2)
        t = {"symbol": sym, "side": side, "volume": vol, "open": t0, "open_price": op, "sl": round(op - sign * stop, 2), "tp": round(op + sign * target_r * stop, 2),
             "close": t1, "close_price": cp, "profit": round(sign * (cp - op) * POINT_VALUE[sym] * vol, 2)}
        out.append(t)
        return t

    special = {20: "lunch", 24: "pm", 27: "overtrading", 30: "early", 33: "big_risk"}  # within the last 30 days
    for i, day in enumerate(days):
        kind = special.get(i)
        if kind == "overtrading":  # five trades, a revenge trade six minutes after a loss, doubled size
            trade(day, "London", -1.0, "XAUUSD", minute=150, hold=35, stop=5.0)
            trade(day, "London", -1.0, "XAUUSD", minute=191, hold=30, stop=5.0)
            trade(day, "London", -1.0, "XAUUSD", risk=2000.0, minute=227, hold=20, stop=5.0)  # 6 min after the loss, twice the volume
            trade(day, "NY_AM", 0.8, "NAS100", minute=440)
            trade(day, "NY_AM", -1.0, "NAS100", minute=520)
            continue
        if kind == "lunch":
            trade(day, "NY_Lunch", -1.0)
            trade(day, "NY_AM", 2.5)
            continue
        if kind == "pm":
            trade(day, "NY_PM", -1.0)
            continue
        if kind == "early":
            trade(day, "London", 0.6)
            trade(day, "NY_AM", 0.7)
            continue
        if kind == "big_risk":
            trade(day, "NY_AM", -1.0, risk=1800.0)
            continue
        if rng.random() < 0.25:
            continue  # no setup that day
        kz = "London" if rng.random() < 0.5 else "NY_AM"
        roll = rng.random()
        r = 2.5 if roll < 0.25 else (1.5 if roll < 0.32 else (0.0 if roll < 0.40 else -1.0))
        trade(day, kz, r)
    return out


def cfd_csv(trades: list[dict[str, Any]]) -> str:
    rows = ["Position,Symbol,Type,Volume,Open Time,Open Price,S/L,T/P,Close Time,Close Price,Profit"]
    for n, t in enumerate(trades):
        rows.append(f"{810000 + n},{t['symbol']},{t['side']},{t['volume']:.2f},{_fmt(t['open'])},{t['open_price']:.2f},{t['sl']:.2f},{t['tp']:.2f},"
                    f"{_fmt(t['close'])},{t['close_price']:.2f},{t['profit']:.2f}")
    return "\n".join(rows)


def futures_trades(now_ms: int, account_id: str, seed: int = 5) -> list[dict[str, Any]]:
    """Eight MNQ trades (2 $ a point), 5 contracts, 25-point stops: 250 $ of risk each."""
    rng = random.Random(seed)
    out = []
    for i, day in enumerate(_trading_days(datetime.fromtimestamp(now_ms / 1000, tz=timezone.utc), 12)):
        if i % 3 == 2:
            continue
        side = rng.choice(["long", "short"])
        sign = 1 if side == "long" else -1
        op = round(BASE_PRICE["MNQ"] * (1 + rng.uniform(-0.02, 0.02)) * 4) / 4
        r = [2.0, -1.0, 1.0, -1.0, 2.0, 0.4, -1.0, 2.0][len(out) % 8]
        t0 = _ny(day, rng.randint(575, 590))  # the 9:50 macro, NY AM
        out.append({"account_id": account_id, "symbol": "MNQ", "side": side, "volume": 5, "open_time_utc": t0, "open_price": op,
                    "close_time_utc": t0 + rng.randint(10, 45) * 60_000, "close_price": op + sign * r * 25, "sl": op - sign * 25, "tp": op + sign * 50,
                    "profit": round(r * 25 * 2 * 5, 2), "commission": -3.7})
    return out


# ---------------------------------------------------------------- seeding through the platform's routes
def seed(app: Any, auth: Any, data: Path, now_ms: int, base: str = "http://127.0.0.1:8000") -> dict[str, Any]:
    from fastapi.testclient import TestClient

    def ok(r: Any) -> Any:
        if r.status_code >= 400:
            raise RuntimeError(f"{r.request.method} {r.request.url.path} : {r.status_code} {r.text[:300]}")
        return r.json()

    creds = {"operator": {"username": OPERATOR, "password": _password()},
             "trader": {"email": TRADER[0], "password": _password()}, "prospect": {"email": PROSPECT[0], "password": _password()}}
    op = TestClient(app)
    auth.create_user(OPERATOR, creds["operator"]["password"])
    oh = {"X-CSRF-Token": ok(op.post("/api/auth/login", json={"username": OPERATOR, "password": creds["operator"]["password"]}))["csrf"]}

    # The trader: Quant Elite (every feature), onboarding done, two accounts with fictitious history.
    c = TestClient(app)
    h = {"X-CSRF-Token": ok(c.post("/api/m/register", json={"email": TRADER[0], "password": creds["trader"]["password"], "name": TRADER[1], "phone": "", "accept_terms": True}))["csrf"]}
    mid = ok(c.get("/api/m/me"))["id"]
    ok(op.post(f"/api/admin/members/{mid}/grant", json={"offer": "quant_elite", "months": 1, "reason": "compte de démonstration"}, headers=oh))
    ok(c.put("/api/app/profile", json=PROFILE, headers=h))
    ok(c.put("/api/app/plan", json=PLAN, headers=h))
    ftmo = ok(c.post("/api/app/accounts", json={"label": "FTMO 100K (démo)", "kind": "prop", "broker": "MetaTrader 5", "starting_balance": 100000, "prop_profile": "ftmo_2step"}, headers=h))
    trades = cfd_trades(now_ms)
    ok(c.post("/api/app/import", json={"account_id": ftmo["id"], "filename": "historique-demo.csv", "content_base64": base64.b64encode(cfd_csv(trades).encode()).decode(),
                                       "times_are_utc": True}, headers=h))
    top = ok(c.post("/api/app/accounts", json={"label": "Topstep 50K (démo)", "kind": "prop", "broker": "TopstepX", "starting_balance": 50000, "prop_profile": "topstep_combine"}, headers=h))
    futures = futures_trades(now_ms, top["id"])
    for t in futures:
        ok(c.post("/api/app/trades", json=t, headers=h))
    _journal_notes(c, h, ftmo["id"])

    # The prospect: free account, a Starter payment declared and waiting for the team.
    p = TestClient(app)
    ph = {"X-CSRF-Token": ok(p.post("/api/m/register", json={"email": PROSPECT[0], "password": creds["prospect"]["password"], "name": PROSPECT[1], "phone": "", "accept_terms": True}))["csrf"]}
    try:
        pay = ok(p.post("/api/m/checkout", json={"offer": "starter", "months": 1}, headers=ph))
        ok(p.post(f"/api/m/payments/{pay['payment']['id']}/declare", json={"transaction_ref": "DEMO-" + secrets.token_hex(4).upper()}, headers=ph))
    except RuntimeError as e:  # Wave turned off in the site settings: the demo goes on without it
        creds["note"] = f"paiement de démonstration non créé : {e}"

    ok(op.post("/api/admin/courses", json={"slug": "fvg-en-pratique", "title": "Les FVG en pratique", "subtitle": "Repérer, qualifier et trader un Fair Value Gap",
                                            "level": "Intermédiaire", "access": "academy_member", "status": "soon"}, headers=oh))
    creds["trades"] = {"ftmo": len(trades), "topstep": len(futures)}
    (data / MARKER).write_text(json.dumps(creds, ensure_ascii=False, indent=2), encoding="utf-8")
    (data / CREDENTIALS).write_text(credentials_text(creds, base), encoding="utf-8")
    return creds


def _journal_notes(c: Any, h: dict[str, str], account_id: str) -> None:
    """A few journal entries, as a member would write them."""
    rows = c.get(f"/api/app/trades?days=60&account={account_id}&limit=200").json()
    rows = sorted(rows, key=lambda t: t["open_utc"])
    notes = []
    for t in rows:
        if t.get("killzone") in ("London", "NY_AM") and (t.get("r_multiple") or 0) >= 2:
            notes.append((t, {"setup_model": "SilverBullet", "emotion_before": "calme", "emotion_after": "confiant", "followed_plan": True, "mistakes": [],
                              "notes": "Entrée sur le FVG après la prise de liquidité, stop sous le swing.", "rating": 4}))
        if len(notes) >= 4:
            break
    for a, b in zip(rows, rows[1:]):
        if (a.get("net") or 0) < 0 and b["open_utc"] - (a.get("close_utc") or 0) <= 15 * 60_000:
            notes.append((b, {"setup_model": None, "emotion_before": "frustre", "emotion_after": "stresse", "followed_plan": False, "mistakes": ["revenge", "taille_excessive"],
                              "notes": "Je voulais récupérer la perte tout de suite.", "rating": 1}))
    for t, entry in notes:
        c.put(f"/api/app/trades/{t['id']}/journal", json=entry, headers=h)


def credentials_text(creds: dict[str, Any], base: str = "http://127.0.0.1:8000") -> str:
    o, t, p = creds["operator"], creds["trader"], creds["prospect"]
    return (
        "DÉMONSTRATION : comptes et données fictifs, sur cette machine uniquement.\n\n"
        f"Console et administration   {base}/console  puis  {base}/admin/\n"
        f"  identifiant  {o['username']}\n  mot de passe {o['password']}\n\n"
        f"Membre Quant Elite (toutes les fonctions)   {base}/compte/\n"
        f"  e-mail       {t['email']}\n  mot de passe {t['password']}\n\n"
        f"Membre gratuit (paiement Wave en attente)   {base}/compte/\n"
        f"  e-mail       {p['email']}\n  mot de passe {p['password']}\n"
    )
