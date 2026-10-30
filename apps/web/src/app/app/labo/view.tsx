"use client";

import { Activity, Dices, FlaskConical, GitCompare, Radio } from "lucide-react";
import { useState } from "react";
import { AppShell, Usage } from "@/components/app-shell";
import { Bullets, Kv, Section, useAction, useLoad } from "@/components/app-ui";
import { Notice } from "@/components/ui";
import { n2, appApi, tone, when, type Account } from "@/lib/app";

type Report = { id: string; kind: string; title: string; created_at?: number; body?: Record<string, unknown> } & Record<string, unknown>;
type Pctl = Record<string, number>;
const STRATEGIES: [string, string][] = [["ict_v6", "ICT v6 (Silver Bullet, Macro)"], ["ict_pro", "ICT Pro"], ["trend", "Suivi de tendance"], ["mean_reversion", "Retour à la moyenne"]];

export function LabView() {
  return (
    <AppShell title="Laboratoire" subtitle="Tester avant de risquer : Monte Carlo sur vos R, écarts démo / réel, robustesse d'une stratégie" feature="lab">
      <Lab />
    </AppShell>
  );
}

function Lab() {
  const { data: accounts } = useLoad<Account[]>("/api/app/accounts");
  const reports = useLoad<Report[]>("/api/app/lab/reports");
  const [shown, setShown] = useState<Report | null>(null);
  const done = (r: Report | null) => { if (r) { setShown(r); reports.reload(); } };
  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <div className="grid content-start gap-5 lg:col-span-2">
        <div className="grid gap-5 md:grid-cols-2">
          <MonteCarlo onDone={done} />
          <DemoReal accounts={accounts ?? []} onDone={done} />
        </div>
        <Robustness onDone={done} />
        {shown && <ReportView r={shown} />}
      </div>
      <div className="grid content-start gap-5">
        <Section title="Rapports" icon={<FlaskConical className="size-4" />}>
          {reports.data?.filter((r) => r.kind !== "ea_factory").length ? (
            <ul className="grid gap-1.5 text-sm">
              {reports.data.filter((r) => r.kind !== "ea_factory").map((r) => (
                <li key={r.id}>
                  <button className="flex w-full flex-col rounded-lg px-2 py-1.5 text-left hover:bg-white/[0.04]" onClick={() => setShown({ ...(r.body ?? {}), id: r.id, kind: r.kind, title: r.title })}>
                    <span>{r.title}</span>
                    <span className="text-xs text-faint">{when(r.created_at)}</span>
                  </button>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">Aucun rapport.</p>}
        </Section>
        <Telemetry />
      </div>
    </div>
  );
}

function MonteCarlo({ onDone }: { onDone: (r: Report | null) => void }) {
  const [f, setF] = useState({ days: "180", risk_pct: "", limit_pct: "10", sims: "2000" });
  const { busy, run, note } = useAction();
  const go = async () => onDone(await run(() => appApi<Report>("/api/app/lab/monte-carlo", "POST", {
    days: Number(f.days), risk_pct: f.risk_pct ? Number(f.risk_pct.replace(",", ".")) : null, limit_pct: f.limit_pct ? Number(f.limit_pct.replace(",", ".")) : null, sims: Number(f.sims),
  })));
  return (
    <Section title="Monte Carlo" icon={<Dices className="size-4" />}>
      <p className="mb-3 text-sm text-muted">Rejoue vos R dans des milliers d&apos;ordres différents pour estimer le drawdown à attendre et la probabilité de toucher une limite.</p>
      <div className="grid grid-cols-2 gap-3">
        <label className="field"><span>Trades des derniers (jours)</span><input className="input" inputMode="numeric" value={f.days} onChange={(e) => setF({ ...f, days: e.target.value })} /></label>
        <label className="field"><span>Risque par trade (%)</span><input className="input" inputMode="decimal" placeholder="celui du plan" value={f.risk_pct} onChange={(e) => setF({ ...f, risk_pct: e.target.value })} /></label>
        <label className="field"><span>Limite de perte (%)</span><input className="input" inputMode="decimal" value={f.limit_pct} onChange={(e) => setF({ ...f, limit_pct: e.target.value })} /></label>
        <label className="field"><span>Simulations</span><input className="input" inputMode="numeric" value={f.sims} onChange={(e) => setF({ ...f, sims: e.target.value })} /></label>
      </div>
      <button className="btn btn-primary btn-sm mt-4" disabled={busy} onClick={go}>Simuler</button>
      {note}
    </Section>
  );
}

function DemoReal({ accounts, onDone }: { accounts: Account[]; onDone: (r: Report | null) => void }) {
  const [demo, setDemo] = useState("");
  const [real, setReal] = useState("");
  const [days, setDays] = useState("90");
  const { busy, run, note } = useAction();
  const go = async () => onDone(await run(() => appApi<Report>("/api/app/lab/demo-vs-real", "POST", { demo_account_id: demo, real_account_id: real, days: Number(days) })));
  return (
    <Section title="Démo / réel" icon={<GitCompare className="size-4" />}>
      <p className="mb-3 text-sm text-muted">Apparie les trades des deux comptes (même symbole, même sens, à moins de 5 minutes) et mesure slippage, frais et trades manquants.</p>
      {accounts.length < 2 ? <p className="text-sm text-faint">Il faut deux comptes déclarés (un démo, un réel).</p> : (
        <>
          <div className="grid grid-cols-2 gap-3">
            <label className="field"><span>Compte démo</span><select className="input" value={demo} onChange={(e) => setDemo(e.target.value)}><option value="">—</option>{accounts.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}</select></label>
            <label className="field"><span>Compte réel</span><select className="input" value={real} onChange={(e) => setReal(e.target.value)}><option value="">—</option>{accounts.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}</select></label>
            <label className="field"><span>Période (jours)</span><input className="input" inputMode="numeric" value={days} onChange={(e) => setDays(e.target.value)} /></label>
          </div>
          <button className="btn btn-primary btn-sm mt-4" disabled={busy || !demo || !real || demo === real} onClick={go}>Comparer</button>
        </>
      )}
      {note}
    </Section>
  );
}

function Robustness({ onDone }: { onDone: (r: Report | null) => void }) {
  const [f, setF] = useState({ strategy: "ict_v6", symbol: "XAUUSD", timeframe: "5m", folds: "4" });
  const { busy, run, note } = useAction();
  const go = async () => onDone(await run(() => appApi<Report>("/api/app/lab/robustness", "POST", { ...f, folds: Number(f.folds), params: {} })));
  return (
    <Section title="Robustesse d'une stratégie" icon={<Activity className="size-4" />} actions={<Usage k="backtest" label="Backtests" />}>
      <p className="mb-3 text-sm text-muted">Backtest découpé en fenêtres successives et Sharpe déflaté (qui tient compte du nombre d&apos;essais) : une stratégie qui ne tient que sur une fenêtre est probablement du bruit.</p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <label className="field"><span>Stratégie</span><select className="input" value={f.strategy} onChange={(e) => setF({ ...f, strategy: e.target.value })}>{STRATEGIES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>
        <label className="field"><span>Symbole</span><input className="input" value={f.symbol} onChange={(e) => setF({ ...f, symbol: e.target.value })} /></label>
        <label className="field"><span>Unité de temps</span><select className="input" value={f.timeframe} onChange={(e) => setF({ ...f, timeframe: e.target.value })}>{["1m", "5m", "15m", "1h", "4h"].map((x) => <option key={x}>{x}</option>)}</select></label>
        <label className="field"><span>Fenêtres</span><input className="input" type="number" min={2} max={10} value={f.folds} onChange={(e) => setF({ ...f, folds: e.target.value })} /></label>
      </div>
      <button className="btn btn-primary btn-sm mt-4" disabled={busy} onClick={go}>{busy ? "Backtest en cours…" : "Tester"}</button>
      {note}
    </Section>
  );
}

function ReportView({ r }: { r: Report }) {
  if (r.kind === "monte_carlo") {
    const dd = r.max_drawdown_pct as Pctl;
    const fin = r.final_return_pct as Pctl;
    return (
      <Section title={r.title}>
        <Kv k="Trades (R connus)" v={String(r.trades)} />
        <Kv k="Espérance" v={`${n2(r.expectancy_r as number, 3)} R`} />
        <Kv k="Risque par trade" v={`${n2(r.risk_pct as number)} %`} />
        <Kv k="Drawdown médian / 95e / 99e centile" v={`${n2(dd.p50)} % / ${n2(dd.p95)} % / ${n2(dd.p99)} %`} />
        <Kv k="Résultat 5e / médian / 95e centile" v={`${n2(fin.p05)} % / ${n2(fin.p50)} % / ${n2(fin.p95)} %`} />
        {r.breach_probability != null && <Kv k={`Probabilité de toucher −${r.limit_pct} %`} v={`${n2((r.breach_probability as number) * 100, 1)} %`} />}
        <p className="mt-3 text-xs text-faint">Rééchantillonnage de vos propres trades ({String(r.sims)} tirages, graine {String(r.seed)}) : cela suppose que l&apos;avenir ressemble à votre passé, ce qui n&apos;est pas garanti.</p>
      </Section>
    );
  }
  if (r.kind === "demo_vs_real") {
    return (
      <Section title={r.title}>
        <Kv k="Trades appariés" v={String(r.matched)} />
        <Kv k="Seulement en démo / seulement en réel" v={`${r.demo_only} / ${r.real_only}`} />
        {r.entry_slippage_avg != null && <Kv k="Écart moyen à l'entrée (prix)" v={n2(r.entry_slippage_avg as number, 5)} />}
        {r.exit_slippage_avg != null && <Kv k="Écart moyen à la sortie (prix)" v={n2(r.exit_slippage_avg as number, 5)} />}
        {r.r_diff_avg != null && <Kv k="Écart moyen de R (réel − démo)" v={<span className={tone(r.r_diff_avg as number)}>{n2(r.r_diff_avg as number, 3)}</span>} />}
        {r.cost_diff_avg != null && <Kv k="Écart moyen de frais" v={n2(r.cost_diff_avg as number)} />}
        {r.timing_diff_avg_s != null && <Kv k="Décalage moyen d'ouverture" v={`${n2(r.timing_diff_avg_s as number, 1)} s`} />}
        {r.net_demo != null && <Kv k="Net apparié démo / réel" v={`${n2(r.net_demo as number)} / ${n2(r.net_real as number)}`} />}
        <div className="mt-4"><Bullets items={(r.causes as string[]) ?? []} /></div>
      </Section>
    );
  }
  if (r.kind === "robustness") {
    const m = (r.metrics ?? {}) as Record<string, number>;
    const w = (r.windows ?? []) as { window: number; return_pct: number; sharpe_per_period: number | null }[];
    return (
      <Section title={r.title}>
        {(r.caveats as string[] | undefined)?.length ? <Notice kind="warn" className="mb-3">{(r.caveats as string[]).join(" ")}</Notice> : null}
        <p className="mb-3 text-sm font-semibold">{String(r.verdict)}</p>
        <Kv k="Barres testées" v={String(r.bars)} />
        <Kv k="Trades clôturés" v={String(r.closed_trades)} />
        {m.total_return != null && <Kv k="Rendement total" v={`${n2(m.total_return * 100)} %`} />}
        {m.max_drawdown != null && <Kv k="Drawdown maximal" v={`${n2(m.max_drawdown * 100)} %`} />}
        <Kv k="Sharpe déflaté" v={`${n2(r.deflated_sharpe as number, 3)} (${String(r.n_trials)} essai(s) de cette stratégie)`} />
        <Kv k="Fenêtres positives" v={`${r.positive_windows} / ${r.folds}`} />
        <div className="mt-4 overflow-x-auto">
          <table className="table"><thead><tr><th>Fenêtre</th><th className="text-right">Rendement</th></tr></thead>
            <tbody>{w.map((x) => <tr key={x.window}><td>{x.window}</td><td className={`num text-right ${tone(x.return_pct)}`}>{n2(x.return_pct)} %</td></tr>)}</tbody>
          </table>
        </div>
        <p className="mt-3 text-xs text-faint">Un backtest ne prédit pas les résultats futurs. Chaque nouvel essai sur la même stratégie augmente le seuil du Sharpe déflaté.</p>
      </Section>
    );
  }
  return null;
}

type Tele = { account: string; ea: string; magic: number | null; status: string; spread_points: number | null; last_error: string; time_utc: number; stale: boolean };

function Telemetry() {
  const { data } = useLoad<Tele[]>("/api/app/telemetry");
  return (
    <Section title="Surveillance des EA" icon={<Radio className="size-4" />}>
      {data?.length ? (
        <ul className="grid gap-2 text-sm">
          {data.map((t) => (
            <li key={`${t.account}${t.ea}`} className="rounded-lg border border-white/5 bg-white/[0.02] p-3">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium">{t.ea}</span>
                <span className={`chip ${t.stale ? "chip-gold" : t.status === "running" ? "chip-green" : t.status === "error" ? "chip-red" : ""}`}>{t.stale ? "silencieux" : t.status === "running" ? "actif" : t.status === "error" ? "erreur" : "arrêté"}</span>
              </div>
              <p className="mt-1 text-xs text-muted">{t.account} · dernier signal {when(t.time_utc)}{t.spread_points != null ? ` · spread ${t.spread_points} pts` : ""}</p>
              {t.last_error && <p className="mt-1 text-xs text-down-400">{t.last_error}</p>}
            </li>
          ))}
        </ul>
      ) : <p className="text-sm text-muted">Ajoutez le module AlphaEdgeTelemetry à vos EA pour suivre leur état ici (lecture seule).</p>}
    </Section>
  );
}
