"use client";

import { Calculator, Gauge as GaugeIcon, ListChecks } from "lucide-react";
import { useEffect, useState } from "react";
import { AppShell, useApp } from "@/components/app-shell";
import { Bullets, Gauge, Kv, LabelChip, Section, useAction, useLoad } from "@/components/app-ui";
import { Empty, Notice, Spinner } from "@/components/ui";
import { GATE_LABEL, appApi, money, n2, when, type Account, type GuardStatus, type PropProfile, type RiskGate } from "@/lib/app";

type Profile = PropProfile;

export function RiskView() {
  return (
    <AppShell title="Risque et garde-fou" subtitle="Limites de perte suivies en continu, taille de position calculée par des règles déterministes">
      <Risk />
    </AppShell>
  );
}

function Risk() {
  const { data: accounts } = useLoad<Account[]>("/api/app/accounts");
  const [account, setAccount] = useState("");
  useEffect(() => {
    if (!account && accounts?.length) setAccount(accounts[0].id);
  }, [accounts, account]);
  if (!accounts) return <Spinner />;
  if (!accounts.length) return <Empty icon={<GaugeIcon className="size-7" />} title="Aucun compte de trading">Déclarez votre compte et son solde de départ dans le Journal pour suivre vos limites.</Empty>;
  return (
    <div className="grid gap-5">
      <label className="field max-w-xs">
        <span>Compte</span>
        <select className="input" value={account} onChange={(e) => setAccount(e.target.value)}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}</select>
      </label>
      {account && (
        <div className="grid gap-5 lg:grid-cols-2">
          <Status key={account} account={account} accounts={accounts} />
          <Sizer account={account} />
        </div>
      )}
      <Profiles />
    </div>
  );
}

function Status({ account, accounts }: { account: string; accounts: Account[] }) {
  const { app } = useApp();
  const { data: s, error, reload } = useLoad<GuardStatus & { day_start: number }>(`/api/app/risk/status?account=${account}`);
  const { data: profiles } = useLoad<{ profiles: Profile[]; prop_guard: boolean }>("/api/app/risk/profiles");
  const a = accounts.find((x) => x.id === account);
  const [pp, setPp] = useState(a?.prop_profile ?? "");
  const { busy, run, note } = useAction();
  const setProfile = async (key: string) => {
    if (!a) return;
    const body = { label: a.label, broker: a.broker, server: a.server, login: a.login, kind: a.kind, server_winter_offset_h: a.server_winter_offset_h, server_dst_rule: a.server_dst_rule, currency: a.currency, starting_balance: a.starting_balance, prop_profile: key || null };
    if (await run(() => appApi(`/api/app/accounts/${a.id}`, "PUT", body), "Profil enregistré")) {
      setPp(key);
      reload();
    }
  };
  const cur = a?.currency ?? "USD";
  return (
    <Section title="État des limites" icon={<GaugeIcon className="size-4" />}>
      {error ? <Notice kind="warn">{error}</Notice> : !s ? <Spinner /> : (
        <div className="grid gap-4">
          <label className="field">
            <span>Règles appliquées</span>
            <select className="input" value={pp} disabled={busy} onChange={(e) => setProfile(e.target.value)}>
              <option value="">Mon plan de trading</option>
              {(profiles?.profiles ?? []).filter((p) => p.key !== "generic").map((p) => <option key={p.key} value={p.key} disabled={!app?.features.prop_guard}>{p.label}{p.verified_at ? "" : " (à vérifier)"}</option>)}
            </select>
          </label>
          {!app?.features.prop_guard && <p className="text-xs text-faint">Les profils de prop firm sont inclus à partir de l&apos;offre Pro Trader ; les limites de votre plan de trading s&apos;appliquent.</p>}
          {s.profile !== "generic" && !s.profile_verified && (
            <Notice kind="warn">Ce profil reprend les règles publiées par la prop firm à une date donnée : vérifiez-les dans votre contrat avant de vous y fier.</Notice>
          )}
          <Gauge label="Perte journalière utilisée" value={s.daily_used_pct} hint={s.limits.daily_room != null ? `Marge restante aujourd'hui : ${money(s.limits.daily_room, cur)}` : undefined} />
          <Gauge label="Perte maximale utilisée" value={s.max_used_pct} hint={s.limits.max_room != null ? `Marge restante avant le plancher : ${money(s.limits.max_room, cur)}` : undefined} />
          {s.alerts.length > 0 && <Notice kind="error">Seuil d&apos;alerte atteint ({s.alerts.map((x) => `${x.kind === "daily_loss" ? "perte journalière" : "perte maximale"} ${x.level} %`).join(", ")}). Arrêtez ou réduisez fortement votre exposition.</Notice>}
          <div>
            <Kv k="Solde" v={money(Number(s.state.balance), cur)} />
            <Kv k="Équité" v={money(Number(s.state.equity), cur)} />
            <Kv k="Solde initial" v={money(Number(s.state.initial_balance), cur)} />
            {s.limits.daily_limit != null && <Kv k="Limite journalière" v={money(s.limits.daily_limit, cur)} />}
            {s.limits.max_floor != null && <Kv k="Plancher de perte maximale" v={money(s.limits.max_floor, cur)} />}
            <Kv k="Risque ouvert (stops connus)" v={money(Number(s.state.open_risk), cur)} />
            {Number(s.state.open_risk_unknown) > 0 && <Kv k="Positions sans stop connu" v={String(s.state.open_risk_unknown)} />}
            <Kv k="Trades aujourd'hui" v={String(s.state.trades_today)} />
            <Kv k="Début de journée" v={when(s.day_start)} />
            <Kv k="Source" v={s.state.source === "snapshot" ? "EA Journal Sync (équité en direct)" : "journal (trades clôturés)"} />
          </div>
          {s.objectives && <Objectives o={s.objectives} cur={cur} />}
          {s.notes.length > 0 && <Bullets items={s.notes} />}
          {note}
        </div>
      )}
    </Section>
  );
}

