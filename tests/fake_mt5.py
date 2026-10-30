"""In-memory stand-in for the ``MetaTrader5`` package (the real one needs Windows + a terminal).
Implements the subset of the API the connector uses, with netting/hedging account modes."""

from __future__ import annotations

import itertools
import time
from types import SimpleNamespace as NS

TRADE_ACTION_DEAL = 1
ORDER_TYPE_BUY, ORDER_TYPE_SELL = 0, 1
POSITION_TYPE_BUY, POSITION_TYPE_SELL = 0, 1
DEAL_TYPE_BUY, DEAL_TYPE_SELL = 0, 1
ORDER_TIME_GTC = 0
ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN = 0, 1, 2
ACCOUNT_TRADE_MODE_DEMO, ACCOUNT_TRADE_MODE_REAL = 0, 2
ACCOUNT_MARGIN_MODE_RETAIL_NETTING, ACCOUNT_MARGIN_MODE_RETAIL_HEDGING = 0, 2
TIMEFRAME_M15, TIMEFRAME_H1, TIMEFRAME_H4, TIMEFRAME_D1 = 15, 16385, 16388, 16408
TRADE_RETCODE_DONE, TRADE_RETCODE_REQUOTE, TRADE_RETCODE_NO_MONEY, TRADE_RETCODE_TIMEOUT = 10009, 10004, 10019, 10012


class FakeMT5:
    def __init__(self, hedging: bool = False, real: bool = False, server_offset_h: int = 3):
        for k, v in globals().items():
            if k.isupper():
                setattr(self, k, v)
        self.offset = server_offset_h * 3600
        self.account = NS(login=123, server="Broker-Demo", company="Broker", name="Test", currency="USD", trade_mode=2 if real else 0,
                          margin_mode=2 if hedging else 0, leverage=100, balance=10_000.0, equity=10_000.0, margin_free=9_000.0, trade_allowed=True)
        self.terminal = NS(connected=True, trade_allowed=True)
        self.symbols = {
            "XAUUSD": NS(name="XAUUSD", path="Metals\\XAUUSD", description="Gold", visible=True, digits=2, point=0.01, trade_contract_size=100,
                         trade_tick_value=1.0, trade_tick_size=0.01, volume_min=0.01, volume_step=0.01, volume_max=50, spread=20, filling_mode=2,
                         trade_mode=4, swap_long=-30, swap_short=5, currency_profit="USD"),
            "NAS100": NS(name="NAS100", path="Indices\\NAS100", description="Nasdaq", visible=False, digits=2, point=0.01, trade_contract_size=1,
                         trade_tick_value=0.01, trade_tick_size=0.01, volume_min=0.1, volume_step=0.1, volume_max=100, spread=150, filling_mode=1,
                         trade_mode=4, swap_long=-5, swap_short=-2, currency_profit="USD"),
        }
        self.prices = {"XAUUSD": 2400.0, "NAS100": 19000.0}
        self.positions: list[NS] = []
        self.deals: list[NS] = []
        self.sent: list[dict] = []
        self.script: list[object] = []  # queued results for order_send: retcode int, None, or "timeout_filled"
        self._tickets = itertools.count(1000)

    # ---- connection ----
    def initialize(self, **kw):
        return True

    def shutdown(self):
        pass

    def last_error(self):
        return (1, "ok")

    def terminal_info(self):
        return self.terminal

    def account_info(self):
        return self.account

    # ---- symbols & data ----
    def symbols_get(self, group="*"):
        return tuple(self.symbols.values())

    def symbol_info(self, s):
        return self.symbols.get(s)

    def symbol_select(self, s, enable=True):
        if s in self.symbols:
            self.symbols[s].visible = True
            return True
        return False

    def symbol_info_tick(self, s):
        p = self.prices[s]
        half = self.symbols[s].spread * self.symbols[s].point / 2
        return NS(time=int(time.time()) + self.offset, bid=p - half, ask=p + half, last=p)

    def copy_rates_from_pos(self, s, tf, start, count):
        step = {15: 900, 16385: 3600, 16388: 14400, 16408: 86400}[tf]
        now_server = int(time.time()) + self.offset
        last_open = now_server // step * step  # the still-forming bar
        out = []
        p = self.prices[s]
        for i in range(count - 1, -1, -1):
            t = last_open - i * step
            p *= 1.0005 if (t // step) % 3 else 0.999
            out.append({"time": t, "open": p, "high": p * 1.001, "low": p * 0.999, "close": p, "tick_volume": 100, "spread": 10, "real_volume": 0})
        return out

    # ---- trading ----
    def order_send(self, req):
        self.sent.append(dict(req))
        if self.script:
            action = self.script.pop(0)
            if action is None:
                return None
            if action == "timeout_filled":
                self._execute(req)
                return NS(retcode=TRADE_RETCODE_TIMEOUT, deal=0, order=0, volume=0, price=0, comment="timeout")
            return NS(retcode=action, deal=0, order=0, volume=0, price=0, comment="scripted")
        deal = self._execute(req)
        return NS(retcode=TRADE_RETCODE_DONE, deal=deal.ticket, order=deal.ticket, volume=req["volume"], price=req["price"], comment="done")

    def _execute(self, req):
        s, vol, buy = req["symbol"], req["volume"], req["type"] == ORDER_TYPE_BUY
        deal = NS(ticket=next(self._tickets), time=int(time.time()), type=DEAL_TYPE_BUY if buy else DEAL_TYPE_SELL, magic=req["magic"], volume=vol,
                  price=req["price"], commission=-0.5 * vol, fee=0.0, swap=0.0, profit=0.0, symbol=s, comment=req["comment"])
        self.deals.append(deal)
        ptype = POSITION_TYPE_BUY if buy else POSITION_TYPE_SELL
        if "position" in req:  # hedging close by ticket
            pos = next(p for p in self.positions if p.ticket == req["position"])
            pos.volume = round(pos.volume - vol, 8)
            if pos.volume <= 1e-9:
                self.positions.remove(pos)
        elif self.account.margin_mode == 0:  # netting
            pos = next((p for p in self.positions if p.symbol == s and p.magic == req["magic"]), None)
            signed = vol if buy else -vol
            if pos is None:
                self._open(s, req, ptype, vol)
            else:
                cur = pos.volume if pos.type == POSITION_TYPE_BUY else -pos.volume
                new = round(cur + signed, 8)
                if abs(new) < 1e-9:
                    self.positions.remove(pos)
                else:
                    pos.volume, pos.type = abs(new), POSITION_TYPE_BUY if new > 0 else POSITION_TYPE_SELL
        else:
            self._open(s, req, ptype, vol)
        return deal

    def _open(self, s, req, ptype, vol):
        self.positions.append(NS(ticket=next(self._tickets), time=int(time.time()), type=ptype, magic=req["magic"], volume=vol, price_open=req["price"],
                                 price_current=req["price"], profit=0.0, swap=0.0, symbol=s, comment=req["comment"]))

    def positions_get(self, symbol=None):
        return tuple(p for p in self.positions if symbol is None or p.symbol == symbol)

    def history_deals_get(self, *args, ticket=None, **kw):
        if ticket is not None:
            return tuple(d for d in self.deals if d.ticket == ticket)
        return tuple(self.deals)
