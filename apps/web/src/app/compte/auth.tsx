"use client";

// Sign in and sign up. Left, a live scene (New York clock with the killzones, an illustrative
// candle tape, what the space does); right, the form: sign up in two steps with a password
// strength meter and live checks. With e-mail confirmation on (the default), sign-up ends on
// "check your inbox"; the link (/compte/verifier/) signs the member in and sends them to the
// guided set-up, or back to the offer they came to pay. Forgotten password and a resend of the
// confirmation link live here too.

import { AnimatePresence, motion, useAnimate } from "framer-motion";
import { ArrowLeft, ArrowRight, Check, Eye, EyeOff, KeyRound, Mail, MailCheck, Phone, ShieldCheck, User } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { Emblem } from "@/components/brand";
import { CandleTape, KillzoneDial, ValueLines } from "@/components/session-scene";
import { Turnstile } from "@/components/turnstile";
import { Notice, Spinner } from "@/components/ui";
import { api, type Me, type Pending } from "@/lib/api";
import { useSession } from "@/lib/session";

type Tab = "login" | "register";
type View = Tab | "forgot";
const EMAIL_RE = /^[^@\s<>"']{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$/;
const PHONE_RE = /^[+0-9 ]{6,24}$/;
const MIN_PW = 12;
const EASE = [0.22, 1, 0.36, 1] as const;

/** A safe local path to go to after signing in (?suite=/app/journal/), or null. */
function nextPath(p: URLSearchParams): string | null {
  const s = p.get("suite");
  return safePath(s);
}

function safePath(s: string | null): string | null {
  return s && s.startsWith("/") && !s.startsWith("//") && !s.includes("\\") ? s : null;
}

// Where to go once the e-mail link is clicked (same browser): the offer being paid, the page
// asked for, or the guided set-up. Kept in this browser only; never needed for security.
const AFTER_VERIFY = "lf-apres-confirmation";
function rememberAfterVerify(path: string) {
  try {
    window.localStorage.setItem(AFTER_VERIFY, path);
  } catch {
    /* private browsing: the member lands on the guided set-up */
  }
}
export function takeAfterVerify(): string {
  try {
    const p = safePath(window.localStorage.getItem(AFTER_VERIFY));
    window.localStorage.removeItem(AFTER_VERIFY);
    return p ?? "/app/bienvenue/";
  } catch {
    return "/app/bienvenue/";
  }
}

/** Password strength, computed here and nowhere else: length first, then variety. */
export function strength(pw: string, hints: string[] = []): { score: 0 | 1 | 2 | 3 | 4; label: string } {
  if (pw.length < MIN_PW) return { score: 0, label: pw ? `Encore ${MIN_PW - pw.length} caractère${MIN_PW - pw.length > 1 ? "s" : ""}` : `${MIN_PW} caractères minimum` };
  const classes = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^A-Za-z0-9]/].filter((r) => r.test(pw)).length;
  const low = pw.toLowerCase();
  const weak = /(.)\1{3,}/.test(pw) || /(0123|1234|2345|3456|4567|5678|6789|abcd|azerty|qwerty|password|motdepasse)/.test(low) || hints.some((h) => h.length >= 4 && low.includes(h.toLowerCase()));
  let score = 1 + (pw.length >= 16 ? 1 : 0) + (classes >= 3 ? 1 : 0) + (pw.length >= 20 || classes === 4 ? 1 : 0);
  if (weak) score = Math.min(score, 1);
  const s = Math.min(4, score) as 1 | 2 | 3 | 4;
  return { score: s, label: weak ? "Facile à deviner" : ["", "Acceptable", "Correct", "Solide", "Excellent"][s] };
}

