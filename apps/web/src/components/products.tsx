"use client";

import { motion } from "framer-motion";
import { ArrowRight, Bot, CircleCheck, Clock, Cpu, Lock, MessageCircle, Send, Sparkles } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { api, fcfa, whatsappLink, type Product, type Robot } from "@/lib/api";
import { useApi, useSession } from "@/lib/session";
import { Notice, Reveal, Spinner } from "./ui";

// ---------------- robots ----------------
export function RobotCard({ r, i = 0 }: { r: Robot; i?: number }) {
  const dev = r.status === "development";
  return (
    <Reveal delay={i * 0.08} className="h-full">
      <article id={r.key} className={`card card-hover relative flex h-full flex-col overflow-hidden p-6 ${dev ? "border-dashed" : ""}`}>
        {!dev && <div className="absolute -right-16 -top-16 size-40 rounded-full bg-brand-500/15 blur-3xl" aria-hidden />}
        <div className="flex items-start justify-between gap-3">
          <span className={`grid size-11 place-items-center rounded-xl border ${dev ? "border-gold-400/30 bg-gold-400/5 text-gold-300" : "border-brand-400/30 bg-brand-400/10 text-brand-300"}`}>
            {dev ? <Sparkles className="size-5" /> : <Bot className="size-5" />}
          </span>
          <span className={`chip ${dev ? "chip-gold" : "chip-blue"}`}>{r.status_label}</span>
        </div>
        <h3 className="mt-5 font-[family-name:var(--font-display)] text-xl font-bold">{r.name}</h3>
        <p className="mt-2 text-sm leading-relaxed text-muted">{r.headline}</p>
        <dl className="mt-5 grid gap-2 text-sm">
          <div className="flex justify-between gap-4 border-t border-white/5 pt-2">
            <dt className="text-faint">Marchés</dt>
            <dd className="text-right">{r.markets}</dd>
          </div>
          {r.timeframes.length > 0 && (
            <div className="flex justify-between gap-4 border-t border-white/5 pt-2">
              <dt className="text-faint">Unités de temps</dt>
              <dd className="num text-right">{r.timeframes.map((t) => t.toUpperCase()).join(" · ")}</dd>
            </div>
          )}
          {r.params > 0 && (
            <div className="flex justify-between gap-4 border-t border-white/5 pt-2">
              <dt className="text-faint">Réglages</dt>
              <dd className="num text-right">{r.params} paramètres</dd>
            </div>
          )}
        </dl>
        <div className="mt-auto pt-6">{dev ? <Waitlist interest="next_bot" cta="Être prévenu" /> : <p className="flex items-center gap-2 text-xs text-faint"><Cpu className="size-3.5" /> {r.origin}</p>}</div>
      </article>
    </Reveal>
  );
}

export function RobotGrid() {
  const { data, loading, error } = useApi<Robot[]>("/api/site/robots");
  if (loading) return <Spinner />;
  if (error || !data) return <Notice kind="error">{error ?? "Catalogue indisponible."}</Notice>;
  return (
    <div className="grid gap-5 md:grid-cols-3">
      {data.map((r, i) => (
        <RobotCard key={r.key} r={r} i={i} />
      ))}
    </div>
  );
}

export type Interest = "copytrading" | "next_bot" | "academie" | "newsletter" | "formation" | "mentorat" | "licence";

export function Waitlist({ interest, cta = "M'inscrire" }: { interest: Interest; cta?: string }) {
  const { me } = useSession();
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "busy" | "ok" | string>("idle");
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setState("busy");
    try {
      await api("/api/site/leads", { method: "POST", body: { email: me?.email ?? email, interest } });
      setState("ok");
    } catch (err) {
      setState(err instanceof Error ? err.message : "Erreur");
    }
  };
  if (state === "ok") return <p className="flex items-center gap-2 text-sm text-up-300"><CircleCheck className="size-4" /> C&apos;est noté, nous vous préviendrons.</p>;
  return (
    <form onSubmit={submit} className="flex flex-col gap-2 sm:flex-row">
      {!me && <input className="input !py-2 text-sm" type="email" required placeholder="votre@email.com" value={email} onChange={(e) => setEmail(e.target.value)} aria-label="Adresse e-mail" />}
      <button className="btn btn-ghost btn-sm shrink-0" disabled={state === "busy"}>
        <Send className="size-3.5" /> {cta}
      </button>
      {state !== "idle" && state !== "busy" && <p className="text-xs text-down-400">{state}</p>}
    </form>
  );
}

