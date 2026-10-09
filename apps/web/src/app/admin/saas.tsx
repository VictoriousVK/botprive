"use client";

// Operators: SaaS health (jobs, runs, AI costs), Mentor knowledge base, calendar and news imports,
// pre-session briefing, and the ICT golden set (annotation tool and precision / recall).

import { BookOpen, CalendarClock, Crosshair, Gauge, RefreshCw, Trash } from "lucide-react";
import { useCallback, useEffect, useState, type ReactNode } from "react";
import { Candles, Kv, Section, type Bar, type Mark, type Zone } from "@/components/app-ui";
import { Notice, Spinner, Stat } from "@/components/ui";
import { api } from "@/lib/api";
import { n2, when } from "@/lib/app";

const op = <T,>(path: string, method = "GET", body?: unknown) => api<T>(path, { method, body, as: "operator" });

function useOp<T>(path: string) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const reload = useCallback(async () => {
    try {
      setData(await op<T>(path));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erreur");
    }
  }, [path]);
  useEffect(() => {
    reload();
  }, [reload]);
  return { data, error, reload };
}

function useRun() {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "error"; text: string } | null>(null);
  const run = async <T,>(fn: () => Promise<T>, ok?: (r: T) => string): Promise<T | null> => {
    setBusy(true);
    setMsg(null);
    try {
      const r = await fn();
      if (ok) setMsg({ kind: "ok", text: ok(r) });
      return r;
    } catch (e) {
      setMsg({ kind: "error", text: e instanceof Error ? e.message : "Erreur" });
      return null;
    } finally {
      setBusy(false);
    }
  };
  const note: ReactNode = msg ? <Notice kind={msg.kind} className="mt-3">{msg.text}</Notice> : null;
  return { busy, run, note };
}

type SaasOverview = {
  jobs: Record<string, number>; runs_24h: Record<string, number>; by_graph_24h: { graph: string; runs: number; cost_usd: number | null; llm_calls: number | null }[];
  usage_month: { key: string; count: number; cost_usd: number | null }[]; manifest: { fingerprint: string; model_ids: Record<string, string>; prompt_sha: Record<string, string> }; ai: boolean; database: string;
};

const GRAPH_LABEL: Record<string, string> = { G1: "Analyste (G1)", G2: "Usine EA (G2)", G3: "Coach (G3)", G4: "Research (G4)", mentor: "Mentor", router: "Routeur" };

export function SaasTab() {
  return (
    <div className="grid gap-6">
      <Health />
      <div className="grid gap-6 lg:grid-cols-2">
        <Knowledge />
        <Research />
      </div>
      <Golden />
    </div>
  );
}