export function AuthPanel({ initial }: { initial: Tab }) {
  const { site } = useSession();
  const [tab, setTab] = useState<View>(initial);
  return (
    <div className="relative isolate overflow-hidden">
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[linear-gradient(rgb(148_163_184/.05)_1px,transparent_1px),linear-gradient(90deg,rgb(148_163_184/.05)_1px,transparent_1px)] bg-[size:44px_44px] [mask-image:radial-gradient(ellipse_at_30%_40%,#000_20%,transparent_75%)]" aria-hidden />
      <div className="container-x grid gap-8 py-8 sm:py-12 lg:min-h-[calc(100vh-4rem)] lg:grid-cols-[1.05fr_1fr] lg:items-center lg:gap-14">
        <Scene />
        <div className="w-full max-w-md justify-self-center lg:justify-self-end">
          <div className="card relative overflow-clip p-6 sm:p-8">
            <div className="absolute -right-24 -top-24 size-56 rounded-full bg-brand-500/15 blur-3xl" aria-hidden />
            {tab !== "forgot" && <div className="relative grid grid-cols-2 rounded-xl border border-white/10 bg-ink-950 p-1" role="tablist" aria-label="Connexion ou inscription">
              {(["login", "register"] as const).map((t) => (
                <button key={t} type="button" role="tab" aria-selected={tab === t} onClick={() => setTab(t)} className={`relative rounded-lg py-2 text-sm font-semibold transition-colors ${tab === t ? "text-white" : "text-muted hover:text-fg"}`}>
                  {tab === t && <motion.span layoutId="auth-tab" className="absolute inset-0 rounded-lg bg-white/[0.08]" transition={{ type: "spring", stiffness: 420, damping: 34 }} />}
                  <span className="relative">{t === "login" ? "Connexion" : "Inscription"}</span>
                </button>
              ))}
            </div>}
            <div className={`relative ${tab === "forgot" ? "" : "mt-6"}`}>
              <AnimatePresence mode="wait" initial={false}>
                <motion.div key={tab} initial={{ opacity: 0, y: 10, filter: "blur(4px)" }} animate={{ opacity: 1, y: 0, filter: "blur(0px)" }} exit={{ opacity: 0, y: -8, filter: "blur(4px)" }} transition={{ duration: 0.28, ease: EASE }}>
                  {tab === "login" ? <Login onSwitch={() => setTab("register")} onForgot={() => setTab("forgot")} />
                    : tab === "forgot" ? <Forgot onBack={() => setTab("login")} />
                    : site && !site.registration_open ? <Notice>Les inscriptions ouvrent bientôt.</Notice>
                    : <Register onSwitch={() => setTab("login")} />}
                </motion.div>
              </AnimatePresence>
            </div>
          </div>
          <p className="mt-4 px-2 text-center text-xs leading-relaxed text-faint">
            Outils d&apos;analyse et de discipline, sans signaux ni promesse de gain. Le trading comporte un risque de perte en capital.{" "}
            <Link href="/risques/" className="underline underline-offset-2 hover:text-muted">Avertissement</Link>
          </p>
        </div>
      </div>
    </div>
  );
}

function Scene() {
  return (
    <div className="min-w-0">
      <motion.div className="flex items-center gap-3" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5, ease: EASE }}>
        <Emblem size={40} />
        <div>
          <div className="font-[family-name:var(--font-display)] font-bold leading-tight">Liberté Financière</div>
          <div className="text-xs text-muted">Espace membre et espace de trading</div>
        </div>
      </motion.div>
      <motion.h1 className="h-display mt-6 text-3xl sm:text-4xl lg:text-5xl" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6, delay: 0.08, ease: EASE }}>
        Chaque trade <span className="text-gradient">compte</span>.<br className="hidden sm:block" /> Chaque règle aussi.
      </motion.h1>
      <div className="mt-6 hidden sm:block"><KillzoneDial size={180} /></div>
      <div className="mt-5 sm:hidden"><KillzoneDial size={112} /></div>
      <div className="card mt-6 hidden overflow-hidden p-3 lg:block"><CandleTape height={130} /></div>
      <div className="mt-6 hidden lg:block"><ValueLines /></div>
    </div>
  );
}