// ---------------- pricing ----------------
export function PriceTag({ p, months = 1, big = true }: { p: Product; months?: number; big?: boolean }) {
  const { site } = useSession();
  const free = site?.billing.durations.find((d) => d.months === months)?.free_months ?? 0;
  const billed = p.period === "month" ? Math.max(1, months - free) : 1;
  const size = big ? "text-3xl" : "text-xl";
  const usd = (v: number) => (
    <span className="whitespace-nowrap">
      <span className="num">{new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 }).format(v)}</span>
      <span className="ml-1 font-sans">$</span>
    </span>
  );
  if (p.price_range_usd) {
    const [lo, hi] = p.price_range_usd;
    return (
      <div className="flex flex-wrap items-baseline gap-x-2">
        <span className={`${size} font-semibold`}>{usd(lo)} <span className="text-base font-normal text-muted">à</span> {usd(hi)}</span>
        {p.period === "month" && <span className="text-sm text-muted">/ mois</span>}
      </div>
    );
  }
  if (p.price_usd == null) return <span className={`${size} font-semibold`}>Sur devis</span>;
  return (
    <div>
      <div className="flex flex-wrap items-baseline gap-x-2">
        <span className={`${size} font-semibold`}>{usd(p.price_usd)}</span>
        <span className="whitespace-nowrap text-sm text-muted">{p.period === "month" ? "/ mois" : "paiement unique"}</span>
        {p.alt_price && <span className="whitespace-nowrap text-sm text-muted">{p.alt_price}</span>}
      </div>
      {p.price_xof != null && (
        <div className="num mt-1 text-xs text-faint">
          ≈ {fcfa(p.price_xof)}
          {p.period === "month" ? " / mois" : ""}
          {p.period === "month" && months > 1 && p.purchasable ? ` · ${fcfa(p.price_xof * billed)} pour ${months} mois` : ""}
        </div>
      )}
    </div>
  );
}

export function WhatsAppButton({ text, label = "Nous écrire sur WhatsApp", className = "btn btn-ghost" }: { text: string; label?: string; className?: string }) {
  const { site } = useSession();
  if (!site?.contact.whatsapp) return null;
  return (
    <a href={whatsappLink(site.contact.whatsapp, text)} target="_blank" rel="noopener noreferrer" className={className}>
      <MessageCircle className="size-4" /> {label}
    </a>
  );
}

function ProductCta({ p, months, owned }: { p: Product; months: number; owned: boolean }) {
  if (owned && p.period === "once") return <span className="btn btn-ghost w-full cursor-default">Déjà dans vos accès</span>;
  if (p.status === "contact") return <WhatsAppButton className="btn btn-ghost w-full" label="Candidater sur WhatsApp" text={`Bonjour Victor, je suis intéressé(e) par : ${p.label}.`} />;
  if (p.status === "soon")
    return <Waitlist interest={p.category === "licence" ? "licence" : p.category === "mentorat" ? "mentorat" : "formation"} cta="Être prévenu" />;
  return (
    <Link href={`/compte/?offre=${p.key}&mois=${p.period === "month" ? months : 0}`} className={`btn w-full ${p.featured ? "btn-primary" : "btn-ghost"}`}>
      {owned ? "Prolonger" : p.category === "formation" ? "Acheter la formation" : "Choisir cette offre"} <ArrowRight className="size-4" />
    </Link>
  );
}

export function ProductCard({ p, months = 1, i = 0 }: { p: Product; months?: number; i?: number }) {
  const { me } = useSession();
  const owned = !!me?.access?.some((a) => a.product === p.key);
  const gold = p.key === "formation_ict";
  return (
    <Reveal delay={i * 0.06} className="h-full">
      <div className={`card relative flex h-full flex-col p-6 ${p.featured ? "border-brand-400/50 shadow-[var(--shadow-glow)]" : ""} ${gold ? "border-gold-400/45 bg-gradient-to-b from-gold-500/[0.07] to-transparent" : ""}`}>
        {p.featured && <span className="chip chip-blue absolute -top-3 left-6 bg-ink-900">Le plus choisi</span>}
        {gold && <span className="chip chip-gold absolute -top-3 left-6 bg-ink-900">Programme officiel</span>}
        <div className="flex items-start justify-between gap-2">
          <h3 className="font-[family-name:var(--font-display)] text-lg font-bold">{p.label}</h3>
          {p.status !== "available" && <span className={`chip ${p.status === "soon" ? "chip-gold" : ""}`}>{p.status_label}</span>}
        </div>
        <p className="mt-1 text-sm text-muted">{p.summary}</p>
        <div className="mt-5">
          <PriceTag p={p} months={months} />
        </div>
        <ul className="mt-6 grid gap-2.5 text-sm">
          {p.highlights.map((h) => (
            <li key={h.text} className="flex gap-2.5">
              <CircleCheck className={`mt-0.5 size-4 shrink-0 ${h.soon ? "text-faint" : "text-up-400"}`} />
              <span className={h.soon ? "text-muted" : "text-fg/90"}>
                {h.text} {h.soon && <span className="chip ml-1 !px-1.5 !py-0 text-[10px]">bientôt</span>}
              </span>
            </li>
          ))}
        </ul>
        {p.audience.length > 0 && <p className="mt-4 text-xs text-faint">Pour : {p.audience.join(", ")}</p>}
        <div className="mt-auto grid gap-2 pt-7">
          <ProductCta p={p} months={months} owned={owned} />
          {p.page && (
            <Link href={p.page} className="text-center text-sm text-gold-300 hover:underline">
              Voir le programme complet
            </Link>
          )}
        </div>
      </div>
    </Reveal>
  );
}

