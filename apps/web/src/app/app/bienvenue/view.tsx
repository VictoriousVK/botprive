"use client";

// Guided set-up after sign-up, in four steps: who you are, your prop firm, your risk plan, your
// first account. Each step is saved when the member moves on and can be skipped; everything
// stays editable in Réglages. The amounts shown are arithmetic on the member's own inputs and on
// the firm profile (config/prop_firms.yaml), never an estimate.

import { AnimatePresence, motion } from "framer-motion";
import { ArrowLeft, ArrowRight, Building2, Check, Crosshair, ExternalLink, Minus, Plus, ShieldCheck, Upload, UserRound, Wallet } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Seg } from "@/components/app-ui";
import { KILLZONES } from "@/components/session-scene";
import { Notice, Spinner } from "@/components/ui";
import { appApi, type Account, type Profile, type PropProfile, type TradingPlan } from "@/lib/app";
import { useSession } from "@/lib/session";

const EASE = [0.22, 1, 0.36, 1] as const;
const STEPS = ["Vous", "Prop firm", "Plan de risque", "Compte"] as const;

const LEVELS: [string, string, string][] = [
  ["debutant", "Débutant", "J'apprends les bases, je trade peu ou en démo"],
  ["intermediaire", "Intermédiaire", "Je trade régulièrement, mes résultats varient"],
  ["confirme", "Confirmé", "J'ai une méthode et un historique"],
  ["professionnel", "Professionnel", "Je gère un capital financé, ou le mien, à plein temps"],
];
const EXPERIENCE: [number, string][] = [[3, "Moins de 6 mois"], [9, "6 à 12 mois"], [24, "1 à 3 ans"], [48, "Plus de 3 ans"]];
const GOALS = ["Réussir une évaluation prop firm", "Trader avec régularité", "Respecter mon plan", "Maîtriser les concepts ICT", "Automatiser avec des EA"];
const MARKETS: [string, string[]][] = [["CFD et Forex", ["XAUUSD", "NAS100", "US30", "EURUSD", "GBPUSD"]], ["Futures (CME)", ["MNQ", "NQ", "MES", "ES", "MGC"]]];
const FIRMS: [string, string, string][] = [
  ["none", "Aucune", "Mon capital, mon plan"], ["Topstep", "Topstep", "Futures"], ["Tradeify", "Tradeify", "Futures"],
  ["FundingPips", "FundingPips", "CFD et Forex"], ["FTMO", "FTMO", "CFD et Forex"], ["other", "Autre", "Une autre firme"],
];
const CFD_SIZES = [10000, 25000, 50000, 100000, 200000];
const RESET: Record<string, string> = { ny_17: "17:00 à New York", ny_18: "18:00 à New York (journée CME)", cet_0: "minuit, heure d'Europe centrale", utc3_0: "minuit UTC+3 (heure MT5)", utc_0: "minuit UTC" };
const MAX_TYPE: Record<string, string> = { static: "fixe", trailing: "suiveuse", trailing_eod: "suiveuse en fin de journée" };
const CONS: Record<string, string> = { target: "de l'objectif", total_profit: "du profit total", positive_days: "des jours gagnants" };

const usd = (n: number) => `${Math.round(n).toLocaleString("fr-FR").replace(/\u202f/g, "\u00a0")}\u00a0$`;
const k$ = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}K` : String(n));
const hhmm = (m: number) => `${String(Math.floor(m / 60) % 24).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const programName = (p: PropProfile) => p.label.split(" — ").slice(1).join(" — ") || p.label;
const sizesOf = (p?: PropProfile) => (p?.sizes ? Object.keys(p.sizes).map(Number).sort((a, b) => a - b) : CFD_SIZES);

type Loaded = { profile: Profile; plan: TradingPlan; profiles: PropProfile[]; propGuard: boolean; accounts: Account[] };

export function WelcomeView() {
  const { me, ready } = useSession();
  const router = useRouter();
  useEffect(() => {
    if (ready && !me) router.replace("/compte/?vue=connexion&suite=/app/bienvenue/");
  }, [ready, me, router]);
  if (!ready || !me) return <div className="container-x py-14"><Spinner /></div>;
  return <Onboarding firstName={me.name.split(" ")[0]} />;
}

function Onboarding({ firstName }: { firstName: string }) {
  const [data, setData] = useState<Loaded | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    Promise.all([
      appApi<Profile>("/api/app/profile"),
      appApi<{ plan: TradingPlan }>("/api/app/plan"),
      appApi<{ profiles: PropProfile[]; prop_guard: boolean }>("/api/app/risk/profiles"),
      appApi<Account[]>("/api/app/accounts"),
    ])
      .then(([profile, plan, pr, accounts]) => setData({ profile, plan: plan.plan, profiles: pr.profiles, propGuard: pr.prop_guard, accounts }))
      .catch((e) => setErr(e instanceof Error ? e.message : "Erreur"));
  }, []);
  if (err) return <div className="container-x py-14"><Notice kind="error">{err}</Notice></div>;
  if (!data) return <div className="container-x py-14"><Spinner /></div>;
  return <Wizard firstName={firstName} init={data} />;
}