// ---------------- sign in ----------------
function Login({ onSwitch, onForgot }: { onSwitch: () => void; onForgot: () => void }) {
  const { setMe } = useSession();
  const params = useSearchParams();
  const router = useRouter();
  const [f, setF] = useState({ email: "", password: "", totp: "" });
  const [needTotp, setNeedTotp] = useState(false);
  const [state, setState] = useState<"idle" | "busy" | "done">("idle");
  const [err, setErr] = useState<string | null>(null);
  const [unconfirmed, setUnconfirmed] = useState(false); // e-mail not confirmed yet: offer a new link
  const [scope, shake] = useAnimate();

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setState("busy");
    setErr(null);
    setUnconfirmed(false);
    try {
      const m = await api<Me>("/api/m/login", { method: "POST", body: { email: f.email.trim(), password: f.password, totp: f.totp || null } });
      setState("done");
      const stay = params.get("offre") || params.get("paiement");
      window.setTimeout(() => {
        setMe(m);
        if (!stay) router.push(nextPath(params) ?? "/app/");
      }, 450);
    } catch (e2) {
      // The server never says whether an account has 2FA: the member opens the code field.
      const msg = e2 instanceof Error ? e2.message : "Erreur";
      setUnconfirmed(/non confirmé/i.test(msg));
      setErr(msg);
      setState("idle");
      shake(scope.current, { x: [0, -9, 9, -6, 6, -2, 0] }, { duration: 0.42 });
    }
  };

  return (
    <form ref={scope} onSubmit={submit} className="grid gap-4" noValidate>
      <div>
        <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">Bon retour</h2>
        <p className="mt-1 text-sm text-muted">Reprenez votre journal là où vous l&apos;avez laissé.</p>
      </div>
      <Field icon={<Mail className="size-4" />} label="E-mail" ok={EMAIL_RE.test(f.email.trim())}>
        {(id) => <input id={id} className="input !pl-10" type="email" required autoComplete="email" inputMode="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} />}
      </Field>
      <PasswordField value={f.password} onChange={(v) => setF({ ...f, password: v })} autoComplete="current-password" />
      <div className="-mt-2 flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
        {!needTotp ? (
          <button type="button" className="text-xs text-muted hover:text-fg" onClick={() => setNeedTotp(true)}>
            J&apos;ai activé la double authentification
          </button>
        ) : <span />}
        <button type="button" className="text-xs font-medium text-brand-300 hover:underline" onClick={onForgot}>Mot de passe oublié ?</button>
      </div>
      <AnimatePresence initial={false}>
        {needTotp && (
          <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="overflow-hidden">
            <Field icon={<ShieldCheck className="size-4" />} label="Code de l'application d'authentification">
              {(id) => <input id={id} className="input num !pl-10 tracking-[0.4em]" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={f.totp} onChange={(e) => setF({ ...f, totp: e.target.value.replace(/\D/g, "") })} autoFocus />}
            </Field>
          </motion.div>
        )}
      </AnimatePresence>
      <ErrorLine err={err} />
      {unconfirmed && <ResendLink email={f.email.trim()} />}
      <MorphButton state={state} disabled={!f.email || !f.password}>Se connecter</MorphButton>
      <p className="text-center text-sm text-muted">
        Pas encore de compte ? <button type="button" className="font-semibold text-brand-300 hover:underline" onClick={onSwitch}>Créer un compte gratuit</button>
      </p>
    </form>
  );
}

