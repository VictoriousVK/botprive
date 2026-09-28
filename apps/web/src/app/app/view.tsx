"use client";

import { ArrowRight, BookOpen, CalendarClock, Crosshair, MessageSquareText, ShieldCheck, Sparkles, TrendingUp } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { AppShell, Usage, useApp } from "@/components/app-shell";
import { Bullets, Gauge, GroupTable, LabelChip, Section, useAction, useLoad } from "@/components/app-ui";
import { AreaChart, Notice, Spinner, Stat } from "@/components/ui";
import { BEHAVIOR_LABEL, COACH_LABEL, MODEL_LABEL, SETUP_LABEL, appApi, n2, pc, rr, tone, when, type Overview } from "@/lib/app";

const BRIEF_LABEL: Record<string, [string, string]> = { RISK_ON: ["Appétit pour le risque", "chip-green"], RISK_OFF: ["Aversion au risque", "chip-red"], NEUTRAL: ["Neutre", ""], INSUFFICIENT_EVIDENCE: ["Données insuffisantes", ""] };

export function DashboardView() {
  return (
    <AppShell title="Tableau de bord" subtitle="Vos 30 derniers jours, vos leçons et vos limites de risque">
      <Dashboard />
    </AppShell>
  );
}

function Dashboard() {
  const { app } = useApp();
  const { data: o, error } = useLoad<Overview>("/api/app/overview");
  if (error) return <Notice kind="error">{error}</Notice>;
  if (!o || !app) return <Spinner />;
  const k = o.stats?.kpis;
  const noAccount = !o.accounts?.length;
  return (
    <div className="grid gap-5">
      {noAccount && (
        <Notice kind="info">
          Commencez par la mise en route (profil, prop firm, plan de risque, premier compte), puis importez votre historique MT5 : statistiques, Coach et garde-fou se calculent à partir de vos trades.{" "}
          <Link href="/app/bienvenue/" className="font-semibold text-brand-300 underline-offset-2 hover:underline">Mise en route</Link>
          {" · "}
          <Link href="/app/journal/?vue=comptes" className="font-semibold text-brand-300 underline-offset-2 hover:underline">Ajouter un compte</Link>
        </Notice>
      )}
      <Ask />
      <div className="grid gap-5 lg:grid-cols-3">
        <Section title="Performance (30 jours)" icon={<TrendingUp className="size-4" />} className="lg:col-span-2"
          actions={<Link href="/app/journal/?vue=stats" className="btn btn-ghost btn-sm">Détails <ArrowRight className="size-3.5" aria-hidden /></Link>}>
          {k && k.n ? (
            <>
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
                <Stat label="Trades clôturés" value={k.n} />
                <Stat label="Taux de réussite" value={pc(k.win_rate)} hint={k.win_rate_ci95 ? `Intervalle à 95 % : ${pc(k.win_rate_ci95[0])} à ${pc(k.win_rate_ci95[1])}` : undefined} />
                <Stat label="Espérance" value={rr(k.expectancy_r)} tone={tone(k.expectancy_r)} />
                <Stat label="Profit factor" value={n2(k.profit_factor)} />
                <Stat label="Résultat net" value={n2(k.net_total)} tone={tone(k.net_total)} />
                <Stat label="Drawdown max" value={k.max_drawdown_r == null ? "—" : `${n2(k.max_drawdown_r)} R`} />
              </div>
              {(k.insufficient || k.sample_warning) && (
                <p className="mt-3 text-xs text-gold-300">Échantillon faible : ces chiffres varient beaucoup d&apos;un mois à l&apos;autre, n&apos;en tirez pas de conclusion.</p>
              )}
              <div className="mt-5">
                <AreaChart points={(o.stats?.equity ?? []).map((p) => ({ t: p.t, v: p.net }))} label="Courbe du résultat cumulé sur 30 jours" height={150} />
              </div>
            </>
          ) : (
            <p className="text-sm text-muted">Aucun trade clôturé sur 30 jours.</p>
          )}
        </Section>

        <Section title="Garde-fou" icon={<ShieldCheck className="size-4" />} actions={<Link href="/app/risque/" className="btn btn-ghost btn-sm">Ouvrir</Link>}>
          {o.guard ? (
            <div className="grid gap-4">
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <span className="font-medium">{o.guard.profile_label ?? o.guard.profile}</span>
                {o.guard.profile !== "generic" && !o.guard.profile_verified && <span className="chip chip-gold">À vérifier</span>}
              </div>
              <Gauge label="Perte journalière utilisée" value={o.guard.daily_used_pct} />
              <Gauge label="Perte maximale utilisée" value={o.guard.max_used_pct} />
              {o.guard.alerts.length > 0 && <Notice kind="warn">Seuil d&apos;alerte atteint : réduisez votre exposition ou arrêtez pour la journée.</Notice>}
            </div>
          ) : (
            <p className="text-sm text-muted">Renseignez le solde de départ de votre compte pour suivre vos limites de perte.</p>
          )}
        </Section>
      </div>

      <div className="grid gap-5 lg:grid-cols-3">
        <Section title="Comportements repérés" icon={<Sparkles className="size-4" />} className="lg:col-span-2"
          actions={<Link href="/app/revue/" className="btn btn-primary btn-sm">Revue du Coach</Link>}>
          {o.stats?.flags.length ? (
            <ul className="grid gap-2">
              {o.stats.flags.map((f) => (
                <li key={f.kind} className="flex gap-3 rounded-lg border border-white/5 bg-white/[0.02] p-3 text-sm">
                  <span className="chip chip-gold shrink-0">{BEHAVIOR_LABEL[f.kind] ?? f.kind}</span>
                  <span className="text-fg/85">{f.detail}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted">Aucun écart au plan repéré sur 30 jours.</p>
          )}
          {o.last_review && (
            <p className="mt-4 flex flex-wrap items-center gap-2 text-sm text-muted">
              Dernière revue : {when(o.last_review.created_at)} <LabelChip map={COACH_LABEL} k={o.last_review.label} />
            </p>
          )}
          <div className="mt-4 flex flex-wrap gap-2"><Usage k="coach" label="Revues" /></div>
        </Section>

        <Section title="Leçons actives" icon={<BookOpen className="size-4" />}>
          {o.lessons?.length ? (
            <ul className="grid gap-2 text-sm">
              {o.lessons.map((l) => (
                <li key={l.id} className="rounded-lg border border-white/5 bg-white/[0.02] p-3">
                  {l.status === "proposed" && <span className="chip chip-blue mb-1.5">À valider</span>}
                  <p className="leading-relaxed text-fg/85">{l.text}</p>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted">Les leçons que vous validez après une revue apparaissent ici.</p>
          )}
        </Section>
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <Section title="Dernières analyses" icon={<Crosshair className="size-4" />} actions={<Link href="/app/analyse/" className="btn btn-ghost btn-sm">Analyser</Link>}>
          {!app.features.analysis ? (
            <p className="text-sm text-muted">L&apos;Analyste de setup ICT est inclus à partir de l&apos;offre Starter.</p>
          ) : o.analyses?.length ? (
            <ul className="grid gap-2 text-sm">
              {o.analyses.map((a) => (
                <li key={a.id}>
                  <Link href={`/app/analyse/?id=${a.id}`} className="flex flex-wrap items-center gap-2 rounded-lg border border-white/5 bg-white/[0.02] p-3 hover:border-brand-400/40">
                    <span className="font-semibold">{a.symbol}</span>
                    <span className="text-muted">{a.model ? MODEL_LABEL[a.model] ?? a.model : "—"}</span>
                    <LabelChip map={SETUP_LABEL} k={a.label} />
                    <span className="ml-auto text-xs text-faint">{when(a.created_at)}</span>
                  </Link>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted">Aucune analyse pour l&apos;instant.</p>
          )}
          {app.features.analysis && <div className="mt-4"><Usage k="analysis" label="Analyses" /></div>}
        </Section>

        <Section title="Briefing de pré-session" icon={<CalendarClock className="size-4" />}>
          {!app.features.briefing ? (
            <p className="text-sm text-muted">Le briefing et le calendrier économique sont inclus à partir de l&apos;offre Starter.</p>
          ) : o.briefing ? (
            <div className="grid gap-3 text-sm">
              <div className="flex items-center gap-2"><LabelChip map={BRIEF_LABEL} k={o.briefing.label} /><span className="text-muted">{o.briefing.session === "london" ? "Londres" : "New York"}</span></div>
              <p className="leading-relaxed text-fg/85">{o.briefing.summary}</p>
              {o.briefing.high_impact_events.length > 0 && (
                <div>
                  <div className="mb-1 text-xs font-semibold uppercase tracking-wider text-faint">Annonces à fort impact</div>
                  <Bullets items={o.briefing.high_impact_events.map((e) => `${when(e.time_utc)} · ${e.currency} · ${e.title}`)} />
                </div>
              )}
            </div>
          ) : (
            <p className="text-sm text-muted">Pas encore de briefing publié pour cette session.</p>
          )}
        </Section>
      </div>

      {o.stats?.by_killzone.length ? (
        <Section title="Par killzone (30 jours)">
          <GroupTable rows={o.stats.by_killzone} keyLabel="Killzone" />
        </Section>
      ) : null}
    </div>
  );
}

type Route = { intent: string; target: string; reason: string; confidence: number; by: string; reply?: string; menu?: string[] };
const TARGET_LINK: Record<string, [string, string]> = {
  coach: ["/app/revue/", "Ouvrir le Coach"], analyste: ["/app/analyse/", "Ouvrir l'Analyste"], mentor: ["/app/mentor/", "Demander au Mentor"], risk_service: ["/app/risque/", "Ouvrir le calculateur de risque"],
  research: ["/app/analyse/", "Voir le briefing"], ea_factory: ["/app/ea/", "Ouvrir l'usine EA"], support: ["/compte/", "Mon compte"],
};
const MENU_LABEL: Record<string, [string, string]> = {
  journal_review: ["/app/revue/", "Revue de mon journal"], setup_analysis: ["/app/analyse/", "Analyse d'un setup"], learn: ["/app/mentor/", "Question de cours"], risk_check: ["/app/risque/", "Taille de position"],
};

/** Free-text entry point: the router picks the right service (rules first, then a small model). */
function Ask() {
  const [text, setText] = useState("");
  const [route, setRoute] = useState<Route | null>(null);
  const { busy, run, note } = useAction();
  const go = async () => {
    const r = await run(() => appApi<Route>("/api/app/ask", "POST", { message: text }));
    if (r) setRoute(r);
  };
  const link = route && TARGET_LINK[route.target];
  return (
    <div className="card p-4 sm:p-5">
      <form className="flex flex-col gap-2 sm:flex-row" onSubmit={(e) => { e.preventDefault(); if (text.trim().length >= 3) go(); }}>
        <label className="sr-only" htmlFor="ask">Que voulez-vous faire ?</label>
        <div className="relative flex-1">
          <MessageSquareText className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-faint" aria-hidden />
          <input id="ask" className="input pl-9" maxLength={1000} value={text} onChange={(e) => setText(e.target.value)} placeholder="Ex. : revois ma semaine, analyse l'or en M5, combien de lots avec un stop à 12 points ?" />
        </div>
        <button className="btn btn-primary btn-sm" disabled={busy || text.trim().length < 3}>Orienter</button>
      </form>
      {note}
      {route && (
        <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
          {route.reply ? <Notice kind="warn" className="w-full">{route.reply}</Notice> : link ? (
            <>
              <span className="text-muted">{route.reason}</span>
              <Link href={link[0]} className="btn btn-ghost btn-sm">{link[1]} <ArrowRight className="size-3.5" aria-hidden /></Link>
            </>
          ) : (
            <>
              <span className="text-muted">Choisissez un service :</span>
              {(route.menu ?? []).map((m) => MENU_LABEL[m] && <Link key={m} href={MENU_LABEL[m][0]} className="chip chip-blue">{MENU_LABEL[m][1]}</Link>)}
            </>
          )}
        </div>
      )}
    </div>
  );
}