function Health() {
  const { data: o, error, reload } = useOp<SaasOverview>("/api/admin/saas/overview");
  if (error) return <Notice kind="error">{error}</Notice>;
  if (!o) return <Spinner />;
  return (
    <Section title="Santé du SaaS" icon={<Gauge className="size-4" />} actions={<button className="btn btn-ghost btn-sm" onClick={reload}><RefreshCw className="size-4" aria-hidden /> Actualiser</button>}>
      {!o.ai && <Notice kind="warn" className="mb-4">Aucune clé ANTHROPIC_API_KEY : les agents répondent avec leurs sorties déterministes (texte rédigé par les règles).</Notice>}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Stat label="Base" value={o.database === "postgresql" ? "PostgreSQL (RLS)" : "SQLite"} />
        <Stat label="Tâches en file" value={(o.jobs.queued ?? 0) + (o.jobs.running ?? 0)} />
        <Stat label="Tâches en échec" value={o.jobs.failed ?? 0} tone={o.jobs.failed ? "text-down-400" : ""} />
        <Stat label="Exécutions 24 h" value={Object.values(o.runs_24h).reduce((a, b) => a + b, 0)} />
      </div>
      <div className="mt-5 grid gap-5 lg:grid-cols-2">
        <div className="overflow-x-auto">
          <table className="table">
            <thead><tr><th>Agent (24 h)</th><th className="text-right">Exécutions</th><th className="text-right">Appels IA</th><th className="text-right">Coût</th></tr></thead>
            <tbody>
              {o.by_graph_24h.map((g) => (
                <tr key={g.graph}><td>{GRAPH_LABEL[g.graph] ?? g.graph}</td><td className="num text-right">{g.runs}</td><td className="num text-right">{g.llm_calls ?? 0}</td><td className="num text-right">{n2(g.cost_usd ?? 0, 3)} $</td></tr>
              ))}
              {!o.by_graph_24h.length && <tr><td colSpan={4} className="text-faint">Aucune exécution.</td></tr>}
            </tbody>
          </table>
        </div>
        <div className="overflow-x-auto">
          <table className="table">
            <thead><tr><th>Usage du mois</th><th className="text-right">Nombre</th><th className="text-right">Coût IA</th></tr></thead>
            <tbody>
              {o.usage_month.map((u) => <tr key={u.key}><td>{u.key}</td><td className="num text-right">{u.count}</td><td className="num text-right">{n2(u.cost_usd ?? 0, 3)} $</td></tr>)}
              {!o.usage_month.length && <tr><td colSpan={3} className="text-faint">Aucun usage ce mois.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
      <details className="mt-4 text-sm">
        <summary className="cursor-pointer text-xs font-semibold uppercase tracking-wider text-faint">Manifeste de version <span className="num normal-case">{o.manifest.fingerprint.slice(0, 16)}</span></summary>
        <div className="mt-2 grid gap-4 sm:grid-cols-2">
          <div>{Object.entries(o.manifest.model_ids ?? {}).map(([k, v]) => <Kv key={k} k={k} v={v} />)}</div>
          <div>{Object.entries(o.manifest.prompt_sha ?? {}).map(([k, v]) => <Kv key={k} k={`prompt ${k}`} v={String(v).slice(0, 12)} />)}</div>
        </div>
      </details>
    </Section>
  );
}

// ---------------- knowledge base ----------------
type Doc = { id: string; title: string; source: string; access: string; ref: string | null; chunks: number; created_at?: number };
const EMPTY_DOC = { title: "", source: "faq", access: "academy_member", ref: "", text: "" };

function Knowledge() {
  const { data, reload } = useOp<Doc[]>("/api/admin/knowledge");
  const [f, setF] = useState(EMPTY_DOC);
  const { busy, run, note } = useRun();
  const add = async () => {
    if (await run(() => op("/api/admin/knowledge", "POST", { ...f, ref: f.ref || null }), () => "Document indexé")) { setF(EMPTY_DOC); reload(); }
  };
  return (
    <Section title="Base de connaissances du Mentor" icon={<BookOpen className="size-4" />}
      actions={<button className="btn btn-ghost btn-sm" disabled={busy} onClick={async () => { if (await run(() => op<Record<string, number>>("/api/admin/knowledge/reindex", "POST"), (r) => `Réindexé : ${Object.entries(r).map(([k, v]) => `${v} ${k === "skill" ? "fiche(s)" : k === "course" ? "cours" : k}`).join(", ")}`)) reload(); }}>Réindexer</button>}>
      <p className="mb-3 text-sm text-muted">Le Mentor ne répond qu&apos;à partir de ces documents, filtrés selon l&apos;accès du membre. Les fiches de compétences et les cours de l&apos;académie sont indexés automatiquement.</p>
      <ul className="mb-4 grid max-h-64 gap-1.5 overflow-y-auto text-sm">
        {(data ?? []).map((d) => (
          <li key={d.id} className="flex flex-wrap items-center gap-2 border-b border-white/5 pb-1.5">
            <span className="min-w-0 flex-1 truncate">{d.title}</span>
            <span className="chip">{d.source}</span>
            <span className="text-xs text-faint">{d.access} · {d.chunks} passage(s)</span>
            <button className="text-faint hover:text-down-400" aria-label={`Supprimer ${d.title}`} disabled={busy} onClick={async () => { if (confirm(`Supprimer « ${d.title} » ?`) && (await run(() => op(`/api/admin/knowledge/${d.id}`, "DELETE")))) reload(); }}><Trash className="size-4" aria-hidden /></button>
          </li>
        ))}
        {data && !data.length && <li className="text-faint">Aucun document.</li>}
      </ul>
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="field sm:col-span-3"><span>Titre</span><input className="input" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} /></label>
        <label className="field"><span>Type</span><select className="input" value={f.source} onChange={(e) => setF({ ...f, source: e.target.value })}><option value="faq">FAQ</option><option value="transcript">Transcription</option><option value="fiche">Fiche</option><option value="definition">Définition</option></select></label>
        <label className="field"><span>Accès</span><select className="input" value={f.access} onChange={(e) => setF({ ...f, access: e.target.value })}><option value="academy_member">Membres (Starter et plus)</option><option value="academy_free">Tous les comptes</option><option value="formation_ict">Formation ICT</option><option value="formation_ea">Formation EA</option><option value="formation_quant">Formation Quant</option><option value="mentorat">Mentorat</option></select></label>
        <label className="field"><span>Référence (facultatif)</span><input className="input" value={f.ref} onChange={(e) => setF({ ...f, ref: e.target.value })} placeholder="Module 3, leçon 2" /></label>
        <label className="field sm:col-span-3"><span>Texte (20 caractères au moins)</span><textarea className="input min-h-28" value={f.text} onChange={(e) => setF({ ...f, text: e.target.value })} /></label>
      </div>
      <button className="btn btn-primary btn-sm mt-3" disabled={busy || f.title.length < 3 || f.text.length < 20} onClick={add}>Ajouter</button>
      {note}
    </Section>
  );
}