// ---------------- sign up, in two steps ----------------
function Register({ onSwitch }: { onSwitch: () => void }) {
  const { setMe, site } = useSession();
  const params = useSearchParams();
  const router = useRouter();
  const [step, setStep] = useState<1 | 2>(1);
  // website: hidden trap field. People never see it; form robots fill it and get a fake success.
  const [f, setF] = useState({ name: "", email: "", phone: "", password: "", accept: false, website: "" });
  const [state, setState] = useState<"idle" | "busy" | "done">("idle");
  const [err, setErr] = useState<string | null>(null);
  const [pending, setPending] = useState<string | null>(null); // e-mail waiting for its confirmation
  const [captcha, setCaptcha] = useState<string | null>(null);
  const [captchaKey, setCaptchaKey] = useState(0); // a new check after a refused attempt
  const turnstile = site?.turnstile_site_key || "";
  const [scope, shake] = useAnimate();

  const nameOk = f.name.trim().length >= 2;
  const emailOk = EMAIL_RE.test(f.email.trim());
  const phoneOk = !f.phone.trim() || PHONE_RE.test(f.phone.trim());
  const pw = strength(f.password, [f.email.split("@")[0], ...f.name.split(/\s+/)]);
  const ready2 = f.password.length >= MIN_PW && phoneOk && f.accept && (!turnstile || !!captcha);

  const fail = (msg: string) => {
    setErr(msg);
    setState("idle");
    shake(scope.current, { x: [0, -9, 9, -6, 6, -2, 0] }, { duration: 0.42 });
  };
  const next = (e: React.FormEvent) => {
    e.preventDefault();
    if (!nameOk) return fail("Indiquez votre nom (2 caractères au moins).");
    if (!emailOk) return fail("Adresse e-mail invalide.");
    setErr(null);
    setStep(2);
  };
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (f.password.length < MIN_PW) return fail(`Mot de passe : ${MIN_PW} caractères minimum.`);
    if (!phoneOk) return fail("Numéro Wave : chiffres, espaces et + uniquement.");
    if (!f.accept) return fail("Acceptez les conditions pour créer votre compte.");
    setState("busy");
    setErr(null);
    try {
      const r = await api<Me | Pending>("/api/m/register", {
        method: "POST",
        body: { email: f.email.trim(), password: f.password, name: f.name.trim(), phone: f.phone.trim(), accept_terms: f.accept, website: f.website, captcha },
      });
      const offer = params.get("offre");
      if ("pending" in r) {
        rememberAfterVerify(offer ? `/compte/?offre=${encodeURIComponent(offer)}${params.get("mois") ? `&mois=${encodeURIComponent(params.get("mois") ?? "")}` : ""}` : nextPath(params) ?? "/app/bienvenue/");
        setPending(r.email);
        return;
      }
      setState("done");
      window.setTimeout(() => {
        setMe(r);
        if (!offer) router.push("/app/bienvenue/");
      }, 550);
    } catch (e2) {
      const msg = e2 instanceof Error ? e2.message : "Erreur";
      if (/e-mail|adresse|nom/i.test(msg) && !/mot de passe/i.test(msg)) setStep(1);
      if (turnstile) {
        setCaptcha(null);
        setCaptchaKey((k) => k + 1);
      }
      fail(msg);
    }
  };

  if (pending) return <CheckInbox email={pending} onBack={onSwitch} />;

  return (
    <div ref={scope}>
      <div className="flex items-baseline justify-between gap-3">
        <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">{step === 1 ? "Créer votre compte" : "Sécuriser votre compte"}</h2>
        <span className="num shrink-0 text-xs text-faint" aria-live="polite">Étape {step} sur 2</span>
      </div>
      <div className="mt-3 grid grid-cols-2 gap-1.5" aria-hidden>
        {[1, 2].map((i) => (
          <div key={i} className="h-1 overflow-hidden rounded-full bg-white/[0.07]">
            <motion.div className="h-full rounded-full bg-gradient-to-r from-brand-400 to-up-400" initial={false} animate={{ width: step >= i ? "100%" : "0%" }} transition={{ duration: 0.5, ease: EASE }} />
          </div>
        ))}
      </div>
      <AnimatePresence mode="wait" initial={false}>
        {step === 1 ? (
          <motion.form key="s1" onSubmit={next} noValidate className="mt-5 grid gap-4"
            initial={{ opacity: 0, x: -24, filter: "blur(4px)" }} animate={{ opacity: 1, x: 0, filter: "blur(0px)" }} exit={{ opacity: 0, x: -24, filter: "blur(4px)" }} transition={{ duration: 0.3, ease: EASE }}>
            <Field icon={<User className="size-4" />} label="Nom complet" ok={nameOk}>
              {(id) => <input id={id} className="input !pl-10" required minLength={2} maxLength={80} autoComplete="name" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} autoFocus />}
            </Field>
            <Field icon={<Mail className="size-4" />} label="E-mail" ok={emailOk} bad={f.email.includes("@") && f.email.includes(".") && !emailOk}>
              {(id) => <input id={id} className="input !pl-10" type="email" required autoComplete="email" inputMode="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} />}
            </Field>
            <ErrorLine err={err} />
            <MorphButton state="idle" disabled={!nameOk || !emailOk}>Continuer <ArrowRight className="size-4" aria-hidden /></MorphButton>
            <p className="text-center text-sm text-muted">
              Déjà membre ? <button type="button" className="font-semibold text-brand-300 hover:underline" onClick={onSwitch}>Se connecter</button>
            </p>
          </motion.form>
        ) : (
          <motion.form key="s2" onSubmit={submit} noValidate className="mt-5 grid gap-4"
            initial={{ opacity: 0, x: 24, filter: "blur(4px)" }} animate={{ opacity: 1, x: 0, filter: "blur(0px)" }} exit={{ opacity: 0, x: 24, filter: "blur(4px)" }} transition={{ duration: 0.3, ease: EASE }}>
            <button type="button" onClick={() => { setStep(1); setErr(null); }} className="flex min-w-0 items-center gap-2 self-start rounded-full border border-white/10 bg-white/[0.03] py-1 pl-2 pr-3 text-xs text-muted hover:text-fg">
              <ArrowLeft className="size-3.5 shrink-0" aria-hidden /> <span className="truncate">{f.email}</span>
            </button>
            <PasswordField value={f.password} onChange={(v) => setF({ ...f, password: v })} autoComplete="new-password" meter={pw} autoFocus />
            <Field icon={<Phone className="size-4" />} label="Numéro Wave (facultatif, pour retrouver vos paiements)" bad={!phoneOk} ok={!!f.phone.trim() && phoneOk}>
              {(id) => <input id={id} className="input !pl-10" type="tel" inputMode="tel" placeholder="+221 77 000 00 00" autoComplete="tel" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} />}
            </Field>
            <label className="flex cursor-pointer gap-3 rounded-xl border border-white/10 bg-white/[0.02] p-3 text-sm leading-relaxed text-muted has-[:checked]:border-brand-400/40 has-[:checked]:bg-brand-400/[0.05]">
              <input type="checkbox" className="mt-1 size-4 shrink-0 accent-brand-500" checked={f.accept} onChange={(e) => setF({ ...f, accept: e.target.checked })} />
              <span>J&apos;accepte les <Link href="/risques/#conditions" className="text-brand-300 underline">conditions</Link> et j&apos;ai lu l&apos;<Link href="/risques/" className="text-brand-300 underline">avertissement sur les risques</Link>.</span>
            </label>
            {/* Trap for form robots: off-screen, out of the tab order, hidden from screen readers. Keep it that way. */}
            <div className="absolute -left-[10000px] top-auto h-px w-px overflow-hidden" aria-hidden="true">
              <label>Site web<input type="text" name="website" tabIndex={-1} autoComplete="off" value={f.website} onChange={(e) => setF({ ...f, website: e.target.value })} /></label>
            </div>
            {turnstile && <Turnstile key={captchaKey} siteKey={turnstile} onToken={setCaptcha} />}
            <ErrorLine err={err} />
            <MorphButton state={state} disabled={!ready2}>Créer mon compte</MorphButton>
            <p className="flex items-center justify-center gap-1.5 text-center text-xs text-faint"><KeyRound className="size-3.5" aria-hidden /> Mot de passe chiffré (scrypt), jamais stocké en clair.</p>
          </motion.form>
        )}
      </AnimatePresence>
    </div>
  );
}

