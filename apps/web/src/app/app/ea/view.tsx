"use client";

import { Cpu, Download, FileCode2, History, ListPlus } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { AppShell, Usage, useApp } from "@/components/app-shell";
import { Bullets, LabelChip, RunSteps, Section, useAction, useLoad } from "@/components/app-ui";
import { Notice, Spinner } from "@/components/ui";
import { KZ_LABEL, appApi, when, useRunStream } from "@/lib/app";

type Spec = {
  name: string; symbols: string[]; timeframe: string; direction: string; entry_rules: string[]; exit_rules: string[]; risk_pct: number; stop_rule: string; target_rule: string;
  sessions: string[]; max_spread_points: number; max_trades_per_day: number; notes: string;
};
type SpecRow = { id: string; name: string; version: number; body: Spec; created_at: number };
type RunRow = { id: string; status: string; created_at: number; verdict: string | null; error: string | null };
type Report = {
  verdict: string; rounds: number; review: { passed: boolean; failed: string[]; checks: { id?: string; label: string; ok: boolean }[] } | null;
  compile: { ok: boolean | null; errors: string[]; warnings: string[] }; notes: string | null; assumptions: string[]; model_card: string; code: string | null; approval: { decision: string } | null;
};
type Run = { id: string; status: string; error: string | null; report: Report | null; cost_usd: number | null };
const VERDICT: Record<string, [string, string]> = { READY_FOR_DEMO: ["Prêt pour la démo", "chip-green"], REVIEWED_NOT_COMPILED: ["Revu, compilation non vérifiée", "chip-gold"], NEEDS_WORK: ["À retravailler", "chip-red"] };
const lines = (s: string) => s.split("\n").map((x) => x.trim()).filter(Boolean);

export function EaView() {
  return (
    <AppShell title="Usine EA" subtitle="De votre spécification à un EA MQL5 revu et compilé, prêt pour un compte démo" feature="ea_factory">
      <Factory />
    </AppShell>
  );
}

