"use client";

import { BellRing, CalendarClock, Crosshair, History, ShieldCheck, Trash2 } from "lucide-react";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { AppShell, Usage, useApp } from "@/components/app-shell";
import { Bullets, Candles, CopyField, Disclaimer, Kv, LabelChip, RunSteps, Section, Seg, useAction, useLoad, type Bar, type Level, type Zone } from "@/components/app-ui";
import { Notice, Spinner } from "@/components/ui";
import { GATE_LABEL, KZ_LABEL, MODEL_LABEL, SETUP_LABEL, appApi, money, n2, pc, rr, when, useRunStream, type Account, type Analysis, type SetupCard } from "@/lib/app";

type Row = { id: string; symbol: string; as_of: number; source: string; label: string; decision: string | null; expires_at: number | null; created_at: number; model: string | null };
const BIAS: Record<string, string> = { bullish: "haussier", bearish: "baissier", neutral: "neutre" };
const PD: Record<string, string> = { premium: "premium", discount: "discount", equilibrium: "équilibre" };
const AMD: Record<string, string> = { accumulation: "accumulation", manipulation: "manipulation", distribution: "distribution", unknown: "indéterminée" };

export function AnalysisView() {
  return (
    <AppShell title="Analyse de setup ICT" subtitle="Le moteur ICT détecte, le risk gate dimensionne, l'IA explique. Vous décidez." feature="analysis">
      <Analyste />
    </AppShell>
  );
}

