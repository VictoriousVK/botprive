"use client";

import { BarChart3, FileUp, ListChecks, Plus, Star, Trash2, Wallet, X } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { AppShell, useApp } from "@/components/app-shell";
import { FileDrop, GroupTable, Kv, Section, Seg, useAction, useLoad } from "@/components/app-ui";
import { AreaChart, Empty, Notice, Spinner, Stat } from "@/components/ui";
import {
  BEHAVIOR_LABEL, EMOTIONS, KZ_LABEL, MISTAKES, MODEL_LABEL, appApi, fileToBase64, money, n2, pc, rr, tone, when,
  type Account, type JournalEntry, type Stats, type Trade,
} from "@/lib/app";

type Vue = "trades" | "stats" | "comptes";
const KZ_OR_NONE: Record<string, string> = { ...KZ_LABEL, "—": "Hors killzone" };
const WEEKDAY: Record<string, string> = { lundi: "Lundi", mardi: "Mardi", mercredi: "Mercredi", jeudi: "Jeudi", vendredi: "Vendredi", samedi: "Samedi", dimanche: "Dimanche", "—": "Inconnu" };
const SESSION: Record<string, string> = { asia: "Asie", london: "Londres", new_york: "New York", off: "Hors session", "—": "Inconnue" };

export function JournalView() {
  const params = useSearchParams();
  const router = useRouter();
  const vue = (params.get("vue") as Vue) || "trades";
  const setVue = (v: Vue) => router.replace(`/app/journal/?vue=${v}`, { scroll: false });
  return (
    <AppShell title="Journal de trading" subtitle="Import MT5, notes par trade, statistiques calculées sur vos données" feature="journal">
      <div className="mb-5 flex flex-wrap items-center gap-3">
        <Seg<Vue> label="Vue du journal" value={vue} onChange={setVue} options={[["trades", "Trades"], ["stats", "Statistiques"], ["comptes", "Comptes et import"]]} />
        <TradeCap />
      </div>
      {vue === "trades" && <Trades />}
      {vue === "stats" && <StatsPanel />}
      {vue === "comptes" && <Accounts />}
    </AppShell>
  );
}

/** The free plan caps imported trades per calendar month (counted on the trades themselves). */
function TradeCap() {
  const { app } = useApp();
  const cap = app?.limits.trades_per_month;
  if (!cap) return null;
  return <span className="chip" title="Au-delà, les trades du mois ne sont pas importés">Offre gratuite : {cap} trades importés par mois</span>;
}