// ---------------- e-mail links: forgotten password, confirmation ----------------
function Forgot({ onBack }: { onBack: () => void }) {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "busy" | "done">("idle");
  const [err, setErr] = useState<string | null>(null);
  const ok = EMAIL_RE.test(email.trim());
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setState("busy");
    setErr(null);
    try {
      await api("/api/m/password/forgot", { method: "POST", body: { email: email.trim() } });
      setState("done");
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Erreur");
      setState("idle");
    }
  };
  return (
    <form onSubmit={submit} className="grid gap-4" noValidate>
      <button type="button" onClick={onBack} className="flex items-center gap-1.5 self-start text-xs text-muted hover:text-fg"><ArrowLeft className="size-3.5" aria-hidden /> Retour à la connexion</button>
      <div>
        <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">Mot de passe oublié</h2>
        <p className="mt-1 text-sm text-muted">Indiquez l&apos;adresse de votre compte : nous vous envoyons un lien pour choisir un nouveau mot de passe.</p>
      </div>
      {state === "done" ? (
        <Notice kind="ok">Si un compte confirmé existe pour <strong>{email.trim()}</strong>, un lien vient de partir. Il est valable 1 heure ; pensez à regarder dans les spams.</Notice>
      ) : (
        <>
          <Field icon={<Mail className="size-4" />} label="E-mail" ok={ok}>
            {(id) => <input id={id} className="input !pl-10" type="email" required autoComplete="email" inputMode="email" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus />}
          </Field>
          <ErrorLine err={err} />
          <MorphButton state={state} disabled={!ok}>Recevoir le lien</MorphButton>
        </>
      )}
    </form>
  );
}