function Sizer({ account }: { account: string }) {
  const [f, setF] = useState({ symbol: "XAUUSD", direction: "long", entry: "", stop: "", target: "", requested_lots: "" });
  const [res, setRes] = useState<RiskGate | null>(null);
  const { busy, run, note } = useAction();
  const num = (x: string) => (x.trim() === "" ? null : Number(x.replace(",", ".")));
  const go = async () => {
    const out = await run(() => appApi<RiskGate>("/api/app/risk/size", "POST", { symbol: f.symbol, direction: f.direction, entry: num(f.entry), stop: num(f.stop), target: num(f.target), requested_lots: num(f.requested_lots), account_id: account }));
    if (out) setRes(out);
  };
  const inp = (k: keyof typeof f, label: string) => (
    <label className="field"><span>{label}</span><input className="input" inputMode={k === "symbol" ? undefined : "decimal"} value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} /></label>
  );
  return (
    <Section title="Calculateur de taille" icon={<Calculator className="size-4" />}>
      <div className="grid grid-cols-2 gap-3">
        {inp("symbol", "Symbole")}
        <label className="field"><span>Sens</span><select className="input" value={f.direction} onChange={(e) => setF({ ...f, direction: e.target.value })}><option value="long">Achat</option><option value="short">Vente</option></select></label>
        {inp("entry", "Entrée")}
        {inp("stop", "Stop")}
        {inp("target", "Objectif (facultatif)")}
        {inp("requested_lots", "Lots envisagés (facultatif)")}
      </div>
      <p className="mt-2 text-xs text-faint">Futures : MNQ, NQ, MES, ES, MGC, GC, MCL… (sur un compte futures, « NQ » est le contrat, pas le CFD). Forex et CFD : XAUUSD, NAS100, EURUSD…</p>
      <button className="btn btn-primary btn-sm mt-4" disabled={busy || !f.entry || !f.stop} onClick={go}>Calculer</button>
      {note}
      {res && (
        <div className="mt-5 grid gap-3">
          <div className="flex items-center gap-2"><LabelChip map={GATE_LABEL} k={res.decision} /></div>
          <div>
            <Kv k="Taille maximale" v={`${n2(res.max_lots, res.futures ? 0 : 2)} ${res.futures ? "contrat(s)" : "lot(s)"}`} />
            <Kv k="Risque" v={`${money(res.risk_amount)} (${n2(res.risk_pct)} %)`} />
          </div>
          {res.violations.length > 0 && <Notice kind="error"><Bullets items={res.violations} /></Notice>}
          {res.warnings.length > 0 && <Notice kind="warn"><Bullets items={res.warnings} /></Notice>}
          <details className="text-sm text-muted">
            <summary className="cursor-pointer text-xs font-semibold uppercase tracking-wider text-faint">Règles appliquées</summary>
            <div className="mt-2"><Bullets items={res.rules_applied} /></div>
          </details>
          <p className="text-xs text-faint">Calcul déterministe (plan, limites du profil, valeur du point, annonces proches). Aucun ordre n&apos;est envoyé.</p>
        </div>
      )}
    </Section>
  );
}

const pct = (x: number | string | null | undefined) => (x == null ? "—" : x === "plan" ? "selon votre plan" : `${x} %`);
const k$ = (n: number) => `${Math.round(n / 1000)}K`;
const usd = (n?: number) => (n == null ? "—" : `${n.toLocaleString("fr-FR")} $`);
const MAX_TYPE: Record<string, string> = { static: "fixe", trailing: "suiveuse", trailing_eod: "suiveuse (fin de journée)" };
const CONS_BASE: Record<string, string> = { target: "de l'objectif", total_profit: "du profit total", positive_days: "des jours gagnants" };

const lossType = (p: Profile) =>
  `${MAX_TYPE[p.max_loss_type ?? "static"] ?? p.max_loss_type}${p.trailing_lock === "initial" ? ", bloquée au capital de départ" : p.trailing_lock === "initial_plus_100" ? ", bloquée à +100 $" : p.max_loss_type?.startsWith("trailing") ? ", sans blocage" : ""}`;

