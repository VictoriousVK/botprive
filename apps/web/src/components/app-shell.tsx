"use client";

import { Bell, BookOpen, Cpu, Crosshair, FlaskConical, GraduationCap, LayoutDashboard, Lock, Settings, ShieldCheck, Sparkles } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { Notice, Spinner } from "@/components/ui";
import { FEATURE_OFFER, PLAN_LABEL, appApi, type AppMe } from "@/lib/app";
import { useSession } from "@/lib/session";

const TABS: [string, string, typeof LayoutDashboard][] = [
  ["/app/", "Tableau de bord", LayoutDashboard],
  ["/app/journal/", "Journal", BookOpen],
  ["/app/revue/", "Coach", Sparkles],
  ["/app/analyse/", "Analyse ICT", Crosshair],
  ["/app/risque/", "Risque", ShieldCheck],
  ["/app/mentor/", "Mentor", GraduationCap],
  ["/app/labo/", "Labo", FlaskConical],
  ["/app/ea/", "Usine EA", Cpu],
  ["/app/reglages/", "Réglages", Settings],
];

type Ctx = { app: AppMe | null; reload: () => Promise<void> };
const AppCtx = createContext<Ctx>({ app: null, reload: async () => {} });
export const useApp = () => useContext(AppCtx);

export function AppShell({ title, subtitle, feature, children }: { title: string; subtitle?: string; feature?: string; children: ReactNode }) {
  const { me, ready } = useSession();
  const [app, setApp] = useState<AppMe | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [unread, setUnread] = useState(0);
  const path = usePathname();

  const reload = useCallback(async () => {
    try {
      setApp(await appApi<AppMe>("/api/app/me"));
      const n = await appApi<{ unread: number }>("/api/app/notifications");
      setUnread(n.unread);
      setErr(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Erreur");
    }
  }, []);

  useEffect(() => {
    if (me) reload();
  }, [me, reload]);

  if (!ready) return <div className="container-x py-14"><Spinner /></div>;
  if (!me) {
    return (
      <div className="container-x grid min-h-[60vh] place-items-center py-14">
        <div className="card max-w-md p-8 text-center">
          <Lock className="mx-auto size-8 text-brand-300" aria-hidden />
          <h1 className="mt-4 font-[family-name:var(--font-display)] text-xl font-bold">Votre espace de trading</h1>
          <p className="mt-2 text-sm text-muted">Journal, Coach IA, analyse ICT et garde-fou de risque : connectez-vous ou créez un compte gratuit.</p>
          <div className="mt-6 flex justify-center gap-3">
            <Link href="/compte/?vue=connexion" className="btn btn-ghost btn-sm">Connexion</Link>
            <Link href="/compte/?vue=inscription" className="btn btn-primary btn-sm">Créer un compte</Link>
          </div>
        </div>
      </div>
    );
  }
  const locked = feature && app && !app.features[feature];
  return (
    <AppCtx.Provider value={{ app, reload }}>
      <div className="border-b border-white/5 bg-ink-900/60">
        <div className="container-x flex items-center gap-3 pt-5">
          <div className="min-w-0 flex-1">
            <h1 className="truncate font-[family-name:var(--font-display)] text-xl font-bold sm:text-2xl">{title}</h1>
            {subtitle && <p className="mt-0.5 truncate text-sm text-muted">{subtitle}</p>}
          </div>
          {app && <Link href="/compte/" className="chip chip-blue shrink-0 hover:border-brand-400/60" title="Mon compte, mon abonnement">{PLAN_LABEL[app.plan] ?? app.plan}</Link>}
          <Link href="/app/reglages/#notifications" className="relative shrink-0 rounded-lg p-2 text-muted hover:text-white" aria-label={`Notifications : ${unread} non lues`}>
            <Bell className="size-5" aria-hidden />
            {unread > 0 && <span className="absolute right-1 top-1 grid size-4 place-items-center rounded-full bg-down-500 text-[10px] font-bold text-white">{unread > 9 ? "9+" : unread}</span>}
          </Link>
        </div>
        <nav className="container-x mt-3 flex gap-1 overflow-x-auto pb-2 [scrollbar-width:none]" aria-label="Espace de trading">
          {TABS.map(([href, label, Icon]) => {
            const active = href === "/app/" ? path === "/app" || path === "/app/" : path?.startsWith(href.slice(0, -1));
            return (
              <Link key={href} href={href} aria-current={active ? "page" : undefined}
                className={`flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${active ? "bg-white/[0.07] text-white" : "text-muted hover:text-white"}`}>
                <Icon className="size-4" aria-hidden /> {label}
              </Link>
            );
          })}
        </nav>
      </div>
      <div className="app-space container-x py-6 sm:py-8">
        {err && <Notice kind="error" className="mb-4">{err}</Notice>}
        {app?.market.synthetic && <Notice kind="warn" className="mb-4">Prix simulés sur cette plateforme : les analyses sont des démonstrations, sans valeur de marché.</Notice>}
        {locked ? <Locked feature={feature!} /> : app || !feature ? children : <Spinner />}
      </div>
    </AppCtx.Provider>
  );
}

function Locked({ feature }: { feature: string }) {
  return (
    <div className="card mx-auto max-w-lg p-8 text-center">
      <Lock className="mx-auto size-8 text-gold-400" aria-hidden />
      <h2 className="mt-4 text-lg font-semibold">Fonction incluse à partir de l&apos;offre {FEATURE_OFFER[feature] ?? "supérieure"}</h2>
      <p className="mt-2 text-sm text-muted">Votre journal, vos statistiques et le Coach restent disponibles avec le compte gratuit.</p>
      <Link href="/tarifs/" className="btn btn-primary btn-sm mt-6">Voir les offres</Link>
    </div>
  );
}

/** Monthly usage of one capped function, e.g. "Analyses : 3 / 20". */
export function Usage({ k, label }: { k: string; label: string }) {
  const { app } = useApp();
  if (!app) return null;
  const cap = app.limits[k];
  const used = app.usage[k]?.count ?? 0;
  if (!cap) return null; // 0: not included, or unlimited
  return <span className="chip" title="Plafond mensuel de votre offre">{label} : {used} / {cap || "—"} ce mois</span>;
}