function DurationToggle({ months, setMonths }: { months: number; setMonths: (m: number) => void }) {
  const { site } = useSession();
  if (!site) return null;
  return (
    <div className="mx-auto flex w-fit items-center gap-1 rounded-2xl border border-white/10 bg-ink-900 p-1" role="radiogroup" aria-label="Durée des abonnements">
      {site.billing.durations.map((d) => (
        <button key={d.months} role="radio" aria-checked={months === d.months} onClick={() => setMonths(d.months)} className={`relative rounded-xl px-4 py-2 text-sm font-semibold transition-colors ${months === d.months ? "text-white" : "text-muted hover:text-white"}`}>
          {months === d.months && <motion.span layoutId="dur" className="absolute inset-0 -z-0 rounded-xl bg-brand-500/25 ring-1 ring-brand-400/40" transition={{ type: "spring", stiffness: 400, damping: 34 }} />}
          <span className="relative">
            {d.months === 1 ? "1 mois" : d.months === 12 ? "12 mois" : `${d.months} mois`}
            {d.free_months > 0 && <span className="ml-1.5 text-up-300">−{d.free_months} mois</span>}
          </span>
        </button>
      ))}
    </div>
  );
}

/** Offers grouped by category. `only` restricts to some categories (the landing shows subscriptions). */
export function Pricing({ only }: { only?: Product["category"][] }) {
  const { site } = useSession();
  const [months, setMonths] = useState(1);
  if (!site) return <Spinner />;
  const cats = (Object.keys(site.categories) as Product["category"][]).filter((c) => !only || only.includes(c));
  return (
    <div className="grid gap-16">
      {cats.map((cat) => {
        const items = site.products.filter((p) => p.category === cat);
        if (!items.length) return null;
        return (
          <section key={cat} aria-labelledby={`cat-${cat}`}>
            {!only || only.length > 1 ? (
              <h3 id={`cat-${cat}`} className="mb-6 text-center font-[family-name:var(--font-display)] text-xl font-bold">
                {site.categories[cat]}
              </h3>
            ) : (
              <h3 id={`cat-${cat}`} className="sr-only">{site.categories[cat]}</h3>
            )}
            {cat === "abonnement" && (
              <div className="mb-8">
                <DurationToggle months={months} setMonths={setMonths} />
              </div>
            )}
            {cat === "licence" && (
              <p className="mx-auto mb-6 max-w-2xl text-center text-sm text-muted">
                Les licences seront ouvertes quand les performances des EA auront été vérifiées sur plusieurs mois de compte suivi.
              </p>
            )}
            <div className={`grid gap-5 ${items.length >= 3 ? "md:grid-cols-2 xl:grid-cols-3" : "mx-auto max-w-4xl md:grid-cols-2"}`}>
              {items.map((p, i) => (
                <ProductCard key={p.key} p={p} months={cat === "abonnement" ? months : 1} i={i} />
              ))}
            </div>
          </section>
        );
      })}
      <p className="text-center text-xs text-faint">
        Prix en dollars, payés en FCFA (≈ indiqué) avec Wave. L&apos;accès est activé à la confirmation du paiement ; les abonnements se prolongent, sans
        prélèvement automatique ; les formations sont acquises à vie.
      </p>
    </div>
  );
}

export function PaymentMethods() {
  const { site } = useSession();
  if (!site) return null;
  return (
    <div className="flex flex-wrap justify-center gap-2">
      {site.payment_methods.map((m) => (
        <span key={m.name} className={`chip ${m.status === "available" ? "chip-green" : ""}`}>
          {m.status === "available" ? <CircleCheck className="size-3" /> : <Clock className="size-3" />} {m.name}
          {m.status !== "available" && <span className="text-faint">· bientôt</span>}
        </span>
      ))}
    </div>
  );
}

// ---------------- misc ----------------
export function LockedBadge() {
  return (
    <span className="chip">
      <Lock className="size-3" /> Membres
    </span>
  );
}

export function SoonBadge() {
  return (
    <span className="chip chip-gold">
      <Clock className="size-3" /> En préparation
    </span>
  );
}
