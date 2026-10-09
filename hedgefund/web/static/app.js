/* HedgeFund platform - front-end (vanilla JS, CSP-safe: no inline code, all text via textContent). */
(function () {
  "use strict";

  var state = { csrf: null, user: null, overview: null, meta: null, days: 30, tab: "dashboard", timer: null, editing: null };
  var $ = function (id) { return document.getElementById(id); };

  // ---------------- helpers ----------------
  function el(tag, props, children) {
    var e = document.createElement(tag);
    Object.keys(props || {}).forEach(function (k) {
      if (k === "text") e.textContent = props[k];
      else if (k === "cls") e.className = props[k];
      else if (k.slice(0, 2) === "on") e.addEventListener(k.slice(2), props[k]);
      else e.setAttribute(k, props[k]);
    });
    (children || []).forEach(function (c) { if (c !== null && c !== undefined) e.appendChild(typeof c === "string" ? document.createTextNode(c) : c); });
    return e;
  }
  var nf2 = new Intl.NumberFormat("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  var nf0 = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
  var nfc = new Intl.NumberFormat("fr-FR", { notation: "compact", maximumFractionDigits: 1 });
  function money(v, compact) {
    if (v === null || v === undefined || isNaN(v)) return "—";
    var cur = (state.overview && state.overview.account && state.overview.account.currency) || "USD";
    var s = compact && Math.abs(v) >= 10000 ? nfc.format(v) : (Math.abs(v) >= 1000 ? nf0.format(v) : nf2.format(v));
    return s + " " + cur;
  }
  function signed(v) { return (v > 0 ? "+" : "") + money(v); }
  function pct(v, digits) { return v === null || v === undefined || isNaN(v) ? "—" : (v * 100).toLocaleString("fr-FR", { maximumFractionDigits: digits === undefined ? 2 : digits }) + " %"; }
  function num(v, d) { return v === null || v === undefined || isNaN(v) ? "—" : Number(v).toLocaleString("fr-FR", { maximumFractionDigits: d === undefined ? 4 : d }); }
  function dt(ms, withTime) {
    var d = new Date(ms);
    return withTime === false ? d.toLocaleDateString("fr-FR") : d.toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" });
  }
  function axisDate(ms, span, full) {
    var d = new Date(ms);
    if (full) return d.toLocaleString("fr-FR", { dateStyle: "medium", timeStyle: "short" });
    return span < 2 * 86400000 ? d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" }) : d.toLocaleDateString("fr-FR", { day: "2-digit", month: "short" });
  }
  function toast(msg) {
    var t = $("toast"); t.textContent = msg; t.classList.add("show");
    clearTimeout(toast._h); toast._h = setTimeout(function () { t.classList.remove("show"); }, 3500);
  }

  function api(path, opts) {
    opts = opts || {};
    var headers = { "Accept": "application/json" };
    if (opts.body !== undefined) headers["Content-Type"] = "application/json";
    if (opts.method && opts.method !== "GET" && state.csrf) headers["X-CSRF-Token"] = state.csrf;
    return fetch(path, { method: opts.method || "GET", headers: headers, credentials: "same-origin", body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined })
      .then(function (r) {
        if (r.status === 401 && path !== "/api/auth/login") { showLogin(); throw new Error("Session expirée : reconnectez-vous"); }
        return r.json().catch(function () { return {}; }).then(function (data) {
          if (!r.ok) {
            var d = data && data.detail;
            if (Array.isArray(d)) d = d.map(function (x) { return (x.loc ? x.loc.slice(1).join(".") + " : " : "") + x.msg; }).join(" ; ");
            throw new Error(d || ("Erreur " + r.status));
          }
          return data;
        });
      });
  }

  // ---------------- theme ----------------
  function applyTheme(t) {
    if (t) document.documentElement.setAttribute("data-theme", t); else document.documentElement.removeAttribute("data-theme");
  }
  try { applyTheme(localStorage.getItem("hf-theme") || "dark"); } catch (e) { applyTheme("dark"); }
  function toggleTheme() {
    var cur = document.documentElement.getAttribute("data-theme");
    var dark = cur ? cur === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
    var next = dark ? "light" : "dark";
    applyTheme(next);
    try { localStorage.setItem("hf-theme", next); } catch (e) { /* ignore */ }
    render();
  }

  // ---------------- auth ----------------
  function showLogin() {
    stopPolling();
    state.csrf = null;
    $("app-view").classList.add("hidden");
    $("login-view").classList.remove("hidden");
    $("lg-user").focus();
  }
  function showApp() {
    $("login-view").classList.add("hidden");
    $("app-view").classList.remove("hidden");
    api("/api/strategies").then(function (m) { state.meta = m; renderStrategies(); });
    refresh();
    startPolling();
  }
  $("login-form").addEventListener("submit", function (ev) {
    ev.preventDefault();
    $("lg-error").textContent = "";
    api("/api/auth/login", { method: "POST", body: { username: $("lg-user").value, password: $("lg-pass").value, totp: $("lg-totp").value || null } })
      .then(function (r) { state.csrf = r.csrf; state.user = r; $("lg-pass").value = ""; $("lg-totp").value = ""; showApp(); })
      .catch(function (e) { $("lg-error").textContent = e.message; });
  });
  $("logout-btn").addEventListener("click", function () {
    api("/api/auth/logout", { method: "POST", body: {} }).finally(showLogin);
  });
  $("theme-btn").addEventListener("click", toggleTheme);

  // ---------------- tabs & polling ----------------
  Array.prototype.forEach.call(document.querySelectorAll(".tab-btn"), function (b) {
    b.addEventListener("click", function () { selectTab(b.getAttribute("data-tab")); });
  });
  function selectTab(tab) {
    state.tab = tab;
    Array.prototype.forEach.call(document.querySelectorAll(".tab-btn"), function (b) { b.setAttribute("aria-selected", String(b.getAttribute("data-tab") === tab)); });
    Array.prototype.forEach.call(document.querySelectorAll(".tab"), function (s) { s.classList.toggle("hidden", s.id !== "tab-" + tab); });
    refresh();
  }
  Array.prototype.forEach.call(document.querySelectorAll("#range button"), function (b) {
    b.addEventListener("click", function () {
      state.days = Number(b.getAttribute("data-days"));
      Array.prototype.forEach.call(document.querySelectorAll("#range button"), function (x) { x.setAttribute("aria-pressed", String(x === b)); });
      refresh();
    });
  });
  function startPolling() { stopPolling(); state.timer = setInterval(function () { if (!document.hidden) refresh(); }, 10000); }
  function stopPolling() { if (state.timer) clearInterval(state.timer); state.timer = null; }

  function refresh() {
    var jobs = [api("/api/overview").then(function (o) { state.overview = o; })];
    if (state.tab === "dashboard") {
      jobs.push(api("/api/equity?days=" + state.days).then(function (e) { state.equity = e; }));
      jobs.push(api("/api/fills?limit=30").then(function (f) { state.fills = f; }));
      jobs.push(api("/api/alerts?limit=15").then(function (a) { state.alerts = a; }));
    }
    if (state.tab === "journal") jobs.push(api("/api/journal?limit=200").then(function (j) { state.journal = j; }));
    return Promise.all(jobs).then(render).catch(function (e) { if (e.message.indexOf("Session") !== 0) toast(e.message); });
  }

  // ---------------- rendering ----------------
  function render() {
    var o = state.overview;
    if (!o) return;
    renderHeader(o);
    renderBanners(o);
    if (state.tab === "dashboard") renderDashboard(o);
    if (state.tab === "bots") renderBots(o);
    if (state.tab === "journal") renderJournal();
    if (state.tab === "settings") renderSettings(o);
    $("last-update").textContent = "Mis à jour " + new Date().toLocaleTimeString("fr-FR");
  }

  function modeLabel(o) {
    if (o.mode === "simulation") return "SIMULATION";
    if (o.mode === "paper") return "PAPIER (prix MT5)";
    return o.account && o.account.account_type === "real" ? "MT5 · COMPTE RÉEL" : "MT5 · DÉMO";
  }
  function renderHeader(o) {
    var b = $("mode-badge");
    b.textContent = modeLabel(o);
    b.classList.toggle("real", o.mode === "mt5" && o.account && o.account.account_type === "real");
    var c = $("conn-badge"); c.textContent = "";
    var ok = o.account && o.account.connected;
    var dotCls = !ok ? "bad" : (o.mode === "mt5" && !o.account.algo_trading_enabled ? "warn" : "ok");
    c.appendChild(el("span", { cls: "dot " + dotCls }));
    c.appendChild(el("span", { text: ok ? (o.feed === "mt5" ? "MT5 connecté" : "Simulation") : "MT5 déconnecté" }));
  }

  function renderBanners(o) {
    var box = $("banners"); box.textContent = "";
    if (o.kill_switch.engaged) {
      box.appendChild(el("div", { cls: "banner critical", role: "alert" }, [
        el("strong", { text: "Arrêt d'urgence actif." }), el("span", { text: o.kill_switch.reason || "" }),
        el("span", { cls: "spacer" }),
        el("button", { cls: "btn small", type: "button", onclick: resetKill, text: "Réarmer…" }),
      ]));
    }
    if (o.synthetic) box.appendChild(el("div", { cls: "banner warning" }, [el("strong", { text: "Mode simulation." }), el("span", { text: "Prix simulés : aucun ordre n'est envoyé et les résultats ne disent rien des vrais marchés. Installez MT5 + le paquet MetaTrader5 sur Windows pour trader." })]));
    if (o.mode === "paper") box.appendChild(el("div", { cls: "banner" }, [el("strong", { text: "Mode papier." }), el("span", { text: "Prix réels de MT5, exécutions simulées : rien n'est envoyé au broker." })]));
    if (o.mode === "mt5" && o.account && o.account.connected && !o.account.algo_trading_enabled) box.appendChild(el("div", { cls: "banner warning" }, [el("strong", { text: "Algo Trading désactivé dans MT5." }), el("span", { text: "Cliquez sur le bouton « Algo Trading » du terminal pour autoriser les ordres." })]));
    if (!o.engine.alive) box.appendChild(el("div", { cls: "banner warning" }, [el("strong", { text: "Moteur arrêté." }), el("span", { text: o.engine.last_error || "" })]));
    else if (o.engine.last_error) box.appendChild(el("div", { cls: "banner warning" }, [el("strong", { text: "Dernière erreur moteur :" }), el("span", { text: o.engine.last_error })]));
  }

  function tile(label, value, delta, deltaCls, hero) {
    return el("div", { cls: "tile" + (hero ? " hero" : "") }, [
      el("div", { cls: "label", text: label }), el("div", { cls: "value", text: value }),
      delta ? el("div", { cls: "delta " + (deltaCls || "muted"), text: delta }) : null,
    ]);
  }
  function upDown(v) { return v > 0 ? "up" : v < 0 ? "down" : "muted"; }

  function renderDashboard(o) {
    var t = $("tiles"); t.textContent = "";
    var running = o.bots.filter(function (b) { return b.running; }).length;
    t.appendChild(tile("Valeur du portefeuille", money(o.nav), "Capital alloué " + money(o.capital), "muted", true));
    t.appendChild(tile("Résultat du jour", signed(o.pnl_today), o.capital ? pct(o.pnl_today / o.capital) : "", upDown(o.pnl_today)));
    t.appendChild(tile("Résultat total", signed(o.pnl_total), o.capital ? pct(o.pnl_total / o.capital) : "", upDown(o.pnl_total)));
    t.appendChild(tile("Drawdown", pct(o.drawdown), "Arrêt d'urgence à " + pct(o.limits.max_drawdown_pct, 0), o.drawdown > o.limits.drawdown_reduce_only_pct * 0.75 ? "down" : "muted"));
    t.appendChild(tile("Exposition", num(o.gross_exposure, 2) + "×", "nette " + num(o.net_exposure, 2) + "×", "muted"));
    t.appendChild(tile("Bots actifs", String(running), o.bots.length + " configuré(s)", "muted"));

    var eq = state.equity || [];
    var series = [{ name: "Portefeuille (plateforme)", cls: "s1", area: true, points: eq.map(function (p) { return { t: p.t, v: p.nav }; }) }];
    var broker = eq.filter(function (p) { return p.broker_equity !== null && p.broker_equity !== undefined; });
    var leg = $("equity-legend"); leg.textContent = "";
    if (broker.length > 1) {
      series[0].area = false;
      series.push({ name: "Équité du compte MT5", cls: "s2", points: broker.map(function (p) { return { t: p.t, v: p.broker_equity }; }) });
      leg.appendChild(el("span", {}, [el("span", { cls: "key k1" }), "Portefeuille (plateforme)"]));
      leg.appendChild(el("span", {}, [el("span", { cls: "key k2" }), "Équité MT5 (inclut swaps et autres positions)"]));
    }
    Charts.line($("equity-chart"), { series: series, format: function (v, short) { return money(v, short); }, dateFormat: axisDate, label: "Valeur du portefeuille", emptyText: "La courbe apparaîtra après quelques minutes de fonctionnement" });
    Charts.line($("dd-chart"), { series: [{ name: "Drawdown", cls: "neg", area: true, points: eq.map(function (p) { return { t: p.t, v: -(p.drawdown || 0) }; }) }], zeroBaseline: true, height: 200, format: function (v) { return pct(v, 1); }, dateFormat: axisDate, label: "Drawdown" });
    Charts.bars($("bots-chart"), { items: o.bots.map(function (b) { return { label: b.name, value: b.pnl, detail: b.strategy_label + " · " + b.symbols.join("/") }; }), format: signed, label: "Résultat par bot", emptyText: "Créez un bot dans l'onglet Bots" });

    renderAccount(o);
    var names = {}; o.bots.forEach(function (b) { names[b.id] = b.name; });
    table($("positions"), ["Bot", "Actif", "Sens", "Lots", "Prix moyen", "Prix actuel", "Exposition", "Résultat latent"],
      o.positions.map(function (p) { return [names[p.bot_id] || p.bot_id, p.symbol, p.side, num(p.lots, 2), num(p.avg_price, 5), num(p.mark, 5), money(p.notional), { text: signed(p.unrealized), cls: upDown(p.unrealized) }]; }),
      "Aucune position ouverte", [3, 4, 5, 6, 7]);
    table($("fills"), ["Heure", "Bot", "Actif", "Sens", "Prix", "Glissement", "Frais"],
      (state.fills || []).map(function (f) { return [dt(f.t), names[f.strategy_id] || f.strategy_id, f.symbol, f.side === "buy" ? "achat" : "vente", num(f.actual_price, 5), f.slippage_bps === null ? "—" : num(f.slippage_bps, 1) + " pb", money(f.fee)]; }),
      "Aucune exécution", [4, 5, 6]);
    var al = $("alerts"); al.textContent = "";
    var alerts = state.alerts || [];
    if (!alerts.length) al.appendChild(el("div", { cls: "empty", text: "Aucune alerte" }));
    alerts.forEach(function (a) {
      var sev = a.severity === "critical" || a.severity === "high" ? "bad" : a.severity === "low" ? "" : "warn";
      al.appendChild(el("div", { cls: "banner" }, [el("span", { cls: "dot " + sev }), el("span", { cls: "muted", text: dt(a.t) }), el("span", { text: a.message || "" })]));
    });
  }

  function renderAccount(o) {
    var a = o.account || {}, box = $("account"); box.textContent = "";
    if (!a.connected) { box.appendChild(el("p", { cls: "secondary", text: a.error || "Non connecté" })); return; }
    var rows = [
      ["Type de compte", { demo: "Démo", real: "RÉEL", contest: "Concours", simulation: "Simulation" }[a.account_type] || a.account_type],
      ["Broker", a.company || a.server || "—"], ["Compte", a.login ? String(a.login) : "—"], ["Solde", money(a.balance)], ["Équité", money(a.equity)],
      ["Marge libre", money(a.margin_free)], ["Levier", a.leverage ? "1:" + a.leverage : "—"], ["Mode de compte", a.margin_mode === "hedging" ? "Hedging" : a.margin_mode === "netting" ? "Netting" : (a.margin_mode || "—")],
      ["Algo Trading", a.algo_trading_enabled ? "activé" : "désactivé"],
    ];
    table(box, ["", ""], rows.filter(function (r) { return r[1] !== undefined; }), "", [1]);
  }

  function table(container, headers, rows, emptyText, rightCols) {
    container.textContent = "";
    if (!rows.length) { container.appendChild(el("div", { cls: "empty", text: emptyText })); return; }
    rightCols = rightCols || [];
    var thead = el("thead", {}, [el("tr", {}, headers.map(function (h, i) { return el("th", { cls: rightCols.indexOf(i) >= 0 ? "r" : "", text: h }); }))]);
    var tbody = el("tbody", {}, rows.map(function (r) {
      return el("tr", {}, r.map(function (c, i) {
        var cls = (rightCols.indexOf(i) >= 0 ? "r " : "") + (c && c.cls ? c.cls : "") + (c && c.wrap ? " wrap" : "");
        return el("td", { cls: cls.trim(), text: c && typeof c === "object" ? c.text : (c === null || c === undefined ? "—" : String(c)) });
      }));
    }));
    container.appendChild(el("table", {}, [thead, tbody]));
  }

  // ---------------- bots ----------------
  function renderBots(o) {
    var box = $("bots"); box.textContent = "";
    if (!o.bots.length) box.appendChild(el("div", { cls: "card empty" }, [el("p", { text: "Aucun bot pour l'instant." }), el("button", { cls: "btn primary", type: "button", onclick: function () { openBotForm(null); }, text: "Créer mon premier bot" })]));
    o.bots.forEach(function (b) {
      var status = b.running ? (b.halted_reason ? ["warn", "Suspendu"] : ["ok", "Actif"]) : b.status === "error" ? ["bad", "Erreur"] : ["", "Arrêté"];
      var dirs = (state.meta && state.meta.directions) || {};
      var tfs = (state.meta && state.meta.timeframes) || {};
      box.appendChild(el("div", { cls: "card bot-card" }, [
        el("div", { cls: "card-head" }, [el("h3", { text: b.name }), el("span", { cls: "badge" }, [el("span", { cls: "dot " + status[0] }), status[1]])]),
        el("div", { cls: "bot-meta" }, [
          el("span", { cls: "badge clip", text: b.strategy_label, title: b.strategy_label }), el("span", { cls: "badge", text: b.symbols.join(" / ") }),
          el("span", { cls: "badge", text: tfs[b.timeframe] || b.timeframe }), el("span", { cls: "badge", text: dirs[b.direction] || b.direction }),
          el("span", { cls: "badge", text: "risque " + num(b.risk_per_trade_pct, 2) + " %" }),
        ]),
        el("div", { cls: "bot-msg", text: b.halted_reason ? "Nouvelles entrées bloquées : " + b.halted_reason : (b.message || "") }),
        el("div", { cls: "bot-stats" }, [
          el("div", {}, [el("div", { cls: "k", text: "Résultat" }), el("div", { cls: "v " + upDown(b.pnl), text: signed(b.pnl) })]),
          el("div", {}, [el("div", { cls: "k", text: "Clôtures" }), el("div", { cls: "v", text: String(b.closed_trades) })]),
          el("div", {}, [el("div", { cls: "k", text: "Réussite" }), el("div", { cls: "v", text: b.win_rate === null ? "—" : pct(b.win_rate, 0) })]),
        ]),
        el("div", { cls: "actions" }, b.running ? [
          el("button", { cls: "btn danger small", type: "button", onclick: function () { stopBot(b); }, text: "Arrêter" }),
          el("button", { cls: "btn small", type: "button", onclick: function () { runBacktest("/api/bots/" + b.id + "/backtest", null, b.name); }, text: "Backtest" }),
        ] : [
          el("button", { cls: "btn primary small", type: "button", onclick: function () { startBot(b); }, text: "Démarrer" }),
          el("button", { cls: "btn small", type: "button", onclick: function () { runBacktest("/api/bots/" + b.id + "/backtest", null, b.name); }, text: "Backtest" }),
          el("button", { cls: "btn small", type: "button", onclick: function () { openBotForm(b); }, text: "Modifier" }),
          el("button", { cls: "btn ghost small", type: "button", onclick: function () { deleteBot(b); }, text: "Supprimer" }),
        ]),
      ]));
    });
  }

  function startBot(b) {
    var o = state.overview;
    var real = o.mode === "mt5" && o.account && o.account.account_type === "real";
    var text = o.mode === "mt5" ? (real ? "ATTENTION : ce bot enverra des ordres avec de l'argent réel." : "Ce bot enverra des ordres sur votre compte MT5 de démo.") : "Ce bot tournera en " + (o.mode === "paper" ? "mode papier (aucun ordre envoyé)." : "simulation.");
    confirmDialog({ title: "Démarrer « " + b.name + " » ?", text: text, ok: "Démarrer", danger: real }).then(function (r) {
      if (!r) return;
      return api("/api/bots/" + b.id + "/start", { method: "POST", body: {} }).then(function () { toast("Bot démarré"); refresh(); });
    }).catch(function (e) { toast(e.message); });
  }
  function stopBot(b) {
    confirmDialog({ title: "Arrêter « " + b.name + " » ?", text: "Par défaut, ses positions sont fermées au marché.", ok: "Arrêter", danger: true,
      fields: [{ id: "close", type: "checkbox", label: "Fermer ses positions", checked: true }] }).then(function (r) {
      if (!r) return;
      return api("/api/bots/" + b.id + "/stop", { method: "POST", body: { close_positions: r.close } }).then(function () { toast("Bot arrêté"); refresh(); });
    }).catch(function (e) { toast(e.message); });
  }
  function deleteBot(b) {
    confirmDialog({ title: "Supprimer « " + b.name + " » ?", text: "Son historique reste dans le journal d'audit.", ok: "Supprimer", danger: true }).then(function (r) {
      if (!r) return;
      return api("/api/bots/" + b.id, { method: "DELETE" }).then(function () { toast("Bot supprimé"); refresh(); });
    }).catch(function (e) { toast(e.message); });
  }
  $("new-bot-btn").addEventListener("click", function () { openBotForm(null); });

  function renderStrategies() {
    var m = state.meta, box = $("strategies");
    box.textContent = "";
    $("app-version").textContent = "Version " + m.version + " · " + m.strategies.length + " stratégies";
    var yours = function (s) { return s.origin ? 0 : 1; };
    m.strategies.slice().sort(function (a, b) { return yours(a) - yours(b); }).forEach(function (s) {
      var tfs = s.timeframes.map(function (k) { return m.timeframes[k] || k; }).join(", ");
      box.appendChild(el("div", { cls: "card strategy-card" }, [
        el("h3", { text: s.label }),
        s.origin ? el("div", { cls: "bot-meta" }, [el("span", { cls: "badge accent", text: s.origin })]) : null,
        el("p", { cls: "help", text: s.description }),
        el("p", { cls: "muted small", text: (s.n_symbols === 2 ? "2 actifs" : "1 actif") + " · unités de temps : " + tfs }),
        el("div", { cls: "actions" }, [el("button", { cls: "btn primary small", type: "button", onclick: function () { openBotForm(null, s.key); }, text: "Créer un bot avec cette stratégie" })]),
      ]));
    });
  }

  // ---------- bot form & symbol picker ----------
  var picks = [];
  function strategyMeta(key) { return (state.meta.strategies || []).filter(function (s) { return s.key === key; })[0]; }

  function openBotForm(bot, strategyKey) {
    if (!state.meta) { toast("Chargement…"); return; }
    state.editing = bot;
    $("bot-title").textContent = bot ? "Modifier « " + bot.name + " »" : "Nouveau bot";
    $("bot-error").textContent = "";
    var sel = $("bot-strategy"); sel.textContent = "";
    state.meta.strategies.forEach(function (s) { sel.appendChild(el("option", { value: s.key, text: s.label })); });
    var dir = $("bot-dir"); dir.textContent = "";
    Object.keys(state.meta.directions).forEach(function (k) { dir.appendChild(el("option", { value: k, text: state.meta.directions[k] })); });
    $("bot-name").value = bot ? bot.name : "";
    sel.value = bot ? bot.strategy : (strategyKey || "trend");
    dir.value = bot ? bot.direction : "both";
    $("bot-risk").value = bot ? bot.risk_per_trade_pct : 0.5;
    $("bot-maxpos").value = bot ? bot.max_position_pct : 20;
    picks = bot ? bot.symbols.slice() : [];
    onStrategyChange(bot ? bot.params : null, bot ? bot.timeframe : null);
    $("dlg-bot").showModal();
  }
  $("bot-strategy").addEventListener("change", function () { onStrategyChange(null); });
  $("bot-cancel").addEventListener("click", function () { $("dlg-bot").close(); });

  function onStrategyChange(params, timeframe) {
    var s = strategyMeta($("bot-strategy").value);
    $("bot-strategy-help").textContent = s.description;
    picks = picks.slice(0, s.n_symbols);
    if (s.key === "pair") $("bot-dir").value = "both";
    var tf = $("bot-tf"), keep = timeframe || tf.value;
    tf.textContent = "";
    s.timeframes.forEach(function (k) { tf.appendChild(el("option", { value: k, text: state.meta.timeframes[k] || k })); });
    tf.value = s.timeframes.indexOf(keep) >= 0 ? keep : s.default_timeframe;
    var box = $("pickers"); box.textContent = "";
    for (var i = 0; i < s.n_symbols; i++) box.appendChild(symbolPicker(i, s.n_symbols));
    var pbox = $("bot-params"); pbox.textContent = "";
    var group = null;
    Object.keys(s.params).forEach(function (k) {
      var p = s.params[k], value = params && params[k] !== undefined ? params[k] : p.default;
      if (p.group && p.group !== group) { group = p.group; pbox.appendChild(el("h4", { cls: "param-group", text: group })); }
      if (p.kind === "bool") {
        var cb = el("input", { type: "checkbox", id: "param-" + k, "data-param": k });
        cb.checked = Number(value) >= 0.5;
        pbox.appendChild(el("div", { cls: "check" }, [cb, el("label", { "for": "param-" + k, text: p.label })]));
        return;
      }
      var input = el("input", { type: "number", id: "param-" + k, "data-param": k, min: p.min, max: p.max, step: "any" });
      input.value = value;
      pbox.appendChild(el("div", {}, [el("label", { "for": "param-" + k, text: p.label }), input, el("div", { cls: "help", text: "entre " + p.min + " et " + p.max })]));
    });
  }

  function symbolPicker(slot, n) {
    var wrap = el("div", {});
    var title = n === 2 ? (slot === 0 ? "Actif 1 (acheté quand le rapport est bas)" : "Actif 2 (couverture)") : "Actif à trader";
    wrap.appendChild(el("label", { text: title }));
    var cat = "";
    var chips = el("div", { cls: "chips" });
    var cats = [["", "Tous"]].concat(Object.keys(state.meta.categories).map(function (k) { return [k, state.meta.categories[k].split(" (")[0]]; }));
    var search = el("input", { type: "search", placeholder: "Rechercher : or, XAU, NAS100, BTC, EURUSD…", "aria-label": "Rechercher un actif" });
    var results = el("div", { cls: "results" });
    var picked = el("div", { cls: "picked" });
    cats.forEach(function (c) {
      var b = el("button", { cls: "chip", type: "button", "aria-pressed": String(c[0] === ""), text: c[1] });
      b.addEventListener("click", function () {
        cat = c[0];
        Array.prototype.forEach.call(chips.children, function (x) { x.setAttribute("aria-pressed", String(x === b)); });
        load();
      });
      chips.appendChild(b);
    });
    var h;
    search.addEventListener("input", function () { clearTimeout(h); h = setTimeout(load, 200); });
    function load() {
      var q = search.value.trim();
      var alias = { "or": "XAU", "gold": "XAU", "argent": "XAG", "nasdaq": "NAS", "petrole": "OIL", "pétrole": "OIL", "bitcoin": "BTC", "ethereum": "ETH", "dax": "GER", "dow": "US30", "sp500": "US500" };
      q = alias[q.toLowerCase()] || q;
      api("/api/symbols?q=" + encodeURIComponent(q) + "&category=" + encodeURIComponent(cat)).then(function (list) {
        results.textContent = "";
        if (!list.length) results.appendChild(el("div", { cls: "empty", text: "Aucun actif trouvé chez votre broker" }));
        list.slice(0, 80).forEach(function (s) {
          results.appendChild(el("button", { cls: "result", type: "button", onclick: function () { choose(s.name); } }, [
            el("span", {}, [el("strong", { text: s.name }), " ", el("span", { cls: "muted", text: s.description })]),
            el("span", { cls: "muted", text: s.category_label.split(" (")[0] }),
          ]));
        });
      }).catch(function (e) { results.textContent = e.message; });
    }
    function choose(name) {
      picks[slot] = name;
      showPicked();
    }
    function showPicked() {
      picked.textContent = "";
      if (!picks[slot]) { picked.appendChild(el("span", { cls: "muted", text: "Aucun actif choisi" })); return; }
      picked.appendChild(el("strong", { text: picks[slot] }));
      api("/api/symbols/" + encodeURIComponent(picks[slot])).then(function (d) {
        picked.appendChild(el("div", { cls: "help", text: (d.description || "") + " · prix " + num(d.price, 5) + " · spread " + num(d.spread_bps, 1) + " pb · taille minimale du broker ≈ " + money(d.min_trade_notional) + " d'exposition" }));
      }).catch(function () { /* detail is optional */ });
    }
    wrap.appendChild(chips); wrap.appendChild(search); wrap.appendChild(results); wrap.appendChild(picked);
    load(); showPicked();
    return wrap;
  }

  function botPayload() {
    var params = {};
    Array.prototype.forEach.call(document.querySelectorAll("#bot-params input"), function (i) { params[i.getAttribute("data-param")] = i.type === "checkbox" ? (i.checked ? 1 : 0) : Number(i.value); });
    return {
      name: $("bot-name").value.trim() || ($("bot-strategy").selectedOptions[0].textContent + " " + picks.join("/")),
      strategy: $("bot-strategy").value, symbols: picks.filter(Boolean), timeframe: $("bot-tf").value, direction: $("bot-dir").value,
      risk_per_trade_pct: Number($("bot-risk").value), max_position_pct: Number($("bot-maxpos").value), params: params,
    };
  }
  $("bot-form").addEventListener("submit", function (ev) {
    ev.preventDefault();
    var body = botPayload(), editing = state.editing;
    api(editing ? "/api/bots/" + editing.id : "/api/bots", { method: editing ? "PUT" : "POST", body: body })
      .then(function () { $("dlg-bot").close(); toast(editing ? "Bot modifié" : "Bot créé : démarrez-le quand vous êtes prêt"); selectTab("bots"); })
      .catch(function (e) { $("bot-error").textContent = e.message; });
  });
  $("bot-backtest").addEventListener("click", function () { runBacktest("/api/backtest", botPayload(), null); });

  function runBacktest(path, body, name) {
    var content = $("bt-content"); content.textContent = "";
    $("bt-title").textContent = "Backtest" + (name ? " – " + name : "");
    content.appendChild(el("p", { cls: "secondary", text: "Calcul en cours sur l'historique… (quelques secondes)" }));
    $("dlg-backtest").showModal();
    api(path, { method: "POST", body: body || {} }).then(function (r) {
      content.textContent = "";
      if (r.synthetic) content.appendChild(el("div", { cls: "banner warning" }, [el("strong", { text: "Données simulées." }), el("span", { text: "Ce résultat teste la mécanique, pas la rentabilité." })]));
      content.appendChild(el("p", { cls: "muted", text: r.bars + " bougies, du " + dt(Date.parse(r.from), false) + " au " + dt(Date.parse(r.to), false) + ". Coûts (spread + frais) inclus ; swaps non inclus." }));
      var tiles = el("div", { cls: "tiles" });
      tiles.appendChild(tile("Rendement", pct(r.metrics.total_return), "annualisé " + pct(r.metrics.cagr), upDown(r.metrics.total_return)));
      tiles.appendChild(tile("Drawdown max", pct(r.metrics.max_drawdown)));
      tiles.appendChild(tile("Sharpe", num(r.metrics.sharpe, 2), "probabilité > 0 : " + pct(r.metrics.psr, 0)));
      tiles.appendChild(tile("Trades clôturés", String(r.closed_trades), r.win_rate === null ? "" : "réussite " + pct(r.win_rate, 0)));
      tiles.appendChild(tile("Frais payés", money(r.fees), r.rejected_orders ? r.rejected_orders + " ordre(s) refusé(s)" : ""));
      content.appendChild(tiles);
      var chart = el("div", { cls: "chart" });
      content.appendChild(chart);
      Charts.line(chart, { series: [{ name: "Valeur simulée", cls: "s1", area: true, points: r.equity.map(function (p) { return { t: p.t, v: p.nav }; }) }], format: function (v, s) { return money(v, s); }, dateFormat: axisDate, label: "Courbe du backtest", height: 220 });
      var mins = Object.keys(r.min_trade_notional || {}).map(function (s) { return s + " ≈ " + money(r.min_trade_notional[s]); }).join(", ");
      content.appendChild(el("p", { cls: "help", text: "Taille minimale d'un ordre chez le broker (0,01 lot en général) : " + mins + ". Avec un petit capital et un risque faible, certains ordres peuvent être trop petits et refusés." }));
      content.appendChild(el("p", { cls: "help", text: "Un bon backtest ne garantit rien. Testez ensuite plusieurs semaines en démo avant tout argent réel." }));
    }).catch(function (e) { content.textContent = ""; content.appendChild(el("p", { cls: "error", text: e.message })); });
  }
  $("bt-close").addEventListener("click", function () { $("dlg-backtest").close(); });

  // ---------------- confirm dialog ----------------
  function confirmDialog(opts) {
    return new Promise(function (resolve) {
      $("cf-title").textContent = opts.title; $("cf-text").textContent = opts.text || ""; $("cf-error").textContent = "";
      var f = $("cf-fields"); f.textContent = "";
      (opts.fields || []).forEach(function (fd) {
        if (fd.type === "checkbox") {
          var cb = el("input", { type: "checkbox", id: "cf-" + fd.id }); cb.checked = !!fd.checked; cb.className = "";
          cb.style.width = "auto"; cb.style.minHeight = "0";
          f.appendChild(el("label", {}, [cb, " " + fd.label]));
        } else {
          f.appendChild(el("label", { "for": "cf-" + fd.id, text: fd.label }));
          f.appendChild(el("input", { id: "cf-" + fd.id, type: fd.type || "text", autocomplete: fd.autocomplete || "off", inputmode: fd.inputmode || "text" }));
        }
      });
      var ok = $("cf-ok"); ok.textContent = opts.ok || "Confirmer"; ok.className = "btn " + (opts.danger ? "danger" : "primary");
      var dlg = $("dlg-confirm");
      function done(val) { dlg.close(); $("cf-form").removeEventListener("submit", onSubmit); $("cf-cancel").removeEventListener("click", onCancel); resolve(val); }
      function onSubmit(ev) {
        ev.preventDefault();
        var out = {};
        (opts.fields || []).forEach(function (fd) { var i = $("cf-" + fd.id); out[fd.id] = fd.type === "checkbox" ? i.checked : i.value; });
        if (opts.validate) { var err = opts.validate(out); if (err) { $("cf-error").textContent = err; return; } }
        done(out);
      }
      function onCancel() { done(null); }
      $("cf-form").addEventListener("submit", onSubmit);
      $("cf-cancel").addEventListener("click", onCancel);
      dlg.showModal();
    });
  }

  var secretFields = [{ id: "password", type: "password", label: "Mot de passe", autocomplete: "current-password" }, { id: "totp", label: "Code 2FA (si activé)", inputmode: "numeric", autocomplete: "one-time-code" }];

  $("kill-btn").addEventListener("click", function () {
    confirmDialog({ title: "Arrêt d'urgence", text: "Toutes les positions de la plateforme seront fermées au marché et plus aucun ordre ne sera envoyé jusqu'au réarmement.", ok: "Tout arrêter", danger: true,
      fields: [{ id: "reason", label: "Raison" }], validate: function (v) { return v.reason.trim() ? "" : "Indiquez une raison"; } })
      .then(function (r) { if (!r) return; return api("/api/engine/kill", { method: "POST", body: { reason: r.reason } }).then(function () { toast("Arrêt d'urgence activé"); refresh(); }); })
      .catch(function (e) { toast(e.message); });
  });
  function resetKill() {
    confirmDialog({ title: "Réarmer", text: "Vérifiez d'abord la cause de l'arrêt. Les bots devront être redémarrés un par un.", ok: "Réarmer",
      fields: [{ id: "reason", label: "Ce que vous avez vérifié" }].concat(secretFields), validate: function (v) { return v.reason.trim().length >= 3 && v.password ? "" : "Raison et mot de passe requis"; } })
      .then(function (r) { if (!r) return; return api("/api/engine/reset-kill", { method: "POST", body: { reason: r.reason, password: r.password, totp: r.totp || null } }).then(function () { toast("Réarmé"); refresh(); }); })
      .catch(function (e) { toast(e.message); });
  }

  // ---------------- journal ----------------
  var ACTIONS = { login: "Connexion", login_failed: "Échec de connexion", bot_create: "Bot créé", bot_update: "Bot modifié", bot_delete: "Bot supprimé", bot_start: "Bot démarré", bot_resume: "Bot repris", bot_stop: "Bot arrêté",
    kill_switch: "Arrêt d'urgence", kill_switch_reset: "Réarmement", mode_change: "Changement de mode", capital_change: "Capital modifié", real_trading_unlock: "Trading réel déverrouillé", real_trading_lock: "Trading réel verrouillé",
    password_change: "Mot de passe changé", totp_enabled: "2FA activée" };
  function renderJournal() {
    table($("journal"), ["Date", "Type", "Qui", "Détail"], (state.journal || []).map(function (j) {
      var type = j.kind === "operator_action" ? (ACTIONS[j.action] || j.action) : j.kind === "alert" ? "Alerte (" + j.severity + ")" : j.kind === "kill_switch" ? "Arrêt d'urgence : " + j.state : "Risque : " + (j.event || "");
      var detail = j.reason || j.message || (j.bot && j.bot.name) || (j.bot_id || "") || (j.to ? "→ " + j.to : "") || "";
      return [dt(j.t), type, j.operator || j.source || "système", { text: String(detail), wrap: true }];
    }), "Journal vide");
  }

  // ---------------- settings ----------------
  var LIMIT_LABELS = { max_drawdown_pct: ["Perte max depuis le plus haut (arrêt d'urgence)", "pct"], drawdown_reduce_only_pct: ["Perte déclenchant le mode réduction seule", "pct"], max_daily_loss_pct: ["Perte max par jour", "pct"],
    max_position_pct_nav: ["Position max par actif", "pct"], max_gross_leverage: ["Levier brut max", "x"], max_net_leverage: ["Levier net max", "x"], max_cluster_net_pct_nav: ["Exposition max par famille d'actifs", "pct"],
    max_slippage_bps: ["Glissement estimé max", "bps"], max_orders_per_minute: ["Ordres max par minute", "n"], max_risk_per_trade_pct_nav: ["Risque max par trade", "pct"], jev_min_confidence: ["Confiance minimale du modèle de décision", "n"] };
  function renderSettings(o) {
    var ms = $("mode-select");
    Array.prototype.forEach.call(ms.options, function (opt) { opt.disabled = o.synthetic ? opt.value !== "simulation" : opt.value === "simulation"; });
    if (document.activeElement !== ms) ms.value = o.mode;
    var ci = $("capital-input"); if (document.activeElement !== ci) ci.value = Math.round(o.capital);
    var rs = $("real-status"); rs.textContent = "";
    rs.appendChild(el("p", { text: o.real_trading.unlocked ? "Trading réel DÉVERROUILLÉ." : "Trading réel verrouillé : seuls les comptes démo reçoivent des ordres." }));
    if (!o.real_trading.server_allows) rs.appendChild(el("p", { text: "Le serveur n'autorise pas le trading réel (variable HF_ALLOW_REAL_TRADING=1 requise sur le serveur). Recommandé : validez d'abord plusieurs semaines en démo." }));
    $("totp-status").textContent = state.user && state.user.totp_enabled ? "La 2FA est activée sur votre compte." : "La 2FA n'est pas activée : fortement recommandée si la plateforme est accessible en ligne.";
    var rows = Object.keys(LIMIT_LABELS).filter(function (k) { return o.limits[k] !== undefined; }).map(function (k) {
      var v = o.limits[k], kind = LIMIT_LABELS[k][1];
      return [LIMIT_LABELS[k][0], kind === "pct" ? pct(v, 1) : kind === "x" ? num(v, 2) + "×" : kind === "bps" ? num(v, 0) + " pb" : num(v, 2)];
    });
    table($("limits"), ["Limite", "Valeur"], rows, "", [1]);
  }
  function secretBody(prefix) { return { password: $(prefix + "-pass").value, totp: $(prefix + "-totp").value || null }; }
  function clearSecrets(prefix) { $(prefix + "-pass").value = ""; $(prefix + "-totp").value = ""; }
  $("mode-form").addEventListener("submit", function (ev) {
    ev.preventDefault(); $("mode-error").textContent = "";
    api("/api/engine/mode", { method: "POST", body: Object.assign({ mode: $("mode-select").value }, secretBody("mode")) })
      .then(function () { clearSecrets("mode"); toast("Mode changé"); refresh(); }).catch(function (e) { $("mode-error").textContent = e.message; });
  });
  $("capital-form").addEventListener("submit", function (ev) {
    ev.preventDefault(); $("capital-error").textContent = "";
    api("/api/engine/capital", { method: "POST", body: Object.assign({ capital: Number($("capital-input").value) }, secretBody("capital")) })
      .then(function () { clearSecrets("capital"); toast("Capital enregistré"); refresh(); }).catch(function (e) { $("capital-error").textContent = e.message; });
  });
  $("real-form").addEventListener("submit", function (ev) {
    ev.preventDefault(); $("real-error").textContent = "";
    var enable = ev.submitter && ev.submitter.getAttribute("data-enable") === "1";
    api("/api/engine/real-trading", { method: "POST", body: Object.assign({ enabled: enable, confirmation: $("real-confirm").value }, secretBody("real")) })
      .then(function (r) { clearSecrets("real"); $("real-confirm").value = ""; toast(r.unlocked ? "Trading réel déverrouillé" : "Trading réel verrouillé"); refresh(); })
      .catch(function (e) { $("real-error").textContent = e.message; });
  });
  $("pw-form").addEventListener("submit", function (ev) {
    ev.preventDefault(); $("pw-error").textContent = "";
    api("/api/auth/password", { method: "POST", body: { password: $("pw-cur").value, new_password: $("pw-new").value, totp: $("pw-totp").value || null } })
      .then(function () { toast("Mot de passe changé : reconnectez-vous"); showLogin(); }).catch(function (e) { $("pw-error").textContent = e.message; });
  });
  $("totp-begin-form").addEventListener("submit", function (ev) {
    ev.preventDefault(); $("totp-error").textContent = "";
    api("/api/auth/totp/begin", { method: "POST", body: { password: $("totp-pass").value } }).then(function (r) {
      $("totp-pass").value = "";
      var box = $("totp-secret"); box.textContent = "";
      box.appendChild(el("div", { text: "Clé : " + r.secret.replace(/(.{4})/g, "$1 ").trim() }));
      box.appendChild(el("div", { cls: "help", text: r.uri }));
      $("totp-enable-form").classList.remove("hidden");
    }).catch(function (e) { $("totp-error").textContent = e.message; });
  });
  $("totp-enable-form").addEventListener("submit", function (ev) {
    ev.preventDefault(); $("totp-error").textContent = "";
    api("/api/auth/totp/enable", { method: "POST", body: { code: $("totp-code").value } }).then(function () {
      $("totp-enable-form").classList.add("hidden"); $("totp-secret").textContent = "";
      if (state.user) state.user.totp_enabled = true;
      toast("2FA activée"); refresh();
    }).catch(function (e) { $("totp-error").textContent = e.message; });
  });

  // ---------------- boot ----------------
  api("/api/auth/me").then(function (r) { state.csrf = r.csrf; state.user = r; showApp(); }).catch(function () { showLogin(); });
})();
