"use client";

import { AnimatePresence, motion } from "framer-motion";
import { ArrowRight, CircleCheck, Copy, ExternalLink, GraduationCap, LogOut, RefreshCw, Smartphone, Wallet } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { Emblem } from "@/components/brand";
import { Notice, Spinner } from "@/components/ui";
import { api, dateFr, fcfa, type CheckoutResult, type Me, type Payment } from "@/lib/api";
import { useSession } from "@/lib/session";

export function AccountView() {
  const { me, ready } = useSession();
  const params = useSearchParams();
  if (!ready) return <div className="container-x py-14"><Spinner /></div>;
  return me ? <Dashboard me={me} params={params} /> : <AuthPanel initial={params.get("vue") === "inscription" || params.get("offre") ? "register" : "login"} />;
}

// ---------------- sign in / sign up ----------------
function AuthPanel({ initial }: { initial: "login" | "register" }) {
  const { setMe, site } = useSession();
  const [tab, setTab] = useState<"login" | "register">(initial);
  const [f, setF] = useState({ name: "", email: "", phone: "", password: "", totp: "", accept: false });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [needTotp, setNeedTotp] = useState(false);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.type === "checkbox" ? e.target.checked : e.target.value });

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const m =
        tab === "login"
          ? await api<Me>("/api/m/login", { method: "POST", body: { email: f.email, password: f.password, totp: f.totp || null } })
          : await api<Me>("/api/m/register", { method: "POST", body: { email: f.email, password: f.password, name: f.name, phone: f.phone, accept_terms: f.accept } });
      setMe(m);
    } catch (e2) {
      const msg = e2 instanceof Error ? e2.message : "Erreur";
      if (msg.includes("2FA")) setNeedTotp(true);
      setErr(msg);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="container-x grid min-h-[70vh] place-items-center py-14">
      <div className="card w-full max-w-md p-7 sm:p-9">
        <div className="flex items-center gap-3">
          <Emblem size={44} />
          <div>
            <div className="font-[family-name:var(--font-display)] text-lg font-bold">Espace membre</div>
            <div className="text-xs text-muted">Liberté Financière</div>
          </div>
        </div>
        <div className="mt-7 grid grid-cols-2 rounded-xl border border-white/10 bg-ink-950 p-1" role="tablist">
          {(["login", "register"] as const).map((t) => (
            <button key={t} role="tab" aria-selected={tab === t} onClick={() => { setTab(t); setErr(null); }} className={`relative rounded-lg py-2 text-sm font-semibold ${tab === t ? "text-white" : "text-muted"}`}>
              {tab === t && <motion.span layoutId="auth-tab" className="absolute inset-0 rounded-lg bg-white/[0.07]" />}
              <span className="relative">{t === "login" ? "Connexion" : "Inscription"}</span>
            </button>
          ))}
        </div>
        {tab === "register" && site && !site.registration_open ? (
          <Notice className="mt-6">Les inscriptions ouvrent bientôt.</Notice>
        ) : (
          <form onSubmit={submit} className="mt-6 grid gap-4">
            <AnimatePresence initial={false}>
              {tab === "register" && (
                <motion.div key="reg" initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="grid gap-4 overflow-hidden">
                  <label className="field"><span>Nom complet</span><input className="input" required minLength={2} maxLength={80} autoComplete="name" value={f.name} onChange={set("name")} /></label>
                  <label className="field"><span>Téléphone Wave (facultatif)</span><input className="input" type="tel" inputMode="tel" placeholder="+221 77 000 00 00" autoComplete="tel" value={f.phone} onChange={set("phone")} /></label>
                </motion.div>
              )}
            </AnimatePresence>
            <label className="field"><span>E-mail</span><input className="input" type="email" required autoComplete="email" value={f.email} onChange={set("email")} /></label>
            <label className="field">
              <span>Mot de passe {tab === "register" && "(12 caractères minimum)"}</span>
              <input className="input" type="password" required minLength={tab === "register" ? 12 : 1} autoComplete={tab === "register" ? "new-password" : "current-password"} value={f.password} onChange={set("password")} />
            </label>
            {tab === "login" && needTotp && (
              <label className="field"><span>Code 2FA</span><input className="input num" inputMode="numeric" maxLength={6} value={f.totp} onChange={set("totp")} /></label>
            )}
            {tab === "register" && (
              <label className="flex gap-3 text-sm leading-relaxed text-muted">
                <input type="checkbox" className="mt-1 size-4 accent-brand-500" checked={f.accept} onChange={set("accept")} required />
                <span>J&apos;accepte les <Link href="/risques/#conditions" className="text-brand-300 underline">conditions</Link> et j&apos;ai lu l&apos;<Link href="/risques/" className="text-brand-300 underline">avertissement sur les risques</Link>.</span>
              </label>
            )}
            {err && <Notice kind="error">{err}</Notice>}
            <button className="btn btn-primary mt-1" disabled={busy}>
              {busy ? <Spinner label="" /> : tab === "login" ? "Se connecter" : "Créer mon compte"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

// ---------------- member dashboard ----------------
function Dashboard({ me, params }: { me: Me; params: URLSearchParams }) {
  const { site, setMe, refreshMe } = useSession();
  const router = useRouter();
  const [payments, setPayments] = useState<Payment[] | null>(null);
  const offer = params.get("offre");
  const months = Number(params.get("mois") || 1);
  const returning = params.get("paiement");

  const loadPayments = useCallback(() => api<Payment[]>("/api/m/payments").then(setPayments).catch(() => setPayments([])), []);
  useEffect(() => {
    loadPayments();
  }, [loadPayments]);

  const logout = async () => {
    await api("/api/m/logout", { method: "POST" }).catch(() => {});
    setMe(null);
    router.push("/");
  };

  const expires = me.offer_expires_at;
  const daysLeft = expires ? Math.max(0, Math.ceil((expires * 1000 - Date.now()) / 86_400_000)) : null;

  return (
    <div className="container-x py-12">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Espace membre</p>
          <h1 className="h-section mt-2">Bonjour {me.name.split(" ")[0]}</h1>
        </div>
        <button className="btn btn-ghost btn-sm" onClick={logout}><LogOut className="size-4" /> Déconnexion</button>
      </div>

      {returning && <PaymentReturn id={returning} onDone={() => { refreshMe(); loadPayments(); router.replace("/compte/"); }} />}
      {offer && !returning && site?.offers.some((o) => o.key === offer && o.price_xof > 0) && (
        <Checkout offerKey={offer} months={months} onChange={() => { loadPayments(); }} />
      )}

      <div className="mt-8 grid gap-5 lg:grid-cols-3">
        <div className="card relative overflow-hidden p-6 lg:col-span-2">
          <div className="absolute -right-20 -top-20 size-56 rounded-full bg-brand-500/15 blur-3xl" aria-hidden />
          <div className="relative flex flex-wrap items-start justify-between gap-4">
            <div>
              <div className="text-xs font-semibold uppercase tracking-wider text-faint">Mon offre</div>
              <div className="mt-1 font-[family-name:var(--font-display)] text-3xl font-bold">{me.offer_label}</div>
              <div className="mt-1 text-sm text-muted">
                {expires ? <>Active jusqu&apos;au <span className="text-fg">{dateFr(expires)}</span> ({daysLeft} jour{daysLeft === 1 ? "" : "s"})</> : "Offre gratuite, sans limite de durée"}
              </div>
            </div>
            <Link href="/tarifs/" className="btn btn-primary btn-sm">{me.offer === "decouverte" ? "Passer à l'offre supérieure" : "Prolonger ou changer"} <ArrowRight className="size-4" /></Link>
          </div>
          <div className="relative mt-6 flex flex-wrap gap-2">
            {me.entitlements.map((e) => (
              <span key={e} className="chip chip-green"><CircleCheck className="size-3" /> {site?.entitlements[e] ?? e}</span>
            ))}
          </div>
        </div>
        <div className="grid gap-3">
          <QuickLink href="/academie/" icon={GraduationCap} title="Académie" text="Reprendre mes cours" />
          <QuickLink href="/copytrading/" icon={Copy} title="Copytrading" text="Mes copies démo" />
          <QuickLink href="/robots/" icon={Wallet} title="Robots" text="Catalogue et licences" />
        </div>
      </div>

      <section className="mt-10">
        <div className="flex items-center justify-between">
          <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">Mes paiements</h2>
          <button className="btn btn-ghost btn-sm" onClick={loadPayments}><RefreshCw className="size-4" /> Actualiser</button>
        </div>
        <div className="card mt-4 scroll-x">
          {payments === null ? (
            <div className="p-6"><Spinner /></div>
          ) : payments.length === 0 ? (
            <p className="p-6 text-sm text-muted">Aucun paiement pour le moment.</p>
          ) : (
            <table className="table min-w-[640px]">
              <thead><tr><th>Date</th><th>Offre</th><th>Montant</th><th>Moyen</th><th>Statut</th><th /></tr></thead>
              <tbody>
                {payments.map((p) => (
                  <tr key={p.id}>
                    <td className="num text-muted">{dateFr(p.created_at)}</td>
                    <td>{p.offer_label} · {p.months} mois</td>
                    <td className="num">{p.amount ? fcfa(p.amount) : "—"}</td>
                    <td>{p.method_label}</td>
                    <td><StatusChip p={p} /></td>
                    <td className="text-right">
                      {p.status === "pending" && p.method === "wave_manual" && <DeclareInline p={p} onDone={loadPayments} />}
                      {p.status === "pending" && p.launch_url && <a className="btn btn-wave btn-sm" href={p.launch_url}>Payer <ExternalLink className="size-3.5" /></a>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </section>
    </div>
  );
}

function QuickLink({ href, icon: Icon, title, text }: { href: string; icon: typeof Copy; title: string; text: string }) {
  return (
    <Link href={href} className="card card-hover flex items-center gap-4 p-4">
      <span className="grid size-10 place-items-center rounded-xl border border-brand-400/30 bg-brand-400/10 text-brand-300"><Icon className="size-5" /></span>
      <span><span className="block font-semibold">{title}</span><span className="text-sm text-muted">{text}</span></span>
      <ArrowRight className="ml-auto size-4 text-faint" />
    </Link>
  );
}

function StatusChip({ p }: { p: Payment }) {
  const cls = p.status === "succeeded" ? "chip-green" : p.status === "declared" || p.status === "pending" ? "chip-gold" : "chip-red";
  return <span className={`chip ${cls}`}>{p.status_label}</span>;
}

function DeclareInline({ p, onDone }: { p: Payment; onDone: () => void }) {
  const [ref, setRef] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const send = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api(`/api/m/payments/${p.id}/declare`, { method: "POST", body: { transaction_ref: ref } });
      onDone();
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Erreur");
    }
  };
  return (
    <form onSubmit={send} className="flex items-center justify-end gap-2">
      <input className="input !w-40 !py-1.5 text-xs" placeholder="ID transaction Wave" value={ref} onChange={(e) => setRef(e.target.value)} required minLength={6} maxLength={40} />
      <button className="btn btn-ghost btn-sm">Envoyer</button>
      {err && <span className="text-xs text-down-400">{err}</span>}
    </form>
  );
}

function Checkout({ offerKey, months, onChange }: { offerKey: string; months: number; onChange: () => void }) {
  const { site } = useSession();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [res, setRes] = useState<CheckoutResult | null>(null);
  const [txn, setTxn] = useState("");
  const [declared, setDeclared] = useState(false);
  const offer = site?.offers.find((o) => o.key === offerKey);
  const dur = site?.billing.durations.find((d) => d.months === months);
  if (!offer || !dur) return <Notice kind="error" className="mt-6">Offre ou durée inconnue.</Notice>;
  const amount = offer.price_xof * Math.max(1, months - dur.free_months);

  const pay = async () => {
    setBusy(true);
    setErr(null);
    try {
      const r = await api<CheckoutResult>("/api/m/checkout", { method: "POST", body: { offer: offerKey, months } });
      if (r.launch_url) {
        window.location.assign(r.launch_url);
        return;
      }
      setRes(r);
      onChange();
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };
  const declare = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!res) return;
    setErr(null);
    try {
      await api(`/api/m/payments/${res.payment.id}/declare`, { method: "POST", body: { transaction_ref: txn } });
      setDeclared(true);
      onChange();
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Erreur");
    }
  };

  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="card mt-8 overflow-hidden border-[#1dc8ff]/30">
      <div className="grid md:grid-cols-[1fr_1.2fr]">
        <div className="bg-gradient-to-br from-[#1dc8ff]/12 to-transparent p-6">
          <p className="eyebrow !text-[#7fe0ff]">Paiement Wave</p>
          <div className="mt-2 font-[family-name:var(--font-display)] text-2xl font-bold">Offre {offer.label}</div>
          <div className="text-sm text-muted">{months} mois{dur.free_months ? `, dont ${dur.free_months} offerts` : ""}</div>
          <div className="num mt-5 text-3xl font-semibold">{fcfa(amount)}</div>
        </div>
        <div className="p-6">
          {!res ? (
            <div className="grid gap-4">
              <p className="text-sm leading-relaxed text-muted">
                {site?.wave === "api" ? "Vous allez être redirigé vers Wave pour confirmer le paiement dans votre application. Votre accès s'active dès la confirmation." : "Vous allez recevoir le numéro Wave à payer et une référence. Après le paiement, saisissez l'ID de la transaction : l'équipe active votre accès après vérification."}
              </p>
              {err && <Notice kind="error">{err}</Notice>}
              <button className="btn btn-wave" onClick={pay} disabled={busy || site?.wave === "off"}>
                <Smartphone className="size-4" /> {site?.wave === "off" ? "Paiement bientôt disponible" : `Payer ${fcfa(amount)} avec Wave`}
              </button>
            </div>
          ) : res.manual && !declared ? (
            <div className="grid gap-4 text-sm">
              <ol className="grid gap-3">
                <li>
                  1. Envoyez <strong className="num">{fcfa(res.manual.amount)}</strong> avec Wave
                  {res.manual.number && <> au <strong className="num">{res.manual.number}</strong></>}
                  {res.manual.link && <> via <a href={res.manual.link} target="_blank" rel="noopener noreferrer" className="text-[#7fe0ff] underline">le lien de paiement</a></>}.
                </li>
                <li>2. Indiquez la référence <strong className="num">{res.manual.reference}</strong> en commentaire si possible.</li>
                <li>3. Copiez l&apos;ID de la transaction affiché dans Wave et collez-le ici :</li>
              </ol>
              <form onSubmit={declare} className="flex flex-col gap-2 sm:flex-row">
                <input className="input num" placeholder="ID de transaction Wave" value={txn} onChange={(e) => setTxn(e.target.value)} required minLength={6} maxLength={40} />
                <button className="btn btn-primary shrink-0">Valider</button>
              </form>
              {err && <Notice kind="error">{err}</Notice>}
            </div>
          ) : (
            <Notice kind="ok">Merci ! Votre paiement est en cours de vérification. Votre accès sera activé dès validation.</Notice>
          )}
        </div>
      </div>
    </motion.div>
  );
}

function PaymentReturn({ id, onDone }: { id: string; onDone: () => void }) {
  const [p, setP] = useState<Payment | null>(null);
  const [tries, setTries] = useState(0);
  useEffect(() => {
    let stop = false;
    const tick = async () => {
      try {
        const r = await api<{ payment: Payment }>(`/api/m/payments/${encodeURIComponent(id)}`);
        if (stop) return;
        setP(r.payment);
        if (r.payment.status === "pending" && tries < 40) setTimeout(() => setTries((t) => t + 1), 3000);
      } catch {
        /* keep the last state */
      }
    };
    tick();
    return () => {
      stop = true;
    };
  }, [id, tries]);
  if (!p) return <div className="mt-6"><Spinner label="Vérification du paiement auprès de Wave…" /></div>;
  if (p.status === "succeeded")
    return (
      <Notice kind="ok" className="mt-6">
        Paiement confirmé : offre <strong>{p.offer_label}</strong> activée. <button className="ml-2 underline" onClick={onDone}>Continuer</button>
      </Notice>
    );
  if (p.status === "pending") return <Notice className="mt-6">Paiement en attente de confirmation par Wave… Cette page se met à jour toute seule.</Notice>;
  return <Notice kind="error" className="mt-6">Le paiement n&apos;a pas abouti ({p.status_label.toLowerCase()}). Vous pouvez réessayer depuis la page des offres.</Notice>;
}