function ResendLink({ email }: { email: string }) {
  const [state, setState] = useState<"idle" | "busy" | "sent" | "error">("idle");
  const [msg, setMsg] = useState("");
  const resend = async () => {
    setState("busy");
    try {
      await api("/api/m/verify/resend", { method: "POST", body: { email } });
      setState("sent");
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "Erreur");
      setState("error");
    }
  };
  if (state === "sent") return <Notice kind="ok">Si un compte attend sa confirmation pour <strong>{email}</strong>, un nouveau lien vient de partir (valable 48 heures).</Notice>;
  return (
    <div className="grid gap-2">
      {state === "error" && <Notice kind="error">{msg}</Notice>}
      <button type="button" className="btn btn-ghost btn-sm" onClick={resend} disabled={state === "busy" || !EMAIL_RE.test(email)}>
        {state === "busy" ? <Spinner label="" /> : <><MailCheck className="size-4" aria-hidden /> Renvoyer le lien de confirmation</>}
      </button>
    </div>
  );
}

function CheckInbox({ email, onBack }: { email: string; onBack: () => void }) {
  const box = useRef<HTMLDivElement>(null);
  // The two-step form was taller: bring the message into view (on a phone it sits under the scene).
  // Braces matter: recent browsers return a promise from scrollIntoView, which React would take
  // for a clean-up function.
  useEffect(() => {
    box.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, []);
  return (
    <motion.div ref={box} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, ease: EASE }} className="grid gap-4 text-center">
      <motion.div className="mx-auto grid size-14 place-items-center rounded-2xl bg-brand-500/15 text-brand-300" initial={{ scale: 0.6, rotate: -8 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: "spring", stiffness: 380, damping: 18 }}>
        <MailCheck className="size-7" aria-hidden />
      </motion.div>
      <div>
        <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">Confirmez votre adresse</h2>
        <p className="mt-2 text-sm leading-relaxed text-muted">
          Un lien vient de partir vers <span className="break-all text-fg">{email}</span>. Cliquez dessus pour activer votre compte ; il est valable 48 heures.
        </p>
        <p className="mt-2 text-xs text-faint">Rien après quelques minutes ? Regardez dans les spams ou l&apos;onglet « Promotions », puis renvoyez le lien.</p>
      </div>
      <div className="grid gap-2 text-left">
        <ResendLink email={email} />
        <button type="button" className="btn btn-ghost btn-sm" onClick={onBack}>J&apos;ai confirmé : me connecter</button>
      </div>
    </motion.div>
  );
}