// ---------------- calendar, news, briefing ----------------
function Research() {
  const [csv, setCsv] = useState("");
  const [news, setNews] = useState("");
  const { busy, run, note } = useRun();
  const importNews = () => run(async () => {
    let items: unknown;
    try {
      items = JSON.parse(news);
    } catch {
      throw new Error("JSON invalide");
    }
    if (!Array.isArray(items)) throw new Error("Attendu : une liste d'articles");
    return op<{ added: number }>("/api/admin/news", "POST", { items });
  }, (r) => `${r.added} article(s) ajouté(s)`);
  return (
    <Section title="Calendrier, actualités, briefing" icon={<CalendarClock className="size-4" />}>
      <label className="field">
        <span>Calendrier économique (CSV : time, currency, impact, title ; heures ISO en UTC)</span>
        <textarea className="input num min-h-24 text-xs" value={csv} onChange={(e) => setCsv(e.target.value)} placeholder={"time,currency,impact,title\n2026-10-02T12:30:00Z,USD,high,Non-Farm Payrolls"} />
      </label>
      <button className="btn btn-ghost btn-sm mt-2" disabled={busy || csv.length < 10} onClick={() => run(() => op<{ added: number }>("/api/admin/calendar", "POST", { csv, source: "import manuel" }), (r) => `${r.added} annonce(s) ajoutée(s)`)}>Importer le calendrier</button>
      <label className="field mt-4">
        <span>Actualités (JSON : liste de {"{time_utc, publisher, title, url, summary}"})</span>
        <textarea className="input num min-h-20 text-xs" value={news} onChange={(e) => setNews(e.target.value)} />
      </label>
      <button className="btn btn-ghost btn-sm mt-2" disabled={busy || news.length < 5} onClick={importNews}>Importer les actualités</button>
      <div className="mt-5 flex flex-wrap gap-2 border-t border-white/5 pt-4">
        <button className="btn btn-primary btn-sm" disabled={busy} onClick={() => run(() => op<{ status: string }>("/api/admin/briefing?session=london", "POST"), (r) => `Briefing Londres : ${r.status === "done" ? "publié" : r.status}`)}>Briefing Londres</button>
        <button className="btn btn-primary btn-sm" disabled={busy} onClick={() => run(() => op<{ status: string }>("/api/admin/briefing?session=new_york", "POST"), (r) => `Briefing New York : ${r.status === "done" ? "publié" : r.status}`)}>Briefing New York</button>
      </div>
      <p className="mt-2 text-xs text-faint">En production, n8n appelle /api/jobs/briefing avant chaque session (voir workflows/n8n).</p>
      {note}
    </Section>
  );
}