/** Profit target, trading days, best-day rule, contract cap: what an evaluation asks besides loss limits. */
function Objectives({ o, cur }: { o: NonNullable<GuardStatus["objectives"]>; cur: string }) {
  if (!o.target && !o.trading_days && !o.consistency && !o.max_contracts && !o.warnings.length) return null;
  return (
    <div className="grid gap-3 rounded-xl border border-white/5 bg-white/[0.02] p-4">
      <div className="text-xs font-semibold uppercase tracking-wider text-faint">Objectifs de l&apos;évaluation</div>
      {o.target && (
        <div>
          <div className="flex justify-between text-sm"><span className="text-muted">Objectif de profit</span><span className="num">{n2(o.target.progress_pct, 0)} % de {money(o.target.amount, cur)}</span></div>
          <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-white/5"><div className="h-full rounded-full bg-brand-400" style={{ width: `${Math.min(100, o.target.progress_pct)}%` }} /></div>
        </div>
      )}
      {o.trading_days && <Kv k="Jours de trading" v={`${o.trading_days.done} / ${o.trading_days.required} minimum`} />}
      {o.consistency && <Kv k="Meilleur jour" v={`${money(o.consistency.best_day, cur)} = ${n2(o.consistency.share_pct, 0)} % (limite ${o.consistency.limit_pct} %)`} />}
      {o.max_contracts != null && <Kv k="Plafond de contrats" v={`${o.max_contracts} minis (ou ${o.max_contracts * 10} micros)`} />}
      {o.warnings.length > 0 && <Notice kind="warn"><Bullets items={o.warnings} /></Notice>}
    </div>
  );
}

function Profiles() {
  const { data } = useLoad<{ profiles: Profile[] }>("/api/app/risk/profiles");
  if (!data) return null;
  const firms = data.profiles.filter((p) => p.key !== "generic");
  return (
    <Section title="Profils de prop firm" icon={<ListChecks className="size-4" />}>
      <div className="grid gap-4 md:grid-cols-2">
        {firms.map((p) => (
          <div key={p.key} className="rounded-xl border border-white/10 bg-white/[0.02] p-4 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-semibold">{p.label}</span>
              <span className="chip">{p.market === "futures" ? "Futures" : "CFD / forex"}</span>
              {p.verified_at ? <span className="chip chip-green">vérifié le {p.verified_at}</span> : <span className="chip chip-gold">à vérifier</span>}
            </div>
            <div className="mt-3">
              {p.sizes ? (
                <div className="overflow-x-auto">
                  <table className="table">
                    <thead><tr><th>Compte</th><th className="text-right">Perte max.</th><th className="text-right">Perte jour</th><th className="text-right">Objectif</th><th className="text-right">Contrats</th></tr></thead>
                    <tbody>
                      {Object.entries(p.sizes).map(([size, r]) => (
                        <tr key={size}><td>{k$(Number(size))}</td><td className="num text-right">{usd(r.max_loss)}</td><td className="num text-right">{usd(r.daily_loss)}</td><td className="num text-right">{usd(r.profit_target)}</td><td className="num text-right">{r.max_contracts ?? "—"}</td></tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <>
                  <Kv k="Perte journalière" v={pct(p.daily_loss_pct)} />
                  <Kv k="Perte maximale" v={p.max_loss_pct == null ? "—" : `${p.max_loss_pct} %, ${lossType(p)}`} />
                  <Kv k="Objectif" v={Array.isArray(p.profit_target_pct) ? p.profit_target_pct.map((x) => `${x} %`).join(" puis ") : pct(p.profit_target_pct as number | null)} />
                </>
              )}
              {p.sizes && <Kv k="Perte maximale" v={lossType(p)} />}
              {p.consistency && <Kv k="Régularité" v={`meilleur jour ≤ ${p.consistency.pct} % ${CONS_BASE[p.consistency.base] ?? ""}`} />}
              {p.min_trading_days != null && <Kv k="Jours minimum" v={String(p.min_trading_days)} />}
            </div>
            {p.notes && <p className="mt-2 text-xs text-gold-300">{p.notes}</p>}
            <p className="mt-2 text-xs text-faint">
              Relevé le {p.retrieved_at ?? "—"}{p.source && <> · <a href={p.source} target="_blank" rel="noopener noreferrer" className="text-brand-300 hover:underline">règlement officiel</a></>}
            </p>
          </div>
        ))}
      </div>
      <p className="mt-4 text-xs text-faint">
        Les règles des prop firms changent. Chaque profil porte sa source et sa date de relevé ; « à vérifier » signifie qu&apos;il n&apos;a pas encore été confronté au règlement en
        vigueur. En cas de doute, le garde-fou retient la lecture la plus prudente. Pour un compte futures, indiquez comme solde de départ la taille exacte (ex. 50000).
      </p>
    </Section>
  );
}
