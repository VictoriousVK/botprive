"use client";

import { Bell, Database, KeyRound, ListChecks, PlugZap, UserRound } from "lucide-react";
import { useEffect, useState } from "react";
import { AppShell, useApp } from "@/components/app-shell";
import { CopyField, Section, useAction, useLoad } from "@/components/app-ui";
import { Notice, Spinner } from "@/components/ui";
import { KZ_LABEL, MODEL_LABEL, PLAN_LABEL, appApi, n2, when, type Account, type Notification, type Profile, type TradingPlan } from "@/lib/app";

const USAGE_LABEL: Record<string, string> = { coach: "Revues du Coach", analysis: "Analyses de setup", mentor: "Questions au Mentor", backtest: "Backtests du labo", ea_run: "Générations d'EA", briefing: "Briefings", trades_per_month: "Trades importés" };
const NOTIF_KIND: Record<string, string> = { review: "Revues du Coach", analysis: "Analyses", tradingview: "Alertes TradingView", risk_alert: "Alertes de risque", briefing: "Briefings", lab: "Laboratoire", ea_factory: "Usine EA", billing: "Abonnement" };

export function SettingsView() {
  return (
    <AppShell title="Réglages" subtitle="Plan de trading, profil, connexions MT5, notifications et données">
      <Settings />
    </AppShell>
  );
}

function Settings() {
  const { app } = useApp();
  useEffect(() => {
    if (window.location.hash) document.getElementById(window.location.hash.slice(1))?.scrollIntoView();
  }, []);
  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <div className="grid content-start gap-5">
        <PlanForm />
        <ProfileForm />
        <UsagePanel />
      </div>
      <div className="grid content-start gap-5">
        <Notifications />
        {app?.features.mt5_sync ? <Mt5Sync /> : (
          <Section title="Synchronisation MT5" icon={<PlugZap className="size-4" />}><p className="text-sm text-muted">L&apos;EA Journal Sync (lecture seule) est inclus à partir de l&apos;offre Pro Trader. L&apos;import de fichier reste disponible dans le Journal.</p></Section>
        )}
        {app?.features.public_api && <ApiTokens />}
        <DataRights />
      </div>
    </div>
  );
}

// ---------------- trading plan ----------------
function PlanForm() {
  const { data } = useLoad<{ plan: TradingPlan; killzones: string[]; setups: string[] }>("/api/app/plan");
  const [p, setP] = useState<TradingPlan | null>(null);
  const [markets, setMarkets] = useState("");
  const [rules, setRules] = useState("");
  const { busy, run, note } = useAction();
  useEffect(() => {
    if (data) { setP(data.plan); setMarkets(data.plan.markets.join(", ")); setRules((data.plan.rules ?? []).join("\n")); }
  }, [data]);
  if (!p || !data) return <Section title="Plan de trading" icon={<ListChecks className="size-4" />}><Spinner /></Section>;
  const toggle = (k: "killzones" | "setups", v: string) => setP({ ...p, [k]: p[k].includes(v) ? p[k].filter((x) => x !== v) : [...p[k], v] });
  const numField = (k: keyof TradingPlan, label: string, step = "0.1") => (
    <label className="field"><span>{label}</span><input className="input" type="number" step={step} value={String(p[k])} onChange={(e) => setP({ ...p, [k]: Number(e.target.value) })} /></label>
  );
  const save = () => run(() => appApi("/api/app/plan", "PUT", { ...p, markets: markets.split(/[,\s]+/).filter(Boolean), rules: rules.split("\n").map((x) => x.trim()).filter(Boolean) }), "Plan enregistré");
  return (
    <Section title="Plan de trading" icon={<ListChecks className="size-4" />}>
      <p className="mb-4 text-sm text-muted">Le Coach, le garde-fou et l&apos;Analyste comparent vos trades à ce plan. Il vous appartient : ajustez-le à votre méthode.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="field sm:col-span-2"><span>Marchés</span><input className="input" value={markets} onChange={(e) => setMarkets(e.target.value)} /></label>
        {numField("risk_per_trade_pct", "Risque par trade (%)")}
        {numField("max_daily_loss_pct", "Perte journalière maximale (%)")}
        {numField("max_trades_per_day", "Trades par jour au plus", "1")}
        {numField("min_rr", "Rendement / risque minimal (R)")}
        {numField("revenge_minutes", "Délai après une perte (minutes)", "1")}
        {numField("size_up_factor", "Hausse de taille signalée à partir de (×)")}
        <fieldset className="field sm:col-span-2">
          <span>Killzones tradées</span>
          <div className="flex flex-wrap gap-1.5">
            {data.killzones.map((k) => <button key={k} type="button" aria-pressed={p.killzones.includes(k)} className={`chip ${p.killzones.includes(k) ? "chip-blue" : ""}`} onClick={() => toggle("killzones", k)}>{KZ_LABEL[k] ?? k}</button>)}
          </div>
        </fieldset>
        <fieldset className="field sm:col-span-2">
          <span>Setups</span>
          <div className="flex flex-wrap gap-1.5">
            {data.setups.map((k) => <button key={k} type="button" aria-pressed={p.setups.includes(k)} className={`chip ${p.setups.includes(k) ? "chip-blue" : ""}`} onClick={() => toggle("setups", k)}>{MODEL_LABEL[k] ?? k}</button>)}
          </div>
        </fieldset>
        <label className="field sm:col-span-2"><span>Règles personnelles (une par ligne, 15 au plus)</span><textarea className="input min-h-24" value={rules} onChange={(e) => setRules(e.target.value)} placeholder={"Pas de trade dans les 15 minutes autour du NFP\nJamais plus de 2 pertes d'affilée dans la journée"} /></label>
      </div>
      <button className="btn btn-primary btn-sm mt-4" disabled={busy} onClick={save}>Enregistrer le plan</button>
      {note}
    </Section>
  );
}