function Factory() {
  const { app, reload: reloadApp } = useApp();
  const specs = useLoad<SpecRow[]>("/api/app/ea/specs");
  const runs = useLoad<RunRow[]>("/api/app/ea/runs");
  const [trace, setTrace] = useState<string | null>(null);
  const [current, setCurrent] = useState<string | null>(null);
  const [runData, setRunData] = useState<Run | null>(null);
  const { busy, run, note } = useAction();
  const load = useCallback(async (id: string) => setRunData(await appApi<Run>(`/api/app/ea/runs/${id}`).catch(() => null)), []);
  useEffect(() => { if (current) load(current); }, [current, load]);
  const { steps, status } = useRunStream(trace, () => { if (trace) { setCurrent(trace); load(trace); } runs.reload(); reloadApp(); });
  const start = async (specId: string) => {
    const out = await run(() => appApi<{ trace_id: string }>("/api/app/ea/runs", "POST", { spec_id: specId }));
    if (out) { setRunData(null); setCurrent(null); setTrace(out.trace_id); }
  };
  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <div className="grid content-start gap-5 lg:col-span-2">
        {!app?.ai && <Notice kind="warn">Aucun modèle de langage n&apos;est configuré sur cette plateforme : la génération de code est indisponible. Les spécifications restent enregistrables.</Notice>}
        <SpecForm onSaved={specs.reload} />
        {(status || note) && <div className="grid gap-3">{note}<RunSteps steps={steps} status={status} /></div>}
        {runData ? <RunView r={runData} onDone={() => current && load(current)} /> : current && <Spinner />}
      </div>
      <div className="grid content-start gap-5">
        <Section title="Spécifications" icon={<FileCode2 className="size-4" />} actions={<Usage k="ea_run" label="Générations" />}>
          {specs.data?.length ? (
            <ul className="grid gap-2 text-sm">
              {specs.data.map((s) => (
                <li key={s.id} className="flex flex-wrap items-center gap-2 rounded-lg border border-white/5 bg-white/[0.02] p-3">
                  <span className="font-medium">{s.name}</span><span className="chip">v{s.version}</span>
                  <span className="w-full text-xs text-muted">{s.body.symbols.join(", ")} · {s.body.timeframe} · {when(s.created_at)}</span>
                  <button className="btn btn-ghost btn-sm" disabled={busy || !app?.ai || status === "running"} onClick={() => start(s.id)}>Générer l&apos;EA</button>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">Écrivez d&apos;abord une spécification.</p>}
        </Section>
        <Section title="Générations" icon={<History className="size-4" />}>
          {runs.data?.length ? (
            <ul className="grid gap-1.5 text-sm">
              {runs.data.map((r) => (
                <li key={r.id}>
                  <button className="flex w-full flex-wrap items-center gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-white/[0.04]" onClick={() => { setTrace(null); setCurrent(r.id); }}>
                    <span className="text-muted">{when(r.created_at)}</span>
                    {r.verdict ? <LabelChip map={VERDICT} k={r.verdict} /> : <span className="chip">{r.status === "failed" ? "échec" : r.status === "waiting" ? "à approuver" : "en cours"}</span>}
                  </button>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">Aucune génération.</p>}
        </Section>
      </div>
    </div>
  );
}

const EMPTY = { name: "", symbols: "XAUUSD", timeframe: "M5", direction: "both", entry_rules: "", exit_rules: "", risk_pct: "0.5", stop_rule: "", target_rule: "", sessions: [] as string[], max_spread_points: "40", max_trades_per_day: "2", notes: "" };

function SpecForm({ onSaved }: { onSaved: () => void }) {
  const [f, setF] = useState(EMPTY);
  const { busy, run, note } = useAction();
  const save = async () => {
    const body = {
      name: f.name.trim(), symbols: f.symbols.split(/[,\s]+/).filter(Boolean).slice(0, 3), timeframe: f.timeframe, direction: f.direction, entry_rules: lines(f.entry_rules), exit_rules: lines(f.exit_rules),
      risk_pct: Number(f.risk_pct.replace(",", ".")), stop_rule: f.stop_rule, target_rule: f.target_rule, sessions: f.sessions, max_spread_points: Number(f.max_spread_points), max_trades_per_day: Number(f.max_trades_per_day), notes: f.notes,
    };
    if (await run(() => appApi("/api/app/ea/specs", "POST", body), "Spécification enregistrée")) onSaved();
  };
  const set = (k: keyof typeof EMPTY) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  return (
    <Section title="Nouvelle spécification" icon={<ListPlus className="size-4" />}>
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="field sm:col-span-2"><span>Nom (lettres, chiffres, tirets)</span><input className="input" maxLength={60} value={f.name} onChange={set("name")} placeholder="SilverBullet-NY" /></label>
        <label className="field"><span>Symboles (3 au plus)</span><input className="input" value={f.symbols} onChange={set("symbols")} /></label>
        <label className="field"><span>Unité de temps</span><select className="input" value={f.timeframe} onChange={set("timeframe")}>{["M1", "M5", "M15", "M30", "H1", "H4"].map((x) => <option key={x}>{x}</option>)}</select></label>
        <label className="field"><span>Sens</span><select className="input" value={f.direction} onChange={set("direction")}><option value="both">Achat et vente</option><option value="long">Achat seulement</option><option value="short">Vente seulement</option></select></label>
        <label className="field"><span>Risque par trade (%, 2 au plus)</span><input className="input" inputMode="decimal" value={f.risk_pct} onChange={set("risk_pct")} /></label>
        <label className="field sm:col-span-3"><span>Règles d&apos;entrée (une par ligne)</span><textarea className="input min-h-24" value={f.entry_rules} onChange={set("entry_rules")} placeholder={"Sweep du plus bas de la session asiatique\nMSS en M5 avec déplacement\nEntrée au retour dans le FVG créé par le déplacement"} /></label>
        <label className="field sm:col-span-3"><span>Règles de sortie (une par ligne)</span><textarea className="input min-h-16" value={f.exit_rules} onChange={set("exit_rules")} placeholder={"Clôture de la moitié au premier objectif\nStop au point d'entrée ensuite"} /></label>
        <label className="field sm:col-span-3"><span>Stop</span><input className="input" maxLength={300} value={f.stop_rule} onChange={set("stop_rule")} placeholder="Sous le plus bas du déplacement, plus 2 points de marge" /></label>
        <label className="field sm:col-span-3"><span>Objectif</span><input className="input" maxLength={300} value={f.target_rule} onChange={set("target_rule")} placeholder="Liquidité opposée la plus proche, au moins 2 R" /></label>
        <label className="field"><span>Spread maximal (points)</span><input className="input" inputMode="numeric" value={f.max_spread_points} onChange={set("max_spread_points")} /></label>
        <label className="field"><span>Trades par jour au plus</span><input className="input" inputMode="numeric" value={f.max_trades_per_day} onChange={set("max_trades_per_day")} /></label>
        <fieldset className="field sm:col-span-3">
          <span>Sessions (aucune = toutes)</span>
          <div className="flex flex-wrap gap-1.5">
            {Object.entries(KZ_LABEL).map(([k, l]) => {
              const on = f.sessions.includes(k);
              return <button key={k} type="button" aria-pressed={on} className={`chip ${on ? "chip-blue" : ""}`} onClick={() => setF({ ...f, sessions: on ? f.sessions.filter((x) => x !== k) : [...f.sessions, k] })}>{l}</button>;
            })}
          </div>
        </fieldset>
        <label className="field sm:col-span-3"><span>Notes (facultatif)</span><textarea className="input min-h-16" maxLength={2000} value={f.notes} onChange={set("notes")} /></label>
      </div>
      <p className="mt-3 text-xs text-faint">Le code généré utilise le numéro magique 770077, calcule la taille depuis le risque, vérifie chaque ordre et refuse martingale, grille et DLL. Il est destiné à un compte démo ; aucune performance n&apos;est promise.</p>
      <button className="btn btn-primary btn-sm mt-4" disabled={busy || f.name.trim().length < 3 || !f.entry_rules.trim() || !f.exit_rules.trim() || f.stop_rule.length < 5 || f.target_rule.length < 5} onClick={save}>Enregistrer la spécification</button>
      {note}
    </Section>
  );
}

function RunView({ r, onDone }: { r: Run; onDone: () => void }) {
  const { busy, run, note } = useAction();
  if (r.status === "failed") return <Notice kind="error">La génération a échoué : {r.error ?? "erreur inconnue"}.</Notice>;
  const rep = r.report;
  if (!rep) return <Spinner label="Génération en cours…" />;
  const download = () => {
    if (!rep.code) return;
    const url = URL.createObjectURL(new Blob([rep.code], { type: "text/plain" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `${(rep.model_card.match(/EA (.+)/)?.[1] ?? "AlphaEdge").replace(/[^A-Za-z0-9_-]+/g, "_")}.mq5`;
    a.click();
    URL.revokeObjectURL(url);
  };
  const approve = async (decision: "approved" | "rejected") => { if (await run(() => appApi(`/api/app/ea/runs/${r.id}/approve`, "POST", { decision }))) onDone(); };
  return (
    <Section title="Résultat" icon={<Cpu className="size-4" />} actions={<LabelChip map={VERDICT} k={rep.verdict} />}>
      <div className="grid gap-5">
        <div className="grid gap-5 sm:grid-cols-2">
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Vérifications déterministes</h3>
            <ul className="grid gap-1 text-sm">
              {(rep.review?.checks ?? []).map((c) => <li key={c.label} className={c.ok ? "text-up-300" : "text-down-400"}>{c.ok ? "✓" : "✗"} {c.label}</li>)}
            </ul>
          </div>
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Compilation MQL5</h3>
            <p className="text-sm">{rep.compile.ok ? "Compilé sans erreur" : rep.compile.ok === false ? "Erreurs de compilation" : "Non vérifiée (compilateur indisponible)"}</p>
            {rep.compile.errors.length > 0 && <div className="mt-2 text-xs text-down-400"><Bullets items={rep.compile.errors.slice(0, 8)} /></div>}
            <p className="mt-2 text-xs text-faint">{rep.rounds} tour(s) de génération.</p>
          </div>
        </div>
        {rep.assumptions.length > 0 && (
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Hypothèses d&apos;interprétation</h3>
            <Bullets items={rep.assumptions} />
          </div>
        )}
        <details>
          <summary className="cursor-pointer text-xs font-semibold uppercase tracking-wider text-faint">Model card</summary>
          <pre className="mt-2 max-h-96 overflow-auto whitespace-pre-wrap rounded-lg bg-ink-950 p-3 text-xs leading-relaxed text-fg/85">{rep.model_card}</pre>
        </details>
        {rep.code && (
          <details>
            <summary className="cursor-pointer text-xs font-semibold uppercase tracking-wider text-faint">Code MQL5</summary>
            <pre className="num mt-2 max-h-[28rem] overflow-auto rounded-lg bg-ink-950 p-3 text-xs leading-relaxed text-fg/85">{rep.code}</pre>
          </details>
        )}
        <div className="flex flex-wrap gap-2">
          {rep.code && <button className="btn btn-ghost btn-sm" onClick={download}><Download className="size-4" aria-hidden /> Télécharger le .mq5</button>}
        </div>
        {r.status === "waiting" && !rep.approval && (
          <div className="card-gold p-4">
            <p className="text-sm">Relisez le code et la model card. Votre approbation autorise uniquement l&apos;essai sur un <strong>compte démo</strong> ; elle est enregistrée dans le journal d&apos;audit.</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button className="btn btn-primary btn-sm" disabled={busy} onClick={() => approve("approved")}>J&apos;approuve l&apos;essai en démo</button>
              <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => approve("rejected")}>Je refuse</button>
            </div>
          </div>
        )}
        {rep.approval && <Notice kind="info">Décision enregistrée : {rep.approval.decision === "approved" ? "essai en démo approuvé" : "refusé"}.</Notice>}
        {note}
      </div>
    </Section>
  );
}