// ---------------- pieces ----------------
function Field({ icon, label, ok, bad, children }: { icon: ReactNode; label: string; ok?: boolean; bad?: boolean; children: (id: string) => ReactNode }) {
  const id = useId();
  return (
    <div className="field">
      <label htmlFor={id} className="text-[.8rem] font-medium text-muted">{label}</label>
      <div className="relative">
        <span className={`pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 transition-colors ${bad ? "text-down-400" : ok ? "text-brand-300" : "text-faint"}`}>{icon}</span>
        {children(id)}
        <AnimatePresence>
          {ok && (
            <motion.span key="ok" className="pointer-events-none absolute right-3 top-1/2 grid size-5 -translate-y-1/2 place-items-center rounded-full bg-up-400/15 text-up-300"
              initial={{ scale: 0, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: 0, opacity: 0 }} transition={{ type: "spring", stiffness: 500, damping: 26 }} aria-hidden>
              <Check className="size-3" strokeWidth={3} />
            </motion.span>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

const METER = ["#ef5354", "#ef5354", "#d4b374", "#4fb0ff", "#4be08a"];

export function PasswordField({ value, onChange, autoComplete, meter, autoFocus }: { value: string; onChange: (v: string) => void; autoComplete: string; meter?: ReturnType<typeof strength>; autoFocus?: boolean }) {
  const [show, setShow] = useState(false);
  const id = useId();
  return (
    <div className="field">
      <label htmlFor={id} className="text-[.8rem] font-medium text-muted">Mot de passe</label>
      <div className="relative">
        <KeyRound className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-faint" aria-hidden />
        <input id={id} className="input !pl-10 !pr-11" type={show ? "text" : "password"} required minLength={meter ? MIN_PW : 1} autoComplete={autoComplete} value={value} onChange={(e) => onChange(e.target.value)} autoFocus={autoFocus}
          aria-describedby={meter ? `${id}-m` : undefined} />
        <button type="button" onClick={() => setShow(!show)} className="absolute right-2 top-1/2 grid size-8 -translate-y-1/2 place-items-center rounded-lg text-faint hover:text-fg" aria-label={show ? "Masquer le mot de passe" : "Afficher le mot de passe"} aria-pressed={show}>
          <AnimatePresence mode="wait" initial={false}>
            <motion.span key={show ? "h" : "s"} initial={{ rotate: -90, opacity: 0 }} animate={{ rotate: 0, opacity: 1 }} exit={{ rotate: 90, opacity: 0 }} transition={{ duration: 0.15 }}>
              {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
            </motion.span>
          </AnimatePresence>
        </button>
      </div>
      {meter && (
        <div id={`${id}-m`} className="mt-1.5">
          <div className="grid grid-cols-4 gap-1.5" aria-hidden>
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="h-1.5 overflow-hidden rounded-full bg-white/[0.07]">
                <motion.div className="h-full rounded-full" initial={false} animate={{ width: meter.score >= i ? "100%" : "0%", backgroundColor: METER[meter.score] }} transition={{ duration: 0.35, ease: EASE, delay: (i - 1) * 0.04 }} />
              </div>
            ))}
          </div>
          <div className="mt-1.5 flex justify-between gap-3 text-xs">
            <span style={{ color: value ? METER[meter.score] : undefined }} className={value ? "font-semibold" : "text-faint"} aria-live="polite">{meter.label}</span>
            <span className="text-faint">Une phrase de passe fait l&apos;affaire</span>
          </div>
        </div>
      )}
    </div>
  );
}

function ErrorLine({ err }: { err: string | null }) {
  return (
    <AnimatePresence initial={false}>
      {err && (
        <motion.div key={err} initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
          <Notice kind="error">{err}</Notice>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/** The submit button morphs: label, then a spinning ring, then a check drawn on a green pill. */
function MorphButton({ state, disabled, children }: { state: "idle" | "busy" | "done"; disabled?: boolean; children: ReactNode }) {
  return (
    <motion.button type="submit" layout disabled={disabled || state !== "idle"} aria-busy={state === "busy"}
      className={`btn relative mt-1 h-12 w-full overflow-hidden ${state === "done" ? "border border-up-400/40 bg-up-500/20 text-up-300" : "btn-primary"} disabled:cursor-not-allowed disabled:opacity-60 ${state !== "idle" ? "!opacity-100" : ""}`}
      whileTap={state === "idle" && !disabled ? { scale: 0.98 } : undefined}>
      <AnimatePresence mode="wait" initial={false}>
        {state === "idle" && <motion.span key="i" className="flex items-center gap-2" initial={{ y: 12, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: -12, opacity: 0 }} transition={{ duration: 0.18 }}>{children}</motion.span>}
        {state === "busy" && (
          <motion.span key="b" initial={{ scale: 0.6, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: 0.6, opacity: 0 }} transition={{ duration: 0.18 }} role="status" aria-label="Envoi en cours">
            <motion.svg viewBox="0 0 24 24" className="size-5" animate={{ rotate: 360 }} transition={{ repeat: Infinity, duration: 0.8, ease: "linear" }}>
              <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeOpacity=".25" strokeWidth="3" />
              <path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
            </motion.svg>
          </motion.span>
        )}
        {state === "done" && (
          <motion.span key="d" className="flex items-center gap-2" initial={{ scale: 0.6, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: "spring", stiffness: 420, damping: 22 }}>
            <svg viewBox="0 0 24 24" className="size-5" aria-hidden><motion.path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.35, ease: EASE }} /></svg>
            C&apos;est fait
          </motion.span>
        )}
      </AnimatePresence>
    </motion.button>
  );
}