const slide = {
  enter: (d: number) => ({ opacity: 0, x: 56 * d, filter: "blur(6px)" }),
  center: { opacity: 1, x: 0, filter: "blur(0px)" },
  exit: (d: number) => ({ opacity: 0, x: -56 * d, filter: "blur(6px)" }),
};

function Wizard({ firstName, init }: { firstName: string; init: Loaded }) {
  const known = FIRMS.some(([k]) => k === init.profile.prop_firm);
  const programsOf = (f: string) => init.profiles.filter((p) => p.firm === f);
  const firstFirm = init.profile.prop_firm ? (known ? init.profile.prop_firm : "other") : "none";

  const [step, setStep] = useState(0);
  const [dir, setDir] = useState(1);
  const [profile, setProfile] = useState<Profile>(init.profile);
  const [plan, setPlan] = useState<TradingPlan>(init.plan);
  const [firm, setFirm] = useState(firstFirm);
  const [other, setOther] = useState(firstFirm === "other" ? init.profile.prop_firm ?? "" : "");
  const [key, setKey] = useState<string | null>(programsOf(firstFirm)[0]?.key ?? null);
  const [size, setSize] = useState(50000);
  const [acct, setAcct] = useState<{ label?: string; kind?: Account["kind"]; balance?: string; broker: string }>({ broker: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<{ account: Account | null } | null>(null);

  const p = firm !== "none" && firm !== "other" ? init.profiles.find((x) => x.key === key) : undefined;
  const firmLabel = FIRMS.find(([k]) => k === firm)?.[1] ?? firm;
  const label = acct.label ?? (p ? `${firmLabel} ${k$(size)}` : firm === "other" ? other.trim() || "Compte prop firm" : "Mon compte");
  const kind = acct.kind ?? (firm === "none" ? "demo" : "prop");
  const balance = acct.balance ?? (p ? String(size) : "");

  const chooseFirm = (f: string) => {
    setFirm(f);
    const first = programsOf(f)[0];
    setKey(first?.key ?? null);
    const ss = sizesOf(first);
    setSize(ss.includes(size) ? size : ss.includes(50000) ? 50000 : ss[0]);
    setAcct((a) => ({ broker: a.broker }));
  };
  const chooseProgram = (k: string) => {
    setKey(k);
    const ss = sizesOf(init.profiles.find((x) => x.key === k));
    if (!ss.includes(size)) setSize(ss.includes(50000) ? 50000 : ss[0]);
  };

  const go = (to: number) => {
    setDir(to > step ? 1 : -1);
    setErr(null);
    setStep(to);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };
  const save = async (fn: () => Promise<unknown>, after: () => void) => {
    setBusy(true);
    setErr(null);
    try {
      await fn();
      after();
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  const bal = Number(String(balance).replace(/\s/g, "").replace(",", "."));
  const next = () => {
    if (step === 0) return save(async () => { await appApi("/api/app/profile", "PUT", profile); await appApi("/api/app/plan", "PUT", plan); }, () => go(1));
    if (step === 1) {
      const body = { ...profile, prop_firm: firm === "none" ? null : firm === "other" ? other.trim().slice(0, 60) || null : firm };
      return save(async () => { await appApi("/api/app/profile", "PUT", body); setProfile(body); }, () => go(2));
    }
    if (step === 2) return save(() => appApi("/api/app/plan", "PUT", plan), () => go(3));
    return save(async () => {
      const a = await appApi<Account>("/api/app/accounts", "POST", {
        label: label.trim(), kind, broker: acct.broker.trim(), currency: "USD", starting_balance: bal > 0 ? bal : null, prop_profile: p?.key ?? null,
      });
      setDone({ account: a });
    }, () => window.scrollTo({ top: 0, behavior: "smooth" }));
  };
  const skip = () => (step < 3 ? go(step + 1) : setDone({ account: null }));
  const valid = step === 3 ? label.trim().length >= 2 && (!balance || bal > 0) : step === 1 ? firm !== "other" || other.trim().length >= 2 : true;

  return (
    <div className="container-x max-w-3xl py-8 sm:py-12">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <p className="eyebrow">Mise en route · 2 minutes</p>
          <h1 className="h-section mt-2">Bienvenue {firstName}</h1>
          <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted">Quatre réglages, et votre journal, votre Coach et votre garde-fou partent de votre réalité. Tout reste modifiable dans Réglages.</p>
        </div>
        {!done && <Link href="/app/" className="btn btn-ghost btn-sm">Plus tard</Link>}
      </div>
      <Rail step={done ? 4 : step} />
      <div className="card relative mt-6 overflow-clip p-5 sm:p-7">
        <div className="pointer-events-none absolute -right-28 -top-28 size-64 rounded-full bg-brand-500/10 blur-3xl" aria-hidden />
        <AnimatePresence mode="wait" custom={dir} initial={false}>
          <motion.div key={done ? "done" : step} custom={dir} variants={slide} initial="enter" animate="center" exit="exit" transition={{ duration: 0.34, ease: EASE }} className="relative">
            {done ? <Done account={done.account} futures={p?.market === "futures"} />
              : step === 0 ? <StepYou profile={profile} setProfile={setProfile} plan={plan} setPlan={setPlan} />
              : step === 1 ? <StepFirm firm={firm} chooseFirm={chooseFirm} other={other} setOther={setOther} programs={programsOf(firm)} p={p} chooseProgram={chooseProgram} size={size} setSize={setSize} propGuard={init.propGuard} />
              : step === 2 ? <StepPlan plan={plan} setPlan={setPlan} p={p} size={size} balance={bal > 0 ? bal : null} />
              : <StepAccount accounts={init.accounts} label={label} kind={kind} balance={balance} broker={acct.broker} p={p} size={size} set={(v) => setAcct((a) => ({ ...a, ...v }))} />}
          </motion.div>
        </AnimatePresence>
        {!done && (
          <>
            {err && <Notice kind="error" className="mt-5">{err}</Notice>}
            <div className="relative mt-7 flex flex-wrap items-center justify-between gap-3 border-t border-white/5 pt-5">
              {step > 0 ? <button type="button" className="btn btn-ghost btn-sm" onClick={() => go(step - 1)}><ArrowLeft className="size-4" aria-hidden /> Retour</button> : <span />}
              <div className="flex items-center gap-2">
                <button type="button" className="rounded-lg px-3 py-2 text-sm text-muted hover:text-fg" onClick={skip}>{step === 3 ? "Terminer sans compte" : "Passer"}</button>
                <motion.button type="button" className="btn btn-primary btn-sm min-w-32" onClick={next} disabled={busy || !valid} whileTap={{ scale: 0.97 }}>
                  {busy ? <Spinner label="" /> : <>{step === 3 ? "Terminer" : "Continuer"} <ArrowRight className="size-4" aria-hidden /></>}
                </motion.button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// ---------------- progress: a price line that rises from step to step ----------------
const RW = 600;
const RX = [30, 210, 390, 570];
const RY = [52, 39, 26, 13];

function Rail({ step }: { step: number }) {
  // Four equal segments that wiggle like price: a third of the path is exactly one step.
  const d = useMemo(() => {
    let s = `M${RX[0]} ${RY[0]}`;
    for (let i = 0; i < 3; i++) {
      const at = (t: number, dy: number) => `${RX[i] + (RX[i + 1] - RX[i]) * t} ${RY[i] + (RY[i + 1] - RY[i]) * t + dy}`;
      s += ` L${at(0.2, 8)} L${at(0.42, -6)} L${at(0.66, 5)} L${at(0.84, -3)} L${RX[i + 1]} ${RY[i + 1]}`;
    }
    return s;
  }, []);
  return (
    <div className="relative mt-8" role="group" aria-label={step >= 4 ? "Mise en route terminée" : `Étape ${step + 1} sur 4 : ${STEPS[step]}`}>
      <svg viewBox={`0 0 ${RW} 64`} className="block h-auto w-full overflow-visible" aria-hidden>
        <defs>
          <linearGradient id="rail-g" x1="0" x2="1">
            <stop offset="0" stopColor="#4fb0ff" />
            <stop offset="1" stopColor="#4be08a" />
          </linearGradient>
        </defs>
        <path d={d} fill="none" stroke="rgb(148 163 184 / .2)" strokeWidth="1.5" strokeDasharray="3 5" strokeLinejoin="round" />
        <motion.path d={d} fill="none" stroke="url(#rail-g)" strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round"
          initial={{ pathLength: 0 }} animate={{ pathLength: Math.min(step, 3) / 3 }} transition={{ duration: 0.9, ease: EASE }} />
        {RX.map((x, i) => {
          const reached = i < step || step >= 4;
          return (
            <g key={x}>
              {i === step && step < 4 && (
                <motion.circle cx={x} cy={RY[i]} r="8" fill="none" stroke="#4fb0ff" strokeWidth="1.5" initial={{ scale: 1, opacity: 0.9 }} animate={{ scale: 2.4, opacity: 0 }} transition={{ duration: 1.8, repeat: Infinity, ease: "easeOut" }} />
              )}
              <motion.circle cx={x} cy={RY[i]} r="7" strokeWidth="1.5" initial={false}
                animate={{ fill: reached ? "#4be08a" : i === step ? "#4fb0ff" : "#0c1522", stroke: reached || i === step ? "rgba(0,0,0,0)" : "rgba(148,163,184,.4)" }}
                transition={{ duration: 0.35, delay: reached ? 0.55 : 0 }} />
              {reached && <motion.path d={`M${x - 3.2} ${RY[i] + 0.2}l2.2 2.2 4.2-4.6`} fill="none" stroke="#03050a" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ delay: 0.75, duration: 0.25 }} />}
            </g>
          );
        })}
      </svg>
      <ol className="relative mt-1 h-5 text-xs">
        {STEPS.map((s, i) => (
          <li key={s} className={`absolute -translate-x-1/2 whitespace-nowrap transition-colors ${i === step ? "font-semibold text-fg" : i < step || step >= 4 ? "text-up-300" : "text-faint"}`} style={{ left: `${(RX[i] / RW) * 100}%` }} aria-current={i === step ? "step" : undefined}>{s}</li>
        ))}
      </ol>
    </div>
  );
}

// ---------------- steps ----------------
function StepYou({ profile, setProfile, plan, setPlan }: { profile: Profile; setProfile: (p: Profile) => void; plan: TradingPlan; setPlan: (p: TradingPlan) => void }) {
  const exp = EXPERIENCE.reduce((best, [v]) => (Math.abs(v - profile.experience_months) < Math.abs(best - profile.experience_months) ? v : best), EXPERIENCE[0][0]);
  const toggle = <T,>(list: T[], v: T, max = 99) => (list.includes(v) ? list.filter((x) => x !== v) : list.length >= max ? list : [...list, v]);
  return (
    <div>
      <StepHead n={1} icon={<UserRound className="size-5" />} title="Parlez-nous de votre trading" text="Le Coach adapte ses explications à ce que vous déclarez ici. Il ne devine rien." />
      <Group label="Votre niveau">
        <div className="grid gap-2 sm:grid-cols-2">
          {LEVELS.map(([k, t, d]) => <Choice key={k} group="level" active={profile.level === k} onClick={() => setProfile({ ...profile, level: k })} title={t} text={d} />)}
        </div>
      </Group>
      <Group label="Depuis combien de temps tradez-vous ?">
        <div className="flex flex-wrap gap-2">
          {EXPERIENCE.map(([v, l]) => <Pill key={v} active={exp === v} onClick={() => setProfile({ ...profile, experience_months: v })}>{l}</Pill>)}
        </div>
      </Group>
      <Group label="Comment tradez-vous ?" hint="un ou deux choix">
        <div className="flex flex-wrap gap-2">
          <Pill active={profile.trades_manually} onClick={() => setProfile({ ...profile, trades_manually: !profile.trades_manually })}>À la main</Pill>
          <Pill active={profile.uses_eas} onClick={() => setProfile({ ...profile, uses_eas: !profile.uses_eas })}>Avec des robots (EA)</Pill>
        </div>
      </Group>
      <Group label="Vos marchés" hint="plusieurs choix possibles">
        <div className="grid gap-3">
          {MARKETS.map(([g, list]) => (
            <div key={g} className="flex flex-wrap items-center gap-2">
              <span className="w-full text-xs text-faint sm:w-28">{g}</span>
              {list.map((m) => <Pill key={m} mono active={plan.markets.includes(m)} onClick={() => setPlan({ ...plan, markets: toggle(plan.markets, m, 20) })}>{m}</Pill>)}
            </div>
          ))}
        </div>
      </Group>
      <Group label="Vos objectifs" hint="jusqu'à 3">
        <div className="flex flex-wrap gap-2">
          {GOALS.map((g) => <Pill key={g} active={profile.goals.includes(g)} onClick={() => setProfile({ ...profile, goals: toggle(profile.goals, g, 3) })}>{g}</Pill>)}
        </div>
      </Group>
    </div>
  );
}

function StepFirm({ firm, chooseFirm, other, setOther, programs, p, chooseProgram, size, setSize, propGuard }: {
  firm: string; chooseFirm: (f: string) => void; other: string; setOther: (s: string) => void; programs: PropProfile[]; p?: PropProfile; chooseProgram: (k: string) => void;
  size: number; setSize: (n: number) => void; propGuard: boolean;
}) {
  return (
    <div>
      <StepHead n={2} icon={<Building2 className="size-5" />} title="Tradez-vous pour une prop firm ?" text="Le garde-fou suit alors les limites de la firme sur votre compte : perte du jour, perte maximale, objectif, plafond de contrats." />
      <div className="mt-6 grid grid-cols-2 gap-2 sm:grid-cols-3">
        {FIRMS.map(([k, t, d]) => <Choice key={k} group="firm" active={firm === k} onClick={() => chooseFirm(k)} title={t} text={d} />)}
      </div>
      {firm === "other" && (
        <div className="mt-4 grid gap-2">
          <input className="input" placeholder="Nom de la firme" maxLength={60} value={other} onChange={(e) => setOther(e.target.value)} aria-label="Nom de la firme" autoFocus />
          <p className="text-xs text-faint">Nous n&apos;avons pas encore le règlement de cette firme : votre plan personnel s&apos;applique. Le nom que vous indiquez nous aide à choisir les prochains profils.</p>
        </div>
      )}
      {programs.length > 1 && (
        <Group label="Programme">
          <div className="flex flex-wrap gap-2">
            {programs.map((x) => <Pill key={x.key} active={x.key === p?.key} onClick={() => chooseProgram(x.key)}>{programName(x)}</Pill>)}
          </div>
        </Group>
      )}
      {p && (
        <Group label="Taille du compte">
          <div className="flex flex-wrap gap-2">
            {sizesOf(p).map((s) => <Pill key={s} mono active={s === size} onClick={() => setSize(s)}>{k$(s)}</Pill>)}
          </div>
        </Group>
      )}
      <AnimatePresence initial={false}>
        {p && (
          <motion.div key="rules" initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
            <Rules p={p} size={size} />
            {!propGuard && (
              <Notice kind="info" className="mt-3">
                Le suivi automatique de ces règles fait partie de l&apos;offre Pro Trader. D&apos;ici là, le garde-fou applique votre plan personnel.{" "}
                <Link href="/tarifs/" className="font-semibold text-brand-300 hover:underline">Voir les offres</Link>
              </Notice>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

/** The firm's rules for this account size, in plain words; amounts are the profile's own figures. */
function rulesOf(p: PropProfile, size: number): [string, string][] {
  const s = p.sizes?.[String(size)];
  const out: [string, string][] = [];
  if (s?.daily_loss) out.push(["Perte du jour", usd(s.daily_loss)]);
  else if (typeof p.daily_loss_pct === "number")
    out.push(["Perte du jour", p.daily_loss_ref === "initial_balance" ? `${p.daily_loss_pct} % du capital initial (${usd((p.daily_loss_pct / 100) * size)})` : `${p.daily_loss_pct} % du solde du début de journée`]);
  else if (p.sizes) out.push(["Perte du jour", "aucune dans ce programme"]);
  const maxAmt = s?.max_loss ?? (p.max_loss_pct ? (p.max_loss_pct / 100) * size : null);
  if (maxAmt) {
    const trailing = (p.max_loss_type ?? "").startsWith("trailing");
    const lock = p.trailing_lock === "initial" ? ", bloquée au capital de départ" : p.trailing_lock === "initial_plus_100" ? ", bloquée à +100 $" : trailing ? ", sans blocage" : "";
    out.push(["Perte maximale", `${usd(maxAmt)}, ${MAX_TYPE[p.max_loss_type ?? "static"] ?? p.max_loss_type}${lock}`]);
  }
  const tp = Array.isArray(p.profit_target_pct) ? p.profit_target_pct : p.profit_target_pct != null ? [p.profit_target_pct] : [];
  if (s?.profit_target) out.push(["Objectif de profit", usd(s.profit_target)]);
  else if (tp.length) out.push(["Objectif de profit", tp.map((x) => `${x} % (${usd((x / 100) * size)})`).join(" puis ")]);
  if (s?.max_contracts) out.push(["Contrats au plus", `${s.max_contracts} minis ou ${s.max_contracts * 10} micros`]);
  if (p.consistency) out.push(["Régularité", `meilleur jour ≤ ${p.consistency.pct} % ${CONS[p.consistency.base] ?? ""}`]);
  if (p.min_trading_days) out.push(["Jours de trading", `${p.min_trading_days} au moins`]);
  if (p.reset) out.push(["Nouvelle journée", RESET[p.reset] ?? p.reset]);
  return out;
}

function Rules({ p, size }: { p: PropProfile; size: number }) {
  const rows = rulesOf(p, size);
  return (
    <div className="mt-5 rounded-xl border border-white/10 bg-ink-950/50 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs font-semibold uppercase tracking-wider text-faint">Règles suivies · {k$(size)}</span>
        {p.verified_at ? <span className="chip chip-green">Vérifié le {p.verified_at}</span> : <span className="chip chip-gold">À vérifier</span>}
      </div>
      <motion.dl key={`${p.key}-${size}`} className="mt-3 grid gap-x-6 gap-y-2 sm:grid-cols-2" initial="hidden" animate="show" variants={{ show: { transition: { staggerChildren: 0.035 } } }}>
        {rows.map(([k, v]) => (
          <motion.div key={k} variants={{ hidden: { opacity: 0, y: 6 }, show: { opacity: 1, y: 0 } }} className="flex justify-between gap-3 border-b border-white/5 pb-2 text-sm">
            <dt className="shrink-0 text-muted">{k}</dt>
            <dd className="text-right text-fg/90">{v}</dd>
          </motion.div>
        ))}
      </motion.dl>
      {!p.verified_at && (
        <p className="mt-3 text-xs leading-relaxed text-faint">
          Relevé le {p.retrieved_at ?? "—"} sur les pages d&apos;aide de la firme, pas encore relu par notre équipe. Comparez avec le
          {p.source ? <> <a href={p.source} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 underline underline-offset-2 hover:text-muted">règlement officiel <ExternalLink className="size-3" aria-hidden /></a></> : " règlement officiel"}.
          {p.notes ? ` ${p.notes}` : ""}
        </p>
      )}
    </div>
  );
}

function StepPlan({ plan, setPlan, p, size, balance }: { plan: TradingPlan; setPlan: (p: TradingPlan) => void; p?: PropProfile; size: number; balance: number | null }) {
  const base = p ? size : balance ?? 10000;
  const example = !p && !balance;
  const riskAmt = (plan.risk_per_trade_pct / 100) * base;
  const dayAmt = (plan.max_daily_loss_pct / 100) * base;
  const s = p?.sizes?.[String(size)];
  const firmDay = s?.daily_loss ?? (p && typeof p.daily_loss_pct === "number" ? (p.daily_loss_pct / 100) * size : null);
  const kz = (k: string) => (plan.killzones.includes(k) ? plan.killzones.filter((x) => x !== k) : [...plan.killzones, k]);
  return (
    <div>
      <StepHead n={3} icon={<ShieldCheck className="size-5" />} title="Votre plan de risque" text="Le Coach compare chacun de vos trades à ce plan, et le garde-fou s'en sert pour calculer la taille de vos positions." />
      <div className="mt-6 grid gap-5 sm:grid-cols-2">
        <Slider label="Risque par trade" value={plan.risk_per_trade_pct} min={0.25} max={Math.max(2, plan.risk_per_trade_pct)} step={0.25} onChange={(v) => setPlan({ ...plan, risk_per_trade_pct: v })} sub={`${usd(riskAmt)} par trade`} />
        <Slider label="Perte maximale du jour" value={plan.max_daily_loss_pct} min={0.5} max={Math.max(10, plan.max_daily_loss_pct)} step={0.5} onChange={(v) => setPlan({ ...plan, max_daily_loss_pct: v })} sub={`${usd(dayAmt)} par jour`} />
      </div>
      <div className="mt-6 grid gap-5 sm:grid-cols-2">
        <div>
          <div className="mb-2.5 text-sm font-semibold">Trades par jour, au plus</div>
          <Stepper value={plan.max_trades_per_day} min={1} max={10} onChange={(v) => setPlan({ ...plan, max_trades_per_day: v })} />
        </div>
        <div>
          <div className="mb-2.5 text-sm font-semibold">Rapport risque / rendement minimal</div>
          <Seg label="Rapport risque rendement minimal" value={String(plan.min_rr)} options={[["1", "1:1"], ["1.5", "1:1,5"], ["2", "1:2"], ["3", "1:3"]]} onChange={(v) => setPlan({ ...plan, min_rr: Number(v) })} />
        </div>
      </div>
      <Group label="Vos killzones" hint="heures de New York">
        <div className="flex flex-wrap gap-2">
          {KILLZONES.map(([k, l, a, b, col]) => (
            <Pill key={k} active={plan.killzones.includes(k)} onClick={() => setPlan({ ...plan, killzones: kz(k) as TradingPlan["killzones"] })} color={col}>
              {l} <span className="num text-xs opacity-70">{hhmm(a)}–{hhmm(b)}</span>
            </Pill>
          ))}
        </div>
      </Group>
      <div className="mt-6 rounded-xl border border-brand-400/20 bg-gradient-to-br from-brand-400/[0.07] to-transparent p-4 text-sm leading-relaxed">
        <p>
          Je risque au plus <Amount v={`${plan.risk_per_trade_pct.toLocaleString("fr-FR")} %`} /> par trade (<Amount v={usd(riskAmt)} />), je prends <Amount v={`${plan.max_trades_per_day} trade${plan.max_trades_per_day > 1 ? "s" : ""}`} /> par jour au plus,
          et j&apos;arrête la journée à <Amount v={`−${plan.max_daily_loss_pct.toLocaleString("fr-FR")} %`} /> (<Amount v={`−${usd(dayAmt)}`} />).
        </p>
        <p className="mt-1 text-xs text-faint">{example ? "Exemple sur un compte de 10 000 $ : le calcul se fera sur votre solde réel." : `Calculé sur ${usd(base)}.`}</p>
      </div>
      {plan.risk_per_trade_pct > 2 && <Notice kind="warn" className="mt-3">Plus de 2 % par trade : une courte série de pertes entame vite le compte.</Notice>}
      {firmDay != null && dayAmt > firmDay && (
        <Notice kind="warn" className="mt-3">
          Votre limite du jour ({usd(dayAmt)}) dépasse celle de la firme ({usd(firmDay)}). Le garde-fou suit la limite de la firme ; fixez la vôtre en dessous pour garder de la marge.
        </Notice>
      )}
    </div>
  );
}

function StepAccount({ accounts, label, kind, balance, broker, p, size, set }: {
  accounts: Account[]; label: string; kind: Account["kind"]; balance: string; broker: string; p?: PropProfile; size: number;
  set: (v: Partial<{ label: string; kind: Account["kind"]; balance: string; broker: string }>) => void;
}) {
  return (
    <div>
      <StepHead n={4} icon={<Wallet className="size-5" />} title="Votre premier compte" text="Le journal range vos trades par compte, et le garde-fou suit les limites à partir du solde de départ. Aucun identifiant ni mot de passe de broker n'est demandé ici." />
      {accounts.length > 0 && (
        <Notice kind="info" className="mt-5">Vous avez déjà {accounts.length} compte{accounts.length > 1 ? "s" : ""} : {accounts.map((a) => a.label).join(", ")}. Ajoutez-en un autre ou terminez sans compte.</Notice>
      )}
      <div className="mt-6 grid gap-4 sm:grid-cols-2">
        <label className="field sm:col-span-2"><span>Nom du compte</span><input className="input" maxLength={80} value={label} onChange={(e) => set({ label: e.target.value })} /></label>
        <div className="field"><span>Type</span><Seg label="Type de compte" value={kind} options={[["demo", "Démo"], ["real", "Réel"], ["prop", "Prop firm"]]} onChange={(v) => set({ kind: v })} /></div>
        <label className="field"><span>Solde de départ (USD)</span><input className="input num" inputMode="decimal" placeholder="ex. 10000" value={balance} onChange={(e) => set({ balance: e.target.value })} /></label>
        <label className="field sm:col-span-2"><span>Broker ou plateforme (facultatif)</span><input className="input" maxLength={80} placeholder={p?.market === "futures" ? "ex. Tradovate, TopstepX" : "ex. MetaTrader 5"} value={broker} onChange={(e) => set({ broker: e.target.value })} /></label>
      </div>
      {p && <p className="mt-4 flex flex-wrap items-center gap-2 text-xs text-muted">Règles associées à ce compte : <span className="chip chip-blue">{p.label} · {k$(size)}</span></p>}
      {!balance && <p className="mt-3 text-xs text-faint">Sans solde de départ, le garde-fou ne peut pas calculer vos marges ; vous pourrez l&apos;ajouter plus tard.</p>}
    </div>
  );
}

const NEXT: [string, typeof Upload, string, string][] = [
  ["/app/journal/?vue=comptes", Upload, "Importer mon historique", "Rapport MT5 (HTML) ou CSV"],
  ["/app/risque/", ShieldCheck, "Voir mes limites", "Marge du jour et perte maximale"],
  ["/app/analyse/", Crosshair, "Analyser un setup", "Lecture ICT de vos marchés"],
];

function Done({ account, futures }: { account: Account | null; futures: boolean }) {
  return (
    <div className="grid justify-items-center py-2 text-center">
      <Burst />
      <motion.h2 className="mt-5 font-[family-name:var(--font-display)] text-2xl font-bold" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.5 }}>Votre espace est prêt</motion.h2>
      <motion.p className="mt-2 max-w-md text-sm leading-relaxed text-muted" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.6 }}>
        {account ? <>Compte « {account.label} » créé. </> : null}
        Importez maintenant votre historique : statistiques, Coach et garde-fou travaillent sur vos vrais trades.
      </motion.p>
      <div className="mt-6 grid w-full gap-3 text-left sm:grid-cols-3">
        {NEXT.map(([href, Icon, t, d], i) => (
          <motion.div key={href} initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.7 + i * 0.1, ease: EASE }}>
            <Link href={href} className="card card-hover flex h-full items-start gap-3 p-4">
              <span className="grid size-9 shrink-0 place-items-center rounded-lg border border-brand-400/30 bg-brand-400/10 text-brand-300"><Icon className="size-4" aria-hidden /></span>
              <span className="min-w-0"><span className="block font-semibold">{t}</span><span className="text-sm text-muted">{d}</span></span>
            </Link>
          </motion.div>
        ))}
      </div>
      {futures && <p className="mt-4 max-w-md text-xs text-faint">Import des relevés TopstepX et Tradovate : en préparation. D&apos;ici là, vos trades futures se saisissent à la main dans le journal.</p>}
      <Link href="/app/" className="btn btn-ghost btn-sm mt-6">Aller au tableau de bord <ArrowRight className="size-4" aria-hidden /></Link>
    </div>
  );
}

function Burst() {
  return (
    <div className="relative grid size-28 place-items-center" aria-hidden>
      {Array.from({ length: 12 }, (_, i) => (
        <div key={i} className="absolute inset-0" style={{ transform: `rotate(${i * 30}deg)` }}>
          <motion.span className="absolute left-[calc(50%-1.5px)] top-0 h-3.5 w-[3px] rounded-full" style={{ background: i % 2 ? "#4fb0ff" : "#4be08a" }}
            initial={{ y: 34, opacity: 0 }} animate={{ y: [34, -4], opacity: [0, 1, 0] }} transition={{ duration: 0.9, delay: 0.35, ease: EASE }} />
        </div>
      ))}
      <svg viewBox="0 0 64 64" className="size-20">
        <motion.circle cx="32" cy="32" r="28" fill="rgb(75 224 138 / .08)" stroke="#4be08a" strokeWidth="2.5" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.6, ease: EASE }} />
        <motion.path d="M20 33l8 8 16-17" fill="none" stroke="#4be08a" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.4, delay: 0.45, ease: EASE }} />
      </svg>
    </div>
  );
}

// ---------------- pieces ----------------
function StepHead({ n, icon, title, text }: { n: number; icon: ReactNode; title: string; text: string }) {
  return (
    <div className="flex gap-4">
      <span className="grid size-11 shrink-0 place-items-center rounded-xl border border-brand-400/30 bg-brand-400/10 text-brand-300">{icon}</span>
      <div className="min-w-0">
        <div className="num text-xs text-faint">Étape {n} sur 4</div>
        <h2 className="font-[family-name:var(--font-display)] text-xl font-bold">{title}</h2>
        <p className="mt-1 text-sm leading-relaxed text-muted">{text}</p>
      </div>
    </div>
  );
}

function Group({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <fieldset className="mt-6 min-w-0">
      <legend className="mb-2.5 text-sm font-semibold">{label}{hint && <span className="ml-2 text-xs font-normal text-faint">{hint}</span>}</legend>
      {children}
    </fieldset>
  );
}

/** A selectable card; the ring glides from the old choice to the new one (shared layout). */
function Choice({ group, active, onClick, title, text }: { group: string; active: boolean; onClick: () => void; title: string; text?: string }) {
  return (
    <motion.button type="button" onClick={onClick} aria-pressed={active} whileTap={{ scale: 0.98 }}
      className={`relative min-w-0 rounded-xl border p-3.5 text-left transition-colors sm:p-4 ${active ? "border-transparent bg-brand-400/[0.07]" : "border-white/10 bg-white/[0.02] hover:border-white/25"}`}>
      {active && <motion.span layoutId={`ring-${group}`} className="absolute inset-0 rounded-xl border-2 border-brand-400/80 shadow-[0_0_28px_-10px_rgb(79_176_255/.9)]" transition={{ type: "spring", stiffness: 420, damping: 34 }} />}
      <span className="relative flex items-center justify-between gap-2">
        <span className="font-semibold">{title}</span>
        <AnimatePresence initial={false}>
          {active && <motion.span key="c" initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0 }} className="grid size-5 shrink-0 place-items-center rounded-full bg-brand-400 text-ink-950"><Check className="size-3" strokeWidth={3} /></motion.span>}
        </AnimatePresence>
      </span>
      {text && <span className="relative mt-1 block text-xs leading-relaxed text-muted sm:text-sm">{text}</span>}
    </motion.button>
  );
}

function Pill({ active, onClick, children, color, mono }: { active: boolean; onClick: () => void; children: ReactNode; color?: string; mono?: boolean }) {
  return (
    <motion.button type="button" onClick={onClick} aria-pressed={active} whileTap={{ scale: 0.94 }}
      className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition-colors ${mono ? "num" : ""} ${active ? "border-brand-400/60 bg-brand-400/15 text-white" : "border-white/12 bg-white/[0.02] text-muted hover:border-white/30 hover:text-fg"}`}>
      {color && <span className="size-2 rounded-full" style={{ background: color }} />}
      {children}
      <AnimatePresence initial={false}>
        {active && (
          <motion.span key="c" initial={{ width: 0, opacity: 0 }} animate={{ width: "auto", opacity: 1 }} exit={{ width: 0, opacity: 0 }} className="overflow-hidden">
            <Check className="size-3.5 text-brand-300" strokeWidth={3} />
          </motion.span>
        )}
      </AnimatePresence>
    </motion.button>
  );
}

function Slider({ label, value, min, max, step, onChange, sub }: { label: string; value: number; min: number; max: number; step: number; onChange: (v: number) => void; sub: string }) {
  const pos = ((value - min) / (max - min)) * 100;
  return (
    <label className="grid gap-2">
      <span className="flex items-baseline justify-between gap-3">
        <span className="text-sm font-semibold">{label}</span>
        <span className="num overflow-hidden text-lg font-semibold text-fg">
          <AnimatePresence mode="popLayout" initial={false}>
            <motion.span key={value} className="inline-block" initial={{ y: -14, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: 14, opacity: 0 }} transition={{ duration: 0.18 }}>{value.toLocaleString("fr-FR")} %</motion.span>
          </AnimatePresence>
        </span>
      </span>
      <input type="range" className="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} style={{ ["--pos" as string]: `${pos}%` }} />
      <span className="num text-xs text-muted">{sub}</span>
    </label>
  );
}

function Stepper({ value, min, max, onChange }: { value: number; min: number; max: number; onChange: (v: number) => void }) {
  return (
    <div className="inline-flex items-center rounded-xl border border-white/10 bg-white/[0.02]">
      <button type="button" className="grid size-10 place-items-center text-muted hover:text-fg disabled:opacity-40" onClick={() => onChange(Math.max(min, value - 1))} disabled={value <= min} aria-label="Un de moins"><Minus className="size-4" /></button>
      <span className="num relative w-10 overflow-hidden text-center text-lg font-semibold" aria-live="polite">
        <AnimatePresence mode="popLayout" initial={false}>
          <motion.span key={value} className="inline-block" initial={{ y: -14, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: 14, opacity: 0 }} transition={{ duration: 0.18 }}>{value}</motion.span>
        </AnimatePresence>
      </span>
      <button type="button" className="grid size-10 place-items-center text-muted hover:text-fg disabled:opacity-40" onClick={() => onChange(Math.min(max, value + 1))} disabled={value >= max} aria-label="Un de plus"><Plus className="size-4" /></button>
    </div>
  );
}

function Amount({ v }: { v: string }) {
  return (
    <span className="num inline-block font-semibold text-fg">
      <AnimatePresence mode="popLayout" initial={false}>
        <motion.span key={v} className="inline-block" initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 6 }} transition={{ duration: 0.16 }}>{v}</motion.span>
      </AnimatePresence>
    </span>
  );
}