// ---------------- profile ----------------
function ProfileForm() {
  const { data } = useLoad<Profile>("/api/app/profile");
  const [p, setP] = useState<Profile | null>(null);
  const { busy, run, note } = useAction();
  useEffect(() => { if (data) setP(data); }, [data]);
  if (!p) return null;
  return (
    <Section title="Profil" icon={<UserRound className="size-4" />}>
      <p className="mb-4 text-sm text-muted">Déclaré par vous, jamais déduit : il adapte le niveau des explications.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="field"><span>Niveau</span>
          <select className="input" value={p.level} onChange={(e) => setP({ ...p, level: e.target.value })}>
            <option value="debutant">Débutant</option><option value="intermediaire">Intermédiaire</option><option value="confirme">Confirmé</option><option value="professionnel">Professionnel</option>
          </select>
        </label>
        <label className="field"><span>Expérience (mois)</span><input className="input" type="number" min={0} max={600} value={p.experience_months} onChange={(e) => setP({ ...p, experience_months: Number(e.target.value) })} /></label>
        <label className="field"><span>Prop firm (facultatif)</span><input className="input" maxLength={60} value={p.prop_firm ?? ""} onChange={(e) => setP({ ...p, prop_firm: e.target.value || null })} /></label>
        <label className="field"><span>Langue</span><select className="input" value={p.language} onChange={(e) => setP({ ...p, language: e.target.value as "fr" | "en" })}><option value="fr">Français</option><option value="en">English</option></select></label>
        <label className="flex items-center gap-2 text-sm text-muted"><input type="checkbox" checked={p.trades_manually} onChange={(e) => setP({ ...p, trades_manually: e.target.checked })} /> Je trade manuellement</label>
        <label className="flex items-center gap-2 text-sm text-muted"><input type="checkbox" checked={p.uses_eas} onChange={(e) => setP({ ...p, uses_eas: e.target.checked })} /> J&apos;utilise des EA</label>
      </div>
      <button className="btn btn-primary btn-sm mt-4" disabled={busy} onClick={() => run(() => appApi("/api/app/profile", "PUT", p), "Profil enregistré")}>Enregistrer</button>
      {note}
    </Section>
  );
}

function UsagePanel() {
  const { app } = useApp();
  if (!app) return null;
  const keys = Object.keys(app.limits).filter((k) => k in USAGE_LABEL);
  return (
    <Section title={`Offre ${PLAN_LABEL[app.plan] ?? app.plan} · ${app.month}`}>
      <ul className="grid gap-2 text-sm">
        {keys.map((k) => {
          const cap = app.limits[k];
          const used = app.usage[k]?.count ?? 0;
          return (
            <li key={k} className="flex justify-between gap-3 border-b border-white/5 pb-1.5 last:border-0">
              <span className="text-muted">{USAGE_LABEL[k]}</span>
              <span className="num">{k === "trades_per_month" ? (cap ? `${cap} par mois` : "illimité") : cap === 0 ? "non inclus" : `${used} / ${cap}`}</span>
            </li>
          );
        })}
      </ul>
      <p className="mt-3 text-xs text-faint">Les plafonds se renouvellent chaque mois. Version des agents : <span className="num">{app.manifest.slice(0, 12)}</span></p>
    </Section>
  );
}