// ---------------- golden set ----------------
type Labels = { fvg: { kind: string; t: number; top: number; bottom: number }[]; swings: { kind: string; t: number; price: number }[]; sweeps: { side: string; level: number; t: number }[]; mss: { direction: string; t: number }[]; setup: null };
type Snap = { symbol: string; timeframe: string; as_of: number; bars: Bar[]; synthetic: boolean };
type EvalRes = { dataset: string; split: string; definitions: string; cases: number; summary: Record<string, { cases: number; labels: number; found: number; tp: number; precision: number | null; recall: number | null }> | null };
const EMPTY_LABELS: Labels = { fvg: [], swings: [], sweeps: [], mss: [], setup: null };

function Golden() {
  const [dataset, setDataset] = useState("golden-v1");
  const [snapIn, setSnapIn] = useState({ symbol: "XAUUSD", timeframe: "M5", at: "", bars: "120" });
  const [snap, setSnap] = useState<Snap | null>(null);
  const [pick, setPick] = useState<number | null>(null);
  const [labels, setLabels] = useState<Labels>(EMPTY_LABELS);
  const [meta, setMeta] = useState({ annotator: "", rationale: "", split: "dev" });
  const [evalRes, setEvalRes] = useState<EvalRes | null>(null);
  const list = useOp<{ id: string; symbol: string; timeframe: string; as_of: number; annotator: string; split: string; created_at: number; labels: Labels }[]>(`/api/admin/golden?dataset=${encodeURIComponent(dataset)}`);
  const { busy, run, note } = useRun();

  const load = async () => {
    const out = await run(() => op<Snap>("/api/admin/golden/snapshot", "POST", { symbol: snapIn.symbol, timeframe: snapIn.timeframe, bars: Number(snapIn.bars), at: snapIn.at ? new Date(snapIn.at + "Z").getTime() : null }));
    if (out) { setSnap(out); setLabels(EMPTY_LABELS); setPick(null); }
  };
  const b = snap && pick != null ? snap.bars[pick] : null;
  const prev = snap && pick != null && pick > 0 ? snap.bars[pick - 1] : null;
  const next = snap && pick != null && pick < snap.bars.length - 1 ? snap.bars[pick + 1] : null;
  const add = (fn: (l: Labels) => Labels) => setLabels(fn(labels));

  const marks: Mark[] = [
    ...labels.swings.map((s) => ({ t: s.t, price: s.price, label: s.kind === "high" ? "SH" : "SL" })),
    ...labels.sweeps.map((s) => ({ t: s.t, price: s.level, label: s.side, color: "#8fcbff" })),
    ...(snap ? labels.mss.map((m) => ({ t: m.t, price: (snap.bars.find((x) => x[0] === m.t) ?? [0, 0, 0, 0, 0])[4], label: m.direction === "bullish" ? "MSS↑" : "MSS↓", color: "#4be08a" })) : []),
  ];
  const zones: Zone[] = labels.fvg.map((g) => ({ top: g.top, bottom: g.bottom, label: g.kind, color: g.kind === "BISI" ? "rgb(75 224 138 / .12)" : "rgb(239 83 84 / .12)" }));
  const count = labels.fvg.length + labels.swings.length + labels.sweeps.length + labels.mss.length;

  const save = async () => {
    if (!snap) return;
    const body = { dataset, symbol: snap.symbol, timeframe: snap.timeframe, as_of: snap.as_of, bars: snap.bars, labels, ...meta };
    if (await run(() => op<{ id: string }>("/api/admin/golden", "POST", body), (r) => `Annotation enregistrée (${r.id})`)) { list.reload(); setLabels(EMPTY_LABELS); }
  };

  return (
    <Section title="Golden set ICT" icon={<Crosshair className="size-4" />}>
      <p className="mb-4 text-sm text-muted">
        Annotez des graphiques réels pour mesurer la précision et le rappel du moteur ICT (définitions versionnées). Cliquez une bougie puis étiquetez-la. Le jeu « holdout » ne sert qu&apos;à la validation finale ; ne le consultez pas en réglant le moteur.
      </p>
      <div className="grid gap-3 sm:grid-cols-5">
        <label className="field"><span>Jeu de données</span><input className="input" value={dataset} onChange={(e) => setDataset(e.target.value.toLowerCase())} /></label>
        <label className="field"><span>Symbole</span><input className="input" value={snapIn.symbol} onChange={(e) => setSnapIn({ ...snapIn, symbol: e.target.value })} /></label>
        <label className="field"><span>Unité</span><select className="input" value={snapIn.timeframe} onChange={(e) => setSnapIn({ ...snapIn, timeframe: e.target.value })}>{["M1", "M5", "M15", "H1"].map((x) => <option key={x}>{x}</option>)}</select></label>
        <label className="field"><span>Jusqu&apos;à (UTC, vide = maintenant)</span><input className="input" type="datetime-local" value={snapIn.at} onChange={(e) => setSnapIn({ ...snapIn, at: e.target.value })} /></label>
        <label className="field"><span>Bougies</span><input className="input" type="number" min={40} max={600} value={snapIn.bars} onChange={(e) => setSnapIn({ ...snapIn, bars: e.target.value })} /></label>
      </div>
      <button className="btn btn-ghost btn-sm mt-3" disabled={busy} onClick={load}>Charger le graphique</button>
      {snap && (
        <div className="mt-4 grid gap-4">
          {snap.synthetic && <Notice kind="warn">Prix simulés : n&apos;annotez que des données de marché réelles pour le golden set.</Notice>}
          <Candles bars={snap.bars} zones={zones} marks={marks} picked={pick} onPick={setPick} height={360} label={`Graphique à annoter ${snap.symbol} ${snap.timeframe}`} />
          {b && (
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span className="num text-muted">{new Date(b[0]).toISOString().slice(0, 16).replace("T", " ")} UTC · H {Number(b[2].toPrecision(8))} · L {Number(b[3].toPrecision(8))}</span>
              <button className="chip" onClick={() => add((l) => ({ ...l, swings: [...l.swings, { kind: "high", t: b[0], price: b[2] }] }))}>Swing haut</button>
              <button className="chip" onClick={() => add((l) => ({ ...l, swings: [...l.swings, { kind: "low", t: b[0], price: b[3] }] }))}>Swing bas</button>
              {prev && next && next[3] > prev[2] && <button className="chip chip-green" onClick={() => add((l) => ({ ...l, fvg: [...l.fvg, { kind: "BISI", t: b[0], top: next[3], bottom: prev[2] }] }))}>FVG haussier (bougie du milieu)</button>}
              {prev && next && next[2] < prev[3] && <button className="chip chip-red" onClick={() => add((l) => ({ ...l, fvg: [...l.fvg, { kind: "SIBI", t: b[0], top: prev[3], bottom: next[2] }] }))}>FVG baissier (bougie du milieu)</button>}
              <button className="chip chip-blue" onClick={() => add((l) => ({ ...l, sweeps: [...l.sweeps, { side: "BSL", level: b[2], t: b[0] }] }))}>Prise BSL</button>
              <button className="chip chip-blue" onClick={() => add((l) => ({ ...l, sweeps: [...l.sweeps, { side: "SSL", level: b[3], t: b[0] }] }))}>Prise SSL</button>
              <button className="chip" onClick={() => add((l) => ({ ...l, mss: [...l.mss, { direction: "bullish", t: b[0] }] }))}>MSS haussier</button>
              <button className="chip" onClick={() => add((l) => ({ ...l, mss: [...l.mss, { direction: "bearish", t: b[0] }] }))}>MSS baissier</button>
            </div>
          )}
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted">
            <span>{labels.swings.length} swing(s), {labels.fvg.length} FVG, {labels.sweeps.length} prise(s), {labels.mss.length} MSS</span>
            {count > 0 && <button className="text-brand-300 hover:underline" onClick={() => setLabels(EMPTY_LABELS)}>Tout effacer</button>}
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <label className="field"><span>Annotateur</span><input className="input" value={meta.annotator} onChange={(e) => setMeta({ ...meta, annotator: e.target.value })} /></label>
            <label className="field"><span>Jeu</span><select className="input" value={meta.split} onChange={(e) => setMeta({ ...meta, split: e.target.value })}><option value="dev">dev (réglage)</option><option value="holdout">holdout (validation)</option></select></label>
            <label className="field sm:col-span-3"><span>Justification</span><textarea className="input min-h-16" value={meta.rationale} onChange={(e) => setMeta({ ...meta, rationale: e.target.value })} /></label>
          </div>
          <button className="btn btn-primary btn-sm justify-self-start" disabled={busy || meta.annotator.length < 2 || count === 0} onClick={save}>Enregistrer l&apos;annotation</button>
        </div>
      )}
      {note}

      <div className="mt-6 grid gap-5 border-t border-white/5 pt-5 lg:grid-cols-2">
        <div>
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <h3 className="flex-1 font-semibold">Mesure du moteur</h3>
            <button className="btn btn-ghost btn-sm" disabled={busy} onClick={async () => { const r = await run(() => op<EvalRes>(`/api/admin/golden/eval?dataset=${encodeURIComponent(dataset)}&split=dev`)); if (r) setEvalRes(r); }}>Évaluer (dev)</button>
            <button className="btn btn-ghost btn-sm" disabled={busy} onClick={async () => { const r = await run(() => op<EvalRes>("/api/admin/golden/eval?dataset=synthetic-v1")); if (r) setEvalRes(r); }}>Jeu synthétique</button>
          </div>
          {evalRes && (
            evalRes.summary ? (
              <table className="table">
                <thead><tr><th>{evalRes.dataset} · {evalRes.cases} cas</th><th className="text-right">Étiquettes</th><th className="text-right">Précision</th><th className="text-right">Rappel</th></tr></thead>
                <tbody>
                  {Object.entries(evalRes.summary).map(([k, v]) => (
                    <tr key={k}><td>{k === "fvg" ? "FVG" : k === "swings" ? "Swings" : k}</td><td className="num text-right">{v.labels}</td><td className="num text-right">{v.precision == null ? "—" : n2(v.precision * 100, 1) + " %"}</td><td className="num text-right">{v.recall == null ? "—" : n2(v.recall * 100, 1) + " %"}</td></tr>
                  ))}
                </tbody>
              </table>
            ) : <p className="text-sm text-muted">Aucun cas dans ce jeu.</p>
          )}
          {evalRes && <p className="mt-2 text-xs text-faint">Définitions {evalRes.definitions}.</p>}
        </div>
        <div>
          <h3 className="mb-3 font-semibold">Annotations ({list.data?.length ?? 0})</h3>
          <ul className="grid max-h-64 gap-1.5 overflow-y-auto text-sm">
            {(list.data ?? []).map((a) => (
              <li key={a.id} className="flex flex-wrap items-center gap-2 border-b border-white/5 pb-1.5">
                <span>{a.symbol} {a.timeframe}</span>
                <span className="chip">{a.split}</span>
                <span className="text-xs text-faint">{when(a.as_of)} · {a.annotator}</span>
                <button className="ml-auto text-faint hover:text-down-400" aria-label="Supprimer l'annotation" disabled={busy} onClick={async () => { if (confirm("Supprimer cette annotation ?") && (await run(() => op(`/api/admin/golden/${a.id}`, "DELETE")))) list.reload(); }}><Trash className="size-4" aria-hidden /></button>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </Section>
  );
}