function Analyste() {
  const { app, reload: reloadApp } = useApp();
  const params = useSearchParams();
  const { data: sym } = useLoad<{ symbols: string[]; synthetic: boolean | null }>("/api/app/symbols");
  const { data: accounts } = useLoad<Account[]>("/api/app/accounts");
  const history = useLoad<Row[]>("/api/app/analyses");
  const [f, setF] = useState({ symbol: "XAUUSD", tf_entry: "M5", tf_htf: "H1", account_id: "", note: "" });
  const [trace, setTrace] = useState<string | null>(null);
  const [current, setCurrent] = useState<string | null>(params.get("id"));
  const [a, setA] = useState<Analysis | null>(null);
  const [tf, setTf] = useState("M5");
  const { busy, run, note } = useAction();

  useEffect(() => {
    if (sym?.symbols.length && !sym.symbols.includes(f.symbol)) setF((x) => ({ ...x, symbol: sym.symbols[0] }));
  }, [sym, f.symbol]);

  const load = useCallback(async (id: string) => setA(await appApi<Analysis>(`/api/app/analyses/${id}`).catch(() => null)), []);
  useEffect(() => {
    if (current) load(current);
  }, [current, load]);

  const { steps, status } = useRunStream(trace, () => {
    if (trace) { setCurrent(trace); load(trace); }
    history.reload();
    reloadApp();
  });

  const start = async () => {
    const out = await run(() => appApi<{ trace_id: string }>("/api/app/analyses", "POST", { ...f, account_id: f.account_id || null }));
    if (out) { setA(null); setCurrent(null); setTf(f.tf_entry); setTrace(out.trace_id); }
  };

  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <div className="grid content-start gap-5 lg:col-span-2">
        <Section title="Nouvelle analyse" icon={<Crosshair className="size-4" />} actions={<Usage k="analysis" label="Analyses" />}>
          <div className="grid gap-3 sm:grid-cols-4">
            <label className="field">
              <span>Symbole</span>
              <select className="input" value={f.symbol} onChange={(e) => setF({ ...f, symbol: e.target.value })}>
                {(sym?.symbols ?? [f.symbol]).map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </label>
            <label className="field"><span>Entrée</span><select className="input" value={f.tf_entry} onChange={(e) => setF({ ...f, tf_entry: e.target.value })}>{["M1", "M5", "M15"].map((x) => <option key={x}>{x}</option>)}</select></label>
            <label className="field"><span>Contexte</span><select className="input" value={f.tf_htf} onChange={(e) => setF({ ...f, tf_htf: e.target.value })}>{["H1", "H4", "D1"].map((x) => <option key={x}>{x}</option>)}</select></label>
            <label className="field">
              <span>Compte (risque)</span>
              <select className="input" value={f.account_id} onChange={(e) => setF({ ...f, account_id: e.target.value })}>
                <option value="">Premier compte</option>
                {(accounts ?? []).map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
              </select>
            </label>
          </div>
          <label className="field mt-3">
            <span>Votre lecture (facultatif)</span>
            <input className="input" maxLength={500} value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} placeholder="Ex. : je vois un sweep du PDL à Londres, j'attends un MSS en M5" />
          </label>
          <div className="mt-3 flex flex-wrap items-center gap-3">
            <button className="btn btn-primary btn-sm" disabled={busy || status === "running"} onClick={start}>Analyser</button>
            {!accounts?.length && <span className="text-xs text-gold-300">Sans compte de trading déclaré, le risk gate ne peut pas dimensionner la position.</span>}
          </div>
          {note}
          <div className="mt-3"><RunSteps steps={steps} status={status} /></div>
        </Section>
        {a ? <Card a={a} tf={tf} setTf={setTf} onDecided={() => { if (current) load(current); history.reload(); }} /> : current && <Spinner />}
      </div>

      <div className="grid content-start gap-5">
        <Section title="Analyses précédentes" icon={<History className="size-4" />}>
          {history.data?.length ? (
            <ul className="grid gap-1.5 text-sm">
              {history.data.map((r) => (
                <li key={r.id}>
                  <button className={`flex w-full flex-wrap items-center gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-white/[0.04] ${current === r.id ? "bg-white/[0.06]" : ""}`} onClick={() => { setTrace(null); setCurrent(r.id); }}>
                    <span className="font-medium">{r.symbol}</span>
                    <LabelChip map={SETUP_LABEL} k={r.label} />
                    {r.source === "tradingview" && <span className="chip">TradingView</span>}
                    <span className="ml-auto text-xs text-faint">{when(r.created_at)}</span>
                  </button>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">Aucune analyse.</p>}
        </Section>
        {app?.features.briefing && <Briefing />}
        {app?.features.tradingview ? <TradingView /> : (
          <Section title="Alertes TradingView" icon={<BellRing className="size-4" />}><p className="text-sm text-muted">Envoyer vos alertes TradingView à l&apos;Analyste est inclus à partir de l&apos;offre Pro Trader.</p></Section>
        )}
      </div>
    </div>
  );
}

function Card({ a, tf, setTf, onDecided }: { a: Analysis; tf: string; setTf: (v: string) => void; onDecided: () => void }) {
  const c = a.card;
  const { data: bars } = useLoad<{ bars: Bar[]; synthetic: boolean }>(c?.symbol ? `/api/app/bars/${encodeURIComponent(c.symbol)}?tf=${tf}&n=150` : null);
  if (a.status === "failed") return <Notice kind="error">L&apos;analyse a échoué : {a.error ?? "erreur inconnue"}.</Notice>;
  if (!c) return <Spinner label="Analyse en cours…" />;
  const cand = c.candidate;
  const ict = c.ict ?? ({} as SetupCard["ict"]);
  const levels: Level[] = [];
  const zones: Zone[] = [];
  for (const p of ict.unswept_pools ?? []) levels.push({ price: p.level, label: `${p.side} ${p.source}`, color: "#93a1b5", dash: true });
  if (ict.time?.midnight_open != null) levels.push({ price: ict.time.midnight_open, label: "Midnight open", color: "#8fcbff", dash: true });
  for (const g of ict.open_fvgs ?? []) zones.push({ top: g.top, bottom: g.bottom, label: `${g.kind === "BISI" ? "FVG haussier" : "FVG baissier"}${g.status === "inverted" ? " (inversé)" : ""}`, color: g.kind === "BISI" ? "rgb(75 224 138 / .09)" : "rgb(239 83 84 / .09)" });
  if (cand) {
    zones.push({ top: Math.max(...cand.entry_zone), bottom: Math.min(...cand.entry_zone), label: "Zone d'entrée", color: "rgb(79 176 255 / .16)" });
    levels.push({ price: cand.entry, label: "Entrée", color: "#4fb0ff" });
    levels.push({ price: cand.invalidation, label: "Invalidation", color: "#ef5354" });
    cand.targets.forEach((t, i) => levels.push({ price: t, label: `Objectif ${i + 1}`, color: "#4be08a" }));
  }
  const g = c.risk_gate;
  const expired = c.expires_at != null && c.expires_at < Date.now();
  return (
    <>
      <Section title={`${c.symbol} · ${cand ? `${MODEL_LABEL[cand.model] ?? cand.model} ${cand.direction === "long" ? "achat" : "vente"}` : "aucun setup"}`}
        actions={<><LabelChip map={SETUP_LABEL} k={c.label} /><span className="chip" title="Confiance calculée par les règles">Confiance {c.confidence} %</span></>}>
        <div className="mb-3 flex flex-wrap items-center gap-2 text-xs text-muted">
          <span>Données au {when(c.as_of)}</span>
          <Seg label="Unité de temps du graphique" value={tf} onChange={setTf} options={[["M1", "M1"], ["M5", "M5"], ["M15", "M15"], ["H1", "H1"]]} />
          {bars?.synthetic && <span className="chip chip-gold">prix simulés</span>}
        </div>
        {bars ? <Candles bars={bars.bars} levels={levels} zones={zones} label={`Graphique ${c.symbol} ${tf} avec les niveaux ICT`} /> : <Spinner />}
        <p className="mt-2 text-xs text-faint">Graphique aux cours actuels ; les niveaux sont ceux de l&apos;analyse.</p>
        <p className="mt-4 whitespace-pre-line text-sm leading-relaxed text-fg/90">{c.summary}</p>

        {cand && (
          <div className="mt-5 grid gap-5 sm:grid-cols-2">
            <div>
              <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Setup (calculé par le moteur)</h3>
              <Kv k="Entrée" v={n2(cand.entry, 5)} />
              <Kv k="Zone d'entrée" v={`${n2(cand.entry_zone[0], 5)} – ${n2(cand.entry_zone[1], 5)}`} />
              <Kv k="Invalidation" v={n2(cand.invalidation, 5)} />
              <Kv k="Objectifs" v={cand.targets.map((t) => n2(t, 5)).join(" · ")} />
              <Kv k="Rapport rendement / risque" v={`${n2(cand.rr)} R`} />
              <Kv k="Score des règles" v={`${cand.rule_score} / ${cand.min_score} requis${cand.relaxed ? " (passe relâchée)" : ""}`} />
              <Kv k="Biais de fond" v={BIAS[cand.htf_bias] ?? cand.htf_bias} />
            </div>
            <div>
              <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Règles</h3>
              <ul className="grid gap-1 text-sm">
                {cand.rules_passed.map((r) => <li key={r} className="text-up-300">✓ {r}</li>)}
                {cand.rules_failed.map((r) => <li key={r} className="text-down-400">✗ {r}</li>)}
              </ul>
            </div>
          </div>
        )}

        <div className="mt-5 grid gap-5 sm:grid-cols-2">
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Contexte ICT</h3>
            {ict.time && <Kv k="Heure de New York" v={ict.time.ny_time} />}
            {ict.time && <Kv k="Killzone" v={ict.time.killzone ? KZ_LABEL[ict.time.killzone] ?? ict.time.killzone : "hors killzone"} />}
            {ict.time?.silver_bullet_window && <Kv k="Fenêtre Silver Bullet" v={ict.time.silver_bullet_window} />}
            {ict.time?.macro_window && <Kv k="Macro" v={ict.time.macro_window} />}
            {ict.htf_bias && <Kv k="Biais de fond" v={BIAS[ict.htf_bias] ?? ict.htf_bias} />}
            {ict.premium_discount && <Kv k="Prix dans le range" v={PD[ict.premium_discount] ?? ict.premium_discount} />}
            {ict.time && <Kv k="Phase AMD" v={AMD[ict.time.amd_phase] ?? ict.time.amd_phase} />}
          </div>
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Alignement avec votre plan</h3>
            <Bullets items={c.plan_alignment} empty="—" />
            {c.points_to_check.length > 0 && (
              <>
                <h3 className="mb-2 mt-4 text-xs font-semibold uppercase tracking-wider text-faint">Points à vérifier vous-même</h3>
                <Bullets items={c.points_to_check} />
              </>
            )}
          </div>
        </div>
        {!cand && (ict.rejections ?? []).length > 0 && (
          <div className="mt-5">
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Pourquoi aucun setup</h3>
            <Bullets items={ict.rejections.slice(0, 8)} />
          </div>
        )}
        {c.stats && (
          <p className="mt-5 text-sm text-muted">
            Sur vos trades de ce modèle : {c.stats.n} trade(s), réussite {pc(c.stats.win_rate)}, espérance {rr(c.stats.expectancy_r)}{c.stats.sample_warning ? " (échantillon faible)" : ""}.
          </p>
        )}
        {c.debate?.decision && (
          <Notice kind={c.debate.decision === "downgrade" ? "warn" : "info"} className="mt-4">
            Débat contradictoire : {c.debate.decision === "downgrade" ? "l'avis a été rétrogradé" : "l'avis est maintenu"}. <Bullets items={c.debate.reasons ?? []} />
          </Notice>
        )}
        {c.caveats.length > 0 && <Notice kind="warn" className="mt-4"><Bullets items={c.caveats} /></Notice>}
        <Disclaimer text={c.disclaimer} narratedBy={c.narrated_by} />
      </Section>

      {g && (
        <Section title="Risk gate" icon={<ShieldCheck className="size-4" />} actions={<LabelChip map={GATE_LABEL} k={g.decision} />}>
          <div className="grid gap-5 sm:grid-cols-2">
            <div>
              <Kv k="Taille maximale" v={`${n2(g.max_lots)} lot(s)`} />
              <Kv k="Risque" v={`${money(g.risk_amount)} (${n2(g.risk_pct)} %)`} />
              <Kv k="Profil" v={<>{g.profile}{g.profile !== "generic" && !g.profile_verified && <span className="chip chip-gold ml-2">à vérifier</span>}</>} />
            </div>
            <div className="grid gap-3">
              {g.violations.length > 0 && <Notice kind="error"><Bullets items={g.violations} /></Notice>}
              {g.warnings.length > 0 && <Notice kind="warn"><Bullets items={g.warnings} /></Notice>}
            </div>
          </div>
          <details className="mt-3 text-sm text-muted">
            <summary className="cursor-pointer text-xs font-semibold uppercase tracking-wider text-faint">Règles appliquées</summary>
            <div className="mt-2"><Bullets items={g.rules_applied} /></div>
          </details>
        </Section>
      )}

      {a.status === "waiting" && !a.decision && (
        <Decision id={a.id} expired={expired} expiresAt={c.expires_at} onDone={onDecided} />
      )}
      {a.decision && (
        <Notice kind="info">Votre décision : {a.decision === "approved" ? "setup retenu" : a.decision === "rejected" ? "setup écarté" : a.decision}. Elle est enregistrée dans votre journal d&apos;audit.</Notice>
      )}
    </>
  );
}

function Decision({ id, expired, expiresAt, onDone }: { id: string; expired: boolean; expiresAt: number | null; onDone: () => void }) {
  const [comment, setComment] = useState("");
  const { busy, run, note } = useAction();
  const decide = async (decision: "approved" | "rejected") => {
    if (await run(() => appApi(`/api/app/analyses/${id}/decision`, "POST", { decision, comment }))) onDone();
  };
  return (
    <div className="card-gold p-5">
      <h2 className="font-semibold">Votre décision</h2>
      <p className="mt-1 text-sm text-muted">
        La plateforme ne passe aucun ordre. Vous exécutez vous-même dans votre terminal ; votre choix est enregistré pour le Coach et le journal d&apos;audit.
        {expiresAt && <> Carte valable jusqu&apos;à {when(expiresAt)}.</>}
      </p>
      {expired ? <p className="mt-3 text-sm text-gold-300">Carte expirée : relancez une analyse.</p> : (
        <>
          <input className="input mt-3" maxLength={300} value={comment} onChange={(e) => setComment(e.target.value)} placeholder="Commentaire (facultatif)" />
          <div className="mt-3 flex flex-wrap gap-2">
            <button className="btn btn-primary btn-sm" disabled={busy} onClick={() => decide("approved")}>Je retiens ce setup</button>
            <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => decide("rejected")}>Je l&apos;écarte</button>
          </div>
        </>
      )}
      {note}
    </div>
  );
}

type BriefingResp = { briefings: { label: string; summary: string; session: string; as_of: number; caveats: string[] }[]; events: { time_utc: number; currency: string; title: string; impact: string }[] };

function Briefing() {
  const { data } = useLoad<BriefingResp>("/api/app/briefing");
  const b = data?.briefings[0];
  return (
    <Section title="Briefing et calendrier" icon={<CalendarClock className="size-4" />}>
      {b ? (
        <div className="mb-4 text-sm">
          <div className="mb-1 text-xs text-faint">{b.session === "london" ? "Londres" : "New York"} · {when(b.as_of)}</div>
          <p className="leading-relaxed text-fg/85">{b.summary}</p>
        </div>
      ) : <p className="mb-4 text-sm text-muted">Aucun briefing publié.</p>}
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Annonces des 48 prochaines heures</h3>
      {data?.events.length ? (
        <ul className="grid gap-1 text-sm">
          {data.events.slice(0, 12).map((e, i) => (
            <li key={i} className="flex gap-2">
              <span className="num w-28 shrink-0 text-muted">{when(e.time_utc)}</span>
              <span className={`chip shrink-0 ${e.impact === "high" ? "chip-red" : e.impact === "medium" ? "chip-gold" : ""}`}>{e.currency}</span>
              <span className="min-w-0 truncate">{e.title}</span>
            </li>
          ))}
        </ul>
      ) : <p className="text-sm text-muted">Aucune annonce chargée.</p>}
    </Section>
  );
}

function TradingView() {
  const { data, reload } = useLoad<{ id: string; enabled: boolean; created_at: number }[]>("/api/app/tradingview/hooks");
  const [created, setCreated] = useState<{ url: string; message: string } | null>(null);
  const { busy, run, note } = useAction();
  const abs = (u: string) => (u.startsWith("/") && typeof window !== "undefined" ? window.location.origin + u : u);
  return (
    <Section title="Alertes TradingView" icon={<BellRing className="size-4" />}>
      <p className="mb-3 text-sm text-muted">Une alerte TradingView déclenche une analyse par les règles ICT et vous notifie. Elle ne passe jamais d&apos;ordre.</p>
      {created && (
        <div className="mb-3 grid gap-3">
          <Notice kind="warn">Copiez ces valeurs maintenant : le jeton n&apos;est affiché qu&apos;une fois.</Notice>
          <CopyField label="URL du webhook" value={abs(created.url)} />
          <CopyField label="Message de l'alerte" value={created.message} secret />
        </div>
      )}
      <ul className="mb-3 grid gap-1.5 text-sm">
        {(data ?? []).filter((h) => h.enabled).map((h) => (
          <li key={h.id} className="flex items-center gap-2">
            <span className="text-muted">Webhook créé {when(h.created_at)}</span>
            <button className="ml-auto text-faint hover:text-down-400" aria-label="Désactiver ce webhook" disabled={busy}
              onClick={async () => { if (await run(() => appApi(`/api/app/tradingview/hooks/${h.id}`, "DELETE"))) reload(); }}>
              <Trash2 className="size-4" aria-hidden />
            </button>
          </li>
        ))}
      </ul>
      <button className="btn btn-ghost btn-sm" disabled={busy} onClick={async () => { const out = await run(() => appApi<{ url: string; message: string }>("/api/app/tradingview/hooks", "POST")); if (out) { setCreated(out); reload(); } }}>Créer un webhook</button>
      {note}
    </Section>
  );
}