// ---------------- notifications ----------------
type NotifResp = { items: Notification[]; unread: number; telegram: { linked: boolean; prefs: Record<string, boolean> } | null; telegram_available: boolean };

function Notifications() {
  const { reload: reloadApp } = useApp();
  const { data, reload } = useLoad<NotifResp>("/api/app/notifications");
  const [link, setLink] = useState<{ code: string; link: string | null; instructions: string } | null>(null);
  const { busy, run, note } = useAction();
  const markRead = async () => { if (await run(() => appApi("/api/app/notifications/read", "POST"))) { reload(); reloadApp(); } };
  const setPref = async (k: string, v: boolean) => {
    if (!data?.telegram) return;
    const prefs = { ...data.telegram.prefs, [k]: v };
    if (await run(() => appApi("/api/app/notifications/telegram", "PUT", { prefs }))) reload();
  };
  return (
    <Section title="Notifications" icon={<Bell className="size-4" />} id="notifications"
      actions={data && data.unread > 0 ? <button className="btn btn-ghost btn-sm" disabled={busy} onClick={markRead}>Tout marquer comme lu</button> : undefined}>
      {!data ? <Spinner /> : (
        <div className="grid gap-4">
          {data.items.length ? (
            <ul className="grid max-h-80 gap-2 overflow-y-auto text-sm">
              {data.items.map((n) => (
                <li key={n.id} className={`rounded-lg border p-3 ${n.read_at ? "border-white/5" : "border-brand-400/30 bg-brand-400/5"}`}>
                  <div className="flex items-baseline gap-2"><span className="font-medium">{n.title}</span><span className="ml-auto shrink-0 text-xs text-faint">{when(n.created_at)}</span></div>
                  {n.body && <p className="mt-1 text-muted">{n.body}</p>}
                  {n.link && n.link.startsWith("/") && <a href={n.link} className="mt-1 inline-block text-xs text-brand-300 hover:underline">Ouvrir</a>}
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">Aucune notification.</p>}
          <div className="border-t border-white/5 pt-4">
            <h3 className="mb-2 text-sm font-semibold">Telegram</h3>
            {!data.telegram_available ? <p className="text-sm text-muted">Le bot Telegram n&apos;est pas encore configuré sur cette plateforme.</p> : data.telegram?.linked ? (
              <div className="grid gap-2">
                <p className="text-sm text-up-300">Compte Telegram relié.</p>
                <div className="grid grid-cols-2 gap-1.5">
                  {Object.entries(NOTIF_KIND).map(([k, l]) => (
                    <label key={k} className="flex items-center gap-2 text-sm text-muted"><input type="checkbox" checked={data.telegram?.prefs[k] ?? true} onChange={(e) => setPref(k, e.target.checked)} /> {l}</label>
                  ))}
                </div>
                <button className="btn btn-ghost btn-sm justify-self-start" disabled={busy} onClick={async () => { if (await run(() => appApi("/api/app/notifications/telegram", "DELETE"))) reload(); }}>Délier</button>
              </div>
            ) : (
              <div className="grid gap-2">
                <p className="text-sm text-muted">Recevez revues, alertes de risque et analyses sur Telegram.</p>
                {link ? (
                  <>
                    <CopyField label="Code à envoyer au bot" value={`/start ${link.code}`} />
                    {link.link && <a href={link.link} target="_blank" rel="noopener noreferrer" className="btn btn-primary btn-sm justify-self-start">Ouvrir le bot</a>}
                    <button className="btn btn-ghost btn-sm justify-self-start" onClick={reload}>J&apos;ai envoyé le code</button>
                  </>
                ) : (
                  <button className="btn btn-ghost btn-sm justify-self-start" disabled={busy} onClick={async () => { const out = await run(() => appApi<{ code: string; link: string | null; instructions: string }>("/api/app/notifications/telegram", "POST")); if (out) setLink(out); }}>Relier Telegram</button>
                )}
              </div>
            )}
          </div>
          {note}
        </div>
      )}
    </Section>
  );
}

// ---------------- MT5 ----------------
type Token = { id: string; kind: string; label: string; account_id: string | null; scopes: string[]; created_at: number; last_used_at: number | null };

function Mt5Sync() {
  const { data: accounts, reload: reloadAccounts } = useLoad<Account[]>("/api/app/accounts");
  const { data: tokens, reload } = useLoad<Token[]>("/api/app/tokens");
  const [account, setAccount] = useState("");
  const [shown, setShown] = useState<{ token: string; url: string } | null>(null);
  const [pwd, setPwd] = useState("");
  const { busy, run, note } = useAction();
  useEffect(() => { if (!account && accounts?.length) setAccount(accounts[0].id); }, [accounts, account]);
  const abs = (u: string) => (u.startsWith("/") ? window.location.origin + u : u);
  const acc = accounts?.find((a) => a.id === account);
  const sync = (tokens ?? []).filter((t) => t.kind === "ea_sync");
  return (
    <Section title="Synchronisation MT5" icon={<PlugZap className="size-4" />}>
      {!accounts?.length ? <p className="text-sm text-muted">Déclarez d&apos;abord un compte dans le Journal.</p> : (
        <div className="grid gap-4">
          <label className="field"><span>Compte</span><select className="input" value={account} onChange={(e) => { setAccount(e.target.value); setShown(null); }}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}</select></label>
          <div className="rounded-xl border border-white/5 bg-white/[0.02] p-4 text-sm">
            <h3 className="font-semibold">EA Journal Sync (recommandé)</h3>
            <ol className="mt-2 grid list-decimal gap-1 pl-5 text-muted">
              <li>Générez un jeton ci-dessous (il remplace le précédent de ce compte).</li>
              <li>Dans MT5 : Outils → Options → Expert Advisors → autorisez WebRequest pour l&apos;adresse de la plateforme.</li>
              <li>Placez <span className="num">JournalSync.mq5</span> sur un graphique du compte, collez l&apos;URL et le jeton.</li>
            </ol>
            <p className="mt-2 text-xs text-faint">L&apos;EA lit l&apos;historique et l&apos;équité, et ne contient aucune fonction de passage d&apos;ordre.</p>
            {shown ? (
              <div className="mt-3 grid gap-2">
                <Notice kind="warn">Copiez le jeton maintenant : il n&apos;est affiché qu&apos;une fois.</Notice>
                <CopyField label="URL" value={abs(shown.url)} />
                <CopyField label="Jeton" value={shown.token} secret />
              </div>
            ) : (
              <button className="btn btn-primary btn-sm mt-3" disabled={busy} onClick={async () => { const out = await run(() => appApi<{ token: string; url: string }>(`/api/app/accounts/${account}/sync-token`, "POST")); if (out) { setShown(out); reload(); reloadAccounts(); } }}>Générer un jeton</button>
            )}
          </div>
          <div className="rounded-xl border border-white/5 bg-white/[0.02] p-4 text-sm">
            <h3 className="font-semibold">Mot de passe investisseur (pont Windows)</h3>
            <p className="mt-1 text-muted">Pour les comptes lus par le pont MT5 de la plateforme. Donnez uniquement le mot de passe <strong>investisseur</strong> (lecture seule), jamais le mot de passe principal. Il est chiffré et n&apos;est jamais réaffiché.</p>
            {acc?.has_secret ? (
              <div className="mt-3 flex flex-wrap items-center gap-2">
                <span className="chip chip-green">enregistré</span>
                <button className="btn btn-ghost btn-sm" disabled={busy} onClick={async () => { if (await run(() => appApi(`/api/app/accounts/${account}/investor`, "PUT", { password: null }), "Mot de passe supprimé")) reloadAccounts(); }}>Supprimer</button>
              </div>
            ) : (
              <div className="mt-3 flex gap-2">
                <input className="input" type="password" autoComplete="off" value={pwd} onChange={(e) => setPwd(e.target.value)} placeholder="Mot de passe investisseur" aria-label="Mot de passe investisseur" />
                <button className="btn btn-ghost btn-sm shrink-0" disabled={busy || pwd.length < 4} onClick={async () => { if (await run(() => appApi(`/api/app/accounts/${account}/investor`, "PUT", { password: pwd }), "Mot de passe enregistré")) { setPwd(""); reloadAccounts(); } }}>Enregistrer</button>
              </div>
            )}
          </div>
          {sync.length > 0 && (
            <div>
              <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Jetons actifs</h3>
              <ul className="grid gap-1.5 text-sm">
                {sync.map((t) => (
                  <li key={t.id} className="flex flex-wrap items-center gap-2">
                    <span>{accounts.find((a) => a.id === t.account_id)?.label ?? t.label}</span>
                    <span className="text-xs text-faint">créé {when(t.created_at)} · {t.last_used_at ? `utilisé ${when(t.last_used_at)}` : "jamais utilisé"}</span>
                    <button className="ml-auto text-xs text-down-400 hover:underline" disabled={busy} onClick={async () => { if (await run(() => appApi(`/api/app/tokens/${t.id}`, "DELETE"))) reload(); }}>Révoquer</button>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {note}
        </div>
      )}
    </Section>
  );
}

// ---------------- public API ----------------
function ApiTokens() {
  const { data, reload } = useLoad<Token[]>("/api/app/tokens");
  const [label, setLabel] = useState("");
  const [shown, setShown] = useState<string | null>(null);
  const { busy, run, note } = useAction();
  const api = (data ?? []).filter((t) => t.kind === "public_api");
  return (
    <Section title="API (lecture seule)" icon={<KeyRound className="size-4" />}>
      <p className="mb-3 text-sm text-muted">Lisez vos trades, statistiques et leçons depuis vos outils : <span className="num">GET /api/v1/trades</span>, <span className="num">/api/v1/stats</span>, <span className="num">/api/v1/lessons</span>, avec l&apos;en-tête <span className="num">Authorization: Bearer</span>. 60 requêtes par minute.</p>
      {shown && <div className="mb-3 grid gap-2"><Notice kind="warn">Copiez le jeton maintenant : il n&apos;est affiché qu&apos;une fois.</Notice><CopyField label="Jeton d'API" value={shown} secret /></div>}
      <div className="flex gap-2">
        <input className="input" maxLength={80} value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Nom du jeton (ex. : tableur)" aria-label="Nom du jeton" />
        <button className="btn btn-ghost btn-sm shrink-0" disabled={busy || label.trim().length < 2} onClick={async () => { const out = await run(() => appApi<{ token: string }>("/api/app/tokens/api", "POST", { label })); if (out) { setShown(out.token); setLabel(""); reload(); } }}>Créer</button>
      </div>
      {api.length > 0 && (
        <ul className="mt-3 grid gap-1.5 text-sm">
          {api.map((t) => (
            <li key={t.id} className="flex flex-wrap items-center gap-2">
              <span>{t.label}</span>
              <span className="text-xs text-faint">{t.last_used_at ? `utilisé ${when(t.last_used_at)}` : "jamais utilisé"}</span>
              <button className="ml-auto text-xs text-down-400 hover:underline" disabled={busy} onClick={async () => { if (await run(() => appApi(`/api/app/tokens/${t.id}`, "DELETE"))) reload(); }}>Révoquer</button>
            </li>
          ))}
        </ul>
      )}
      {note}
    </Section>
  );
}

// ---------------- data rights ----------------
function DataRights() {
  const [confirmText, setConfirmText] = useState("");
  const [deleted, setDeleted] = useState<Record<string, number> | null>(null);
  const { busy, run, note } = useAction();
  const exportData = async () => {
    const out = await run(() => appApi<unknown>("/api/app/export"));
    if (!out) return;
    const url = URL.createObjectURL(new Blob([JSON.stringify(out, null, 2)], { type: "application/json" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `alpha-edge-export-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };
  const erase = async () => {
    const out = await run(() => appApi<{ deleted: Record<string, number> }>("/api/app/erase", "POST", { confirmation: confirmText }));
    if (out) { setDeleted(out.deleted); setConfirmText(""); }
  };
  return (
    <Section title="Vos données" icon={<Database className="size-4" />}>
      <p className="text-sm text-muted">Vos trades, notes, leçons et résumés vous appartiennent. Exportez-les à tout moment, ou effacez-les définitivement.</p>
      <button className="btn btn-ghost btn-sm mt-3" disabled={busy} onClick={exportData}>Exporter (JSON)</button>
      <div className="mt-5 rounded-xl border border-down-500/30 p-4">
        <h3 className="text-sm font-semibold text-down-400">Effacer toutes mes données de trading</h3>
        <p className="mt-1 text-xs text-muted">Supprime comptes, trades, journal, leçons, mémoire, analyses et jetons. Irréversible. Votre compte membre et vos accès restent actifs. Tapez <span className="num">EFFACER MES DONNEES</span> pour confirmer.</p>
        <div className="mt-3 flex gap-2">
          <input className="input" value={confirmText} onChange={(e) => setConfirmText(e.target.value)} aria-label="Confirmation d'effacement" />
          <button className="btn btn-danger btn-sm shrink-0" disabled={busy || confirmText.trim().toUpperCase() !== "EFFACER MES DONNEES"} onClick={erase}>Effacer</button>
        </div>
        {deleted && <Notice kind="ok" className="mt-3">Effacé : {Object.entries(deleted).map(([k, v]) => `${k} (${n2(v, 0)})`).join(", ") || "rien à effacer"}.</Notice>}
      </div>
      {note}
    </Section>
  );
}