// ================================================================ trades
function Trades() {
  const [days, setDays] = useState("90");
  const [account, setAccount] = useState("");
  const [open, setOpen] = useState<string | null>(null);
  const { data: accounts } = useLoad<Account[]>("/api/app/accounts");
  const { data, error, reload } = useLoad<Trade[]>(`/api/app/trades?days=${days}&account=${account}&limit=300`);
  const [adding, setAdding] = useState(false);
  if (error) return <Notice kind="error">{error}</Notice>;
  if (!data || !accounts) return <Spinner />;
  if (!accounts.length) {
    return <Empty icon={<Wallet className="size-7" />} title="Aucun compte de trading">Ajoutez votre compte dans « Comptes et import », puis importez votre historique MT5.</Empty>;
  }
  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <Seg label="Période" value={days} onChange={setDays} options={[["7", "7 j"], ["30", "30 j"], ["90", "90 j"], ["365", "1 an"]]} />
        <select className="input w-auto py-1.5 text-sm" value={account} onChange={(e) => setAccount(e.target.value)} aria-label="Compte">
          <option value="">Tous les comptes</option>
          {accounts.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}
        </select>
        <button className="btn btn-ghost btn-sm ml-auto" onClick={() => setAdding((x) => !x)}><Plus className="size-4" aria-hidden /> Saisir un trade</button>
      </div>
      {adding && <ManualTrade accounts={accounts} onDone={() => { setAdding(false); reload(); }} />}
      {data.length === 0 ? (
        <Empty icon={<ListChecks className="size-7" />} title="Aucun trade sur la période">Importez votre historique ou élargissez la période.</Empty>
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="table min-w-[760px]">
            <thead>
              <tr><th>Ouverture</th><th>Symbole</th><th>Sens</th><th className="text-right">Lots</th><th className="text-right">Net</th><th className="text-right">R</th><th>Killzone</th><th>Setup</th><th>Plan</th><th>Journal</th></tr>
            </thead>
            <tbody>
              {data.map((t) => (
                <tr key={t.id} className="cursor-pointer hover:bg-white/[0.03]" onClick={() => setOpen(t.id)}>
                  <td className="whitespace-nowrap">{when(t.open_utc)}</td>
                  <td className="font-medium">{t.symbol}</td>
                  <td>{t.side === "long" ? "Achat" : "Vente"}</td>
                  <td className="num text-right">{n2(t.volume)}</td>
                  <td className={`num text-right ${tone(t.net)}`}>{t.close_utc ? n2(t.net) : <span className="chip">ouvert</span>}</td>
                  <td className={`num text-right ${tone(t.r_multiple)}`} title={t.r_source === "plan" ? "R estimé depuis le risque du plan (stop initial inconnu)" : undefined}>
                    {t.r_multiple == null ? "—" : `${rr(t.r_multiple)}${t.r_source === "plan" ? "*" : ""}`}
                  </td>
                  <td>{t.killzone ? KZ_LABEL[t.killzone] ?? t.killzone : <span className="text-faint">hors</span>}</td>
                  <td>{t.setup_model ? MODEL_LABEL[t.setup_model] ?? t.setup_model : "—"}</td>
                  <td>{t.plan_respected == null ? "—" : t.plan_respected ? <span className="chip chip-green">oui</span> : <span className="chip chip-red">non</span>}</td>
                  <td>{t.journal ? <span className="chip chip-blue">noté</span> : <span className="text-xs text-faint">à noter</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="px-4 py-3 text-xs text-faint">* R estimé depuis le risque prévu par votre plan, faute de stop initial connu.</p>
        </div>
      )}
      {open && <TradeDrawer id={open} onClose={() => setOpen(null)} onSaved={reload} />}
    </div>
  );
}

function TradeDrawer({ id, onClose, onSaved }: { id: string; onClose: () => void; onSaved: () => void }) {
  const { data: t, error } = useLoad<Trade>(`/api/app/trades/${id}`);
  const { data: plan } = useLoad<{ setups: string[] }>("/api/app/plan");
  const [e, setE] = useState<JournalEntry | null>(null);
  const { busy, run, note } = useAction();
  useEffect(() => {
    if (t) setE({ setup_model: null, emotion_before: null, emotion_after: null, followed_plan: null, mistakes: [], notes: "", rating: null, ...(t.journal ?? {}) });
  }, [t]);
  useEffect(() => {
    const onKey = (ev: KeyboardEvent) => ev.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  const save = async () => {
    if (!e) return;
    const body = { ...e, notes: e.notes ?? "" };
    const out = await run(() => appApi(`/api/app/trades/${id}/journal`, "PUT", body), "Journal enregistré");
    if (out) onSaved();
  };
  const del = async () => {
    if (!confirm("Supprimer ce trade saisi à la main ?")) return;
    if (await run(() => appApi(`/api/app/trades/${id}`, "DELETE"))) { onSaved(); onClose(); }
  };
  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/60" role="dialog" aria-modal="true" aria-label="Détail du trade" onClick={onClose}>
      <div className="h-full w-full max-w-lg overflow-y-auto border-l border-white/10 bg-ink-900 p-5 sm:p-6" onClick={(ev) => ev.stopPropagation()}>
        <div className="mb-4 flex items-center gap-3">
          <h2 className="flex-1 text-lg font-semibold">{t ? `${t.symbol} · ${t.side === "long" ? "Achat" : "Vente"}` : "Trade"}</h2>
          <button className="rounded-lg p-2 text-muted hover:text-white" onClick={onClose} aria-label="Fermer"><X className="size-5" aria-hidden /></button>
        </div>
        {error && <Notice kind="error">{error}</Notice>}
        {!t || !e ? <Spinner /> : (
          <div className="grid gap-5">
            <div className="rounded-xl border border-white/5 bg-white/[0.02] p-4">
              <Kv k="Ouverture" v={`${when(t.open_utc)} à ${n2(t.open_price, 5)}`} />
              <Kv k="Clôture" v={t.close_utc ? `${when(t.close_utc)} à ${n2(t.close_price, 5)}` : "position ouverte"} />
              <Kv k="Volume" v={`${n2(t.volume)} lot(s)`} />
              <Kv k="Stop initial / objectif" v={`${t.sl ? n2(t.sl, 5) : "—"} / ${t.tp ? n2(t.tp, 5) : "—"}`} />
              <Kv k="Net (commission et swap inclus)" v={<span className={tone(t.net)}>{n2(t.net)}</span>} />
              <Kv k="R" v={<span className={tone(t.r_multiple)}>{rr(t.r_multiple)}</span>} />
              <Kv k="Session / killzone" v={`${t.session ? SESSION[t.session] ?? t.session : "—"} / ${t.killzone ? KZ_LABEL[t.killzone] ?? t.killzone : "hors killzone"}`} />
              {t.macro && <Kv k="Macro" v={t.macro} />}
              <Kv k="Source" v={({ mt5_report: "Rapport MT5", csv: "Fichier CSV", sync_ea: "EA Journal Sync", manual: "Saisie manuelle", bridge: "Pont MT5" } as Record<string, string>)[t.source] ?? t.source} />
            </div>
            {t.executions && t.executions.length > 1 && (
              <div>
                <div className="mb-1 text-xs font-semibold uppercase tracking-wider text-faint">Exécutions</div>
                {t.executions.map((x) => <Kv key={x.deal_id} k={`${when(x.time_utc)} · ${x.entry === "in" ? "entrée" : "sortie"}`} v={`${n2(x.volume)} @ ${n2(x.price, 5)}`} />)}
              </div>
            )}
            <div className="grid gap-4">
              <label className="field">
                <span>Setup</span>
                <select className="input" value={e.setup_model ?? ""} onChange={(ev) => setE({ ...e, setup_model: ev.target.value || null })}>
                  <option value="">Non précisé</option>
                  {(plan?.setups ?? Object.keys(MODEL_LABEL)).map((s) => <option key={s} value={s}>{MODEL_LABEL[s] ?? s}</option>)}
                </select>
              </label>
              <div className="grid grid-cols-2 gap-3">
                {(["emotion_before", "emotion_after"] as const).map((key) => (
                  <label key={key} className="field">
                    <span>{key === "emotion_before" ? "Émotion avant" : "Émotion après"}</span>
                    <select className="input" value={e[key] ?? ""} onChange={(ev) => setE({ ...e, [key]: ev.target.value || null })}>
                      <option value="">—</option>
                      {EMOTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                    </select>
                  </label>
                ))}
              </div>
              <fieldset className="field">
                <span>Plan respecté ?</span>
                <Seg label="Plan respecté" value={e.followed_plan == null ? "?" : e.followed_plan ? "oui" : "non"} onChange={(v) => setE({ ...e, followed_plan: v === "?" ? null : v === "oui" })}
                  options={[["oui", "Oui"], ["non", "Non"], ["?", "Non précisé"]]} />
              </fieldset>
              <fieldset className="field">
                <span>Erreurs</span>
                <div className="flex flex-wrap gap-1.5">
                  {MISTAKES.map(([v, l]) => {
                    const on = e.mistakes.includes(v);
                    return (
                      <button key={v} type="button" aria-pressed={on} className={`chip ${on ? "chip-red" : ""}`}
                        onClick={() => setE({ ...e, mistakes: on ? e.mistakes.filter((x) => x !== v) : [...e.mistakes, v].slice(0, 6) })}>{l}</button>
                    );
                  })}
                </div>
              </fieldset>
              <label className="field">
                <span>Notes</span>
                <textarea className="input min-h-28" maxLength={4000} value={e.notes ?? ""} onChange={(ev) => setE({ ...e, notes: ev.target.value })} placeholder="Contexte, raison de l'entrée, gestion, ce que vous referiez autrement" />
              </label>
              <fieldset className="field">
                <span>Note d&apos;exécution</span>
                <div className="flex gap-1">
                  {[1, 2, 3, 4, 5].map((n) => (
                    <button key={n} type="button" aria-label={`${n} sur 5`} aria-pressed={e.rating === n} onClick={() => setE({ ...e, rating: e.rating === n ? null : n })}
                      className={e.rating != null && n <= e.rating ? "text-gold-400" : "text-faint hover:text-gold-300"}>
                      <Star className="size-5" fill={e.rating != null && n <= e.rating ? "currentColor" : "none"} aria-hidden />
                    </button>
                  ))}
                </div>
              </fieldset>
              <div className="flex flex-wrap gap-2">
                <button className="btn btn-primary btn-sm" disabled={busy} onClick={save}>Enregistrer</button>
                {t.source === "manual" && <button className="btn btn-danger btn-sm" disabled={busy} onClick={del}><Trash2 className="size-4" aria-hidden /> Supprimer</button>}
              </div>
              {note}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function ManualTrade({ accounts, onDone }: { accounts: Account[]; onDone: () => void }) {
  const [f, setF] = useState({ account_id: accounts[0]?.id ?? "", symbol: "XAUUSD", side: "long", volume: "0.10", open: "", open_price: "", close: "", close_price: "", sl: "", tp: "", profit: "", commission: "0", swap: "0" });
  const { busy, run, note } = useAction();
  const num = (s: string) => (s.trim() === "" ? null : Number(s.replace(",", ".")));
  const submit = async () => {
    const body = {
      account_id: f.account_id, symbol: f.symbol, side: f.side, volume: num(f.volume), open_time_utc: f.open ? new Date(f.open).getTime() : 0, open_price: num(f.open_price),
      close_time_utc: f.close ? new Date(f.close).getTime() : null, close_price: num(f.close_price), sl: num(f.sl), tp: num(f.tp), profit: num(f.profit) ?? 0, commission: num(f.commission) ?? 0, swap: num(f.swap) ?? 0,
    };
    if (await run(() => appApi("/api/app/trades", "POST", body))) onDone();
  };
  const inp = (k: keyof typeof f, label: string, type = "text") => (
    <label className="field"><span>{label}</span><input className="input" type={type} inputMode={type === "text" && k !== "symbol" ? "decimal" : undefined} value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} /></label>
  );
  return (
    <div className="card p-5">
      <h3 className="mb-3 font-semibold">Saisie manuelle</h3>
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="field"><span>Compte</span><select className="input" value={f.account_id} onChange={(e) => setF({ ...f, account_id: e.target.value })}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}</select></label>
        {inp("symbol", "Symbole")}
        <label className="field"><span>Sens</span><select className="input" value={f.side} onChange={(e) => setF({ ...f, side: e.target.value })}><option value="long">Achat</option><option value="short">Vente</option></select></label>
        {inp("volume", "Lots")}
        {inp("open", "Ouverture (heure locale)", "datetime-local")}
        {inp("open_price", "Prix d'entrée")}
        {inp("close", "Clôture (heure locale)", "datetime-local")}
        {inp("close_price", "Prix de sortie")}
        {inp("sl", "Stop initial")}
        {inp("tp", "Objectif")}
        {inp("profit", "Profit brut (devise du compte)")}
        {inp("commission", "Commission")}
      </div>
      <button className="btn btn-primary btn-sm mt-4" disabled={busy || !f.open || !f.open_price} onClick={submit}>Ajouter</button>
      {note}
    </div>
  );
}

// ================================================================ statistics
function StatsPanel() {
  const [days, setDays] = useState("90");
  const [account, setAccount] = useState("");
  const { data: accounts } = useLoad<Account[]>("/api/app/accounts");
  const { data: st, error } = useLoad<Stats>(`/api/app/stats?days=${days}&account=${account}`);
  if (error) return <Notice kind="error">{error}</Notice>;
  if (!st) return <Spinner />;
  const k = st.kpis;
  return (
    <div className="grid gap-5">
      <div className="flex flex-wrap items-center gap-2">
        <Seg label="Période" value={days} onChange={setDays} options={[["30", "30 j"], ["90", "90 j"], ["365", "1 an"], ["3650", "Tout"]]} />
        <select className="input w-auto py-1.5 text-sm" value={account} onChange={(e) => setAccount(e.target.value)} aria-label="Compte">
          <option value="">Tous les comptes</option>
          {(accounts ?? []).map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}
        </select>
      </div>
      {k.insufficient ? (
        <Notice kind="warn">{k.n} trade(s) clôturé(s) : il en faut au moins {k.min_trades} pour des statistiques interprétables. Les chiffres ci-dessous sont indicatifs.</Notice>
      ) : k.sample_warning ? (
        <Notice kind="warn">Échantillon faible ({k.n} trades) : les intervalles de confiance sont larges.</Notice>
      ) : null}
      <Section title="Indicateurs" icon={<BarChart3 className="size-4" />}>
        <div className="grid grid-cols-2 gap-5 sm:grid-cols-4">
          <Stat label="Trades" value={`${k.n} (${k.wins} G / ${k.losses} P)`} />
          <Stat label="Taux de réussite" value={pc(k.win_rate)} hint={k.win_rate_ci95 ? `IC 95 % : ${pc(k.win_rate_ci95[0])} à ${pc(k.win_rate_ci95[1])}` : undefined} />
          <Stat label="Espérance" value={rr(k.expectancy_r)} tone={tone(k.expectancy_r)} hint={k.expectancy_r_ci95 ? `IC 95 % : ${rr(k.expectancy_r_ci95[0])} à ${rr(k.expectancy_r_ci95[1])}` : undefined} />
          <Stat label="Profit factor" value={n2(k.profit_factor)} />
          <Stat label="Gain moyen" value={rr(k.avg_win_r)} tone="text-up-400" />
          <Stat label="Perte moyenne" value={rr(k.avg_loss_r)} tone="text-down-400" />
          <Stat label="Résultat net" value={money(k.net_total)} tone={tone(k.net_total)} />
          <Stat label="Drawdown max" value={`${n2(k.max_drawdown)}${k.max_drawdown_r != null ? ` (${n2(k.max_drawdown_r)} R)` : ""}`} />
          <Stat label="Pertes consécutives max" value={k.max_consecutive_losses} />
          <Stat label="Trades avec R connu" value={pc(k.r_coverage, 0)} />
        </div>
        <div className="mt-5"><AreaChart points={st.equity.map((p) => ({ t: p.t, v: p.net }))} label="Courbe du résultat cumulé" height={170} /></div>
        {k.win_rate_ci95 && <p className="mt-3 text-xs text-faint">Les intervalles de confiance à 95 % (Wilson pour le taux de réussite, bootstrap pour l&apos;espérance) indiquent la marge d&apos;incertitude due à la taille de l&apos;échantillon.</p>}
      </Section>
      <Section title="Écarts au plan repérés">
        {st.flags.length ? (
          <ul className="grid gap-2">
            {st.flags.map((f) => (
              <li key={f.kind} className="flex flex-wrap gap-3 rounded-lg border border-white/5 bg-white/[0.02] p-3 text-sm">
                <span className="chip chip-gold">{BEHAVIOR_LABEL[f.kind] ?? f.kind}</span>
                <span className="flex-1 text-fg/85">{f.detail}</span>
                <span className="text-xs text-faint">{f.trade_ids.length} trade(s)</span>
              </li>
            ))}
          </ul>
        ) : <p className="text-sm text-muted">Aucun écart repéré sur la période.</p>}
      </Section>
      <div className="grid gap-5 lg:grid-cols-2">
        <Section title="Par killzone"><GroupTable rows={k.by_killzone} keyLabel="Killzone" label={KZ_OR_NONE} /></Section>
        <Section title="Par setup"><GroupTable rows={k.by_setup} keyLabel="Setup" label={{ ...MODEL_LABEL, "—": "Non précisé" }} /></Section>
        <Section title="Par jour"><GroupTable rows={k.by_weekday} keyLabel="Jour" label={WEEKDAY} /></Section>
        <Section title="Par symbole"><GroupTable rows={k.by_symbol} keyLabel="Symbole" label={{}} /></Section>
        <Section title="Par session"><GroupTable rows={k.by_session} keyLabel="Session" label={SESSION} /></Section>
        <Section title="Par sens"><GroupTable rows={k.by_direction} keyLabel="Sens" label={{ long: "Achat", short: "Vente" }} /></Section>
      </div>
    </div>
  );
}

// ================================================================ accounts and import
type Profile = { key: string; label: string; verified_at: string | null };
const EMPTY_ACCOUNT = { label: "", broker: "", server: "", login: "", kind: "demo", server_winter_offset_h: 2, server_dst_rule: "us", currency: "USD", starting_balance: "", prop_profile: "" };
type AccountForm = typeof EMPTY_ACCOUNT;

export function accountBody(f: AccountForm) {
  return { ...f, starting_balance: f.starting_balance === "" ? null : Number(String(f.starting_balance).replace(",", ".")), prop_profile: f.prop_profile || null, server_winter_offset_h: Number(f.server_winter_offset_h) };
}

function Accounts() {
  const { app } = useApp();
  const { data: accounts, reload } = useLoad<Account[]>("/api/app/accounts");
  const { data: profiles } = useLoad<{ profiles: Profile[]; prop_guard: boolean }>("/api/app/risk/profiles");
  const { data: imports, reload: reloadImports } = useLoad<{ id: string; source: string; status: string; stats: Record<string, number>; error?: string | null; created_at: number; account_id: string }[]>("/api/app/imports");
  const [edit, setEdit] = useState<string | null>(null);
  if (!accounts) return <Spinner />;
  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <div className="grid content-start gap-5">
        <Section title="Comptes de trading" icon={<Wallet className="size-4" />} actions={<button className="btn btn-ghost btn-sm" onClick={() => setEdit("new")}><Plus className="size-4" aria-hidden /> Ajouter</button>}>
          {accounts.length === 0 && edit !== "new" && <p className="text-sm text-muted">Déclarez le compte dont vous importez l&apos;historique (démo, réel ou prop firm).</p>}
          <ul className="grid gap-2">
            {accounts.map((a) => (
              <li key={a.id} className="rounded-lg border border-white/5 bg-white/[0.02] p-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold">{a.label}</span>
                  <span className={`chip ${a.kind === "real" ? "chip-gold" : a.kind === "prop" ? "chip-blue" : ""}`}>{a.kind === "real" ? "Réel" : a.kind === "prop" ? "Prop firm" : "Démo"}</span>
                  <span className="chip">{a.access_mode === "sync_ea" ? "EA Journal Sync" : a.access_mode === "investor" ? "Mot de passe investisseur" : "Import de fichier"}</span>
                  <button className="ml-auto text-xs text-brand-300 hover:underline" onClick={() => setEdit(edit === a.id ? null : a.id)}>{edit === a.id ? "Fermer" : "Modifier"}</button>
                </div>
                <p className="mt-1 text-xs text-muted">{[a.broker, a.server, a.login && `n° ${a.login}`].filter(Boolean).join(" · ") || "Broker non renseigné"} · solde de départ {a.starting_balance != null ? money(a.starting_balance, a.currency) : "non renseigné"}{a.last_sync_at ? ` · synchronisé ${when(a.last_sync_at)}` : ""}</p>
                {edit === a.id && <AccountEditor account={a} profiles={profiles?.profiles ?? []} propGuard={!!profiles?.prop_guard} onDone={() => { setEdit(null); reload(); }} />}
              </li>
            ))}
          </ul>
          {edit === "new" && <AccountEditor profiles={profiles?.profiles ?? []} propGuard={!!profiles?.prop_guard} onDone={() => { setEdit(null); reload(); }} />}
        </Section>
        {app?.features.mt5_sync ? (
          <Notice kind="info">Pour une synchronisation automatique, installez l&apos;EA Journal Sync (lecture seule) depuis les Réglages : il envoie vos transactions sans jamais passer d&apos;ordre.</Notice>
        ) : (
          <Notice kind="info">La synchronisation automatique par EA est incluse à partir de l&apos;offre Pro Trader. L&apos;import de fichier reste disponible pour tous.</Notice>
        )}
      </div>
      <div className="grid content-start gap-5">
        <Import accounts={accounts} onDone={reloadImports} />
        <Section title="Historique des imports">
          {imports?.length ? (
            <ul className="grid gap-2 text-sm">
              {imports.map((i) => (
                <li key={i.id} className="flex flex-wrap items-center gap-2 border-b border-white/5 pb-2 last:border-0">
                  <span className={`chip ${i.status === "done" ? "chip-green" : "chip-red"}`}>{i.status === "done" ? "OK" : "Échec"}</span>
                  <span className="text-muted">{when(i.created_at)} · {i.source}</span>
                  <span className="ml-auto text-xs">{i.status === "done" ? `${i.stats.inserted ?? 0} ajoutés, ${i.stats.updated ?? 0} mis à jour${i.stats.skipped_cap ? `, ${i.stats.skipped_cap} au-delà du plafond` : ""}` : i.error}</span>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">Aucun import.</p>}
        </Section>
      </div>
    </div>
  );
}

function AccountEditor({ account, profiles, propGuard, onDone }: { account?: Account; profiles: Profile[]; propGuard: boolean; onDone: () => void }) {
  const [f, setF] = useState<AccountForm>(account ? {
    label: account.label, broker: account.broker, server: account.server, login: account.login, kind: account.kind, server_winter_offset_h: account.server_winter_offset_h,
    server_dst_rule: account.server_dst_rule, currency: account.currency, starting_balance: account.starting_balance == null ? "" : String(account.starting_balance), prop_profile: account.prop_profile ?? "",
  } : EMPTY_ACCOUNT);
  const { busy, run, note } = useAction();
  const save = async () => {
    const out = await run(() => appApi(account ? `/api/app/accounts/${account.id}` : "/api/app/accounts", account ? "PUT" : "POST", accountBody(f)));
    if (out) onDone();
  };
  const archive = async () => {
    if (!account || !confirm("Archiver ce compte ? Ses jetons de synchronisation sont révoqués ; ses trades restent dans vos statistiques.")) return;
    if (await run(() => appApi(`/api/app/accounts/${account.id}`, "DELETE"))) onDone();
  };
  const set = (k: keyof AccountForm) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  return (
    <div className="mt-3 grid gap-3 border-t border-white/5 pt-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="field"><span>Nom du compte</span><input className="input" value={f.label} onChange={set("label")} placeholder="Ex. : FTMO 100k" /></label>
        <label className="field"><span>Type</span><select className="input" value={f.kind} onChange={set("kind")}><option value="demo">Démo</option><option value="real">Réel</option><option value="prop">Prop firm</option></select></label>
        <label className="field"><span>Broker</span><input className="input" value={f.broker} onChange={set("broker")} /></label>
        <label className="field"><span>Serveur MT5</span><input className="input" value={f.server} onChange={set("server")} /></label>
        <label className="field"><span>Numéro de compte</span><input className="input" inputMode="numeric" value={f.login} onChange={(e) => setF({ ...f, login: e.target.value.replace(/\D/g, "") })} /></label>
        <label className="field"><span>Devise</span><input className="input" value={f.currency} maxLength={8} onChange={set("currency")} /></label>
        <label className="field"><span>Solde de départ</span><input className="input" inputMode="decimal" value={f.starting_balance} onChange={set("starting_balance")} /></label>
        <label className="field">
          <span>Profil de risque</span>
          <select className="input" value={f.prop_profile} onChange={set("prop_profile")}>
            <option value="">Mon plan de trading</option>
            {profiles.filter((p) => p.key !== "generic").map((p) => <option key={p.key} value={p.key} disabled={!propGuard}>{p.label}{p.verified_at ? "" : " (à vérifier)"}</option>)}
          </select>
        </label>
        <label className="field"><span>Décalage du serveur en hiver (h)</span><input className="input" type="number" min={-12} max={14} value={f.server_winter_offset_h} onChange={(e) => setF({ ...f, server_winter_offset_h: Number(e.target.value) })} /></label>
        <label className="field">
          <span>Heure d&apos;été du serveur</span>
          <select className="input" value={f.server_dst_rule} onChange={set("server_dst_rule")}><option value="us">Calendrier américain</option><option value="eu">Calendrier européen</option><option value="none">Aucune</option></select>
        </label>
      </div>
      <p className="text-xs text-faint">La plupart des brokers MT5 sont à UTC+2 en hiver et UTC+3 en été (calendrier américain). L&apos;EA Journal Sync mesure le décalage réel et le corrige automatiquement.</p>
      <div className="flex flex-wrap gap-2">
        <button className="btn btn-primary btn-sm" disabled={busy || f.label.trim().length < 2} onClick={save}>{account ? "Enregistrer" : "Créer le compte"}</button>
        {account && <button className="btn btn-danger btn-sm" disabled={busy} onClick={archive}>Archiver</button>}
      </div>
      {note}
    </div>
  );
}

function Import({ accounts, onDone }: { accounts: Account[]; onDone: () => void }) {
  const [account, setAccount] = useState(accounts[0]?.id ?? "");
  const [utc, setUtc] = useState(false);
  const [res, setRes] = useState<Record<string, number | string[]> | null>(null);
  const { busy, run, note } = useAction();
  useEffect(() => { if (!account && accounts[0]) setAccount(accounts[0].id); }, [accounts, account]);
  const send = async (file: File) => {
    if (file.size > 5 * 1024 * 1024) return run(async () => { throw new Error("Fichier trop volumineux (5 Mo maximum)."); });
    const out = await run(async () => appApi<Record<string, number | string[]>>("/api/app/import", "POST", { account_id: account, filename: file.name, content_base64: await fileToBase64(file), times_are_utc: utc }));
    if (out) { setRes(out); onDone(); }
  };
  return (
    <Section title="Importer un historique" icon={<FileUp className="size-4" />}>
      {!accounts.length ? <p className="text-sm text-muted">Créez d&apos;abord un compte.</p> : (
        <div className="grid gap-3">
          <label className="field"><span>Compte</span><select className="input" value={account} onChange={(e) => setAccount(e.target.value)}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}</select></label>
          <FileDrop accept=".htm,.html,.csv,.txt" busy={busy} onFile={send}
            hint="MT5 : onglet Historique → clic droit → Rapport → HTML. Ou un CSV (colonnes position, symbole, sens, volume, heures et prix d'ouverture et de clôture, profit). 5 Mo maximum." />
          <label className="flex items-center gap-2 text-sm text-muted"><input type="checkbox" checked={utc} onChange={(e) => setUtc(e.target.checked)} /> Les heures du CSV sont déjà en UTC</label>
          {note}
          {res && (
            <Notice kind="ok">
              {String(res.parsed)} position(s) lue(s) : {String(res.inserted)} ajoutée(s), {String(res.updated)} mise(s) à jour, {String(res.unchanged)} inchangée(s)
              {Number(res.skipped_cap) > 0 && <>, {String(res.skipped_cap)} au-delà du plafond mensuel de l&apos;offre gratuite</>}.
              {Array.isArray(res.errors) && res.errors.length > 0 && <span className="mt-1 block text-xs text-gold-300">Lignes ignorées : {res.errors.slice(0, 3).join(" ; ")}</span>}
            </Notice>
          )}
          <p className="text-xs text-faint">Les heures du serveur MT5 sont converties en UTC puis en heure de New York pour situer chaque trade dans sa killzone.</p>
        </div>
      )}
    </Section>
  );
}
