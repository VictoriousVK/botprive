"use client";

import { motion } from "framer-motion";
import { ArrowRight, Bot, CircleCheck, Clock, Cpu, Lock, Send, Sparkles } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { api, fcfa, type Offer, type Robot } from "@/lib/api";
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

export function Waitlist({ interest, cta = "M'inscrire" }: { interest: "copytrading" | "next_bot" | "academie" | "newsletter"; cta?: string }) {
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
export function Pricing({ compact = false }: { compact?: boolean }) {
  const { site, me } = useSession();
  const [months, setMonths] = useState(1);
  if (!site) return <Spinner />;
  const durations = site.billing.durations;
  const free = (m: number) => durations.find((d) => d.months === m)?.free_months ?? 0;
  return (
    <div>
      <div className="mx-auto flex w-fit items-center gap-1 rounded-2xl border border-white/10 bg-ink-900 p-1" role="radiogroup" aria-label="Durée">
        {durations.map((d) => (
          <button key={d.months} role="radio" aria-checked={months === d.months} onClick={() => setMonths(d.months)} className={`relative rounded-xl px-4 py-2 text-sm font-semibold transition-colors ${months === d.months ? "text-white" : "text-muted hover:text-white"}`}>
            {months === d.months && <motion.span layoutId="dur" className="absolute inset-0 -z-0 rounded-xl bg-brand-500/25 ring-1 ring-brand-400/40" transition={{ type: "spring", stiffness: 400, damping: 34 }} />}
            <span className="relative">
              {d.months === 1 ? "Mensuel" : d.months === 12 ? "Annuel" : `${d.months} mois`}
              {d.free_months > 0 && <span className="ml-1.5 text-up-300">−{d.free_months} mois</span>}
            </span>
          </button>
        ))}
      </div>
      <div className={`mt-8 grid gap-5 ${compact ? "md:grid-cols-2 xl:grid-cols-4" : "md:grid-cols-2 xl:grid-cols-4"}`}>
        {site.offers.map((o, i) => (
          <OfferCard key={o.key} o={o} months={months} billed={Math.max(1, months - free(months))} current={me?.offer === o.key} i={i} />
        ))}
      </div>
      <p className="mt-6 text-center text-xs text-faint">
        Prix en FCFA, taxes éventuelles non comprises. Paiement par Wave ; l&apos;accès est prolongé de la durée choisie, sans prélèvement automatique.
      </p>
    </div>
  );
}

function OfferCard({ o, months, billed, current, i }: { o: Offer; months: number; billed: number; current: boolean; i: number }) {
  const freeOffer = o.price_xof === 0;
  const href = freeOffer ? "/compte/?vue=inscription" : `/compte/?offre=${o.key}&mois=${months}`;
  return (
    <Reveal delay={i * 0.06} className="h-full">
      <div className={`card relative flex h-full flex-col p-6 ${o.featured ? "border-brand-400/50 shadow-[var(--shadow-glow)]" : ""}`}>
        {o.featured && <span className="chip chip-blue absolute -top-3 left-6 bg-ink-900">Le plus choisi</span>}
        <h3 className="font-[family-name:var(--font-display)] text-lg font-bold">{o.label}</h3>
        <p className="mt-1 text-sm text-muted">{o.summary}</p>
        <div className="mt-5">
          {freeOffer ? (
            <span className="num text-3xl font-semibold">Gratuit</span>
          ) : (
            <>
              <span className="num text-3xl font-semibold">{new Intl.NumberFormat("fr-FR").format(o.price_xof)}</span>
              <span className="ml-1 text-sm text-muted">FCFA / mois</span>
              {months > 1 && <div className="num mt-1 text-xs text-faint">{fcfa(o.price_xof * billed)} pour {months} mois</div>}
            </>
          )}
        </div>
        <ul className="mt-6 grid gap-2.5 text-sm">
          {o.highlights.map((h) => (
            <li key={h} className="flex gap-2.5">
              <CircleCheck className="mt-0.5 size-4 shrink-0 text-up-400" /> <span className="text-fg/90">{h}</span>
            </li>
          ))}
        </ul>
        <div className="mt-auto pt-7">
          {current ? (
            <span className="btn btn-ghost w-full cursor-default">Votre offre actuelle</span>
          ) : (
            <Link href={href} className={`btn w-full ${o.featured ? "btn-primary" : "btn-ghost"}`}>
              {freeOffer ? "Créer mon compte" : "Choisir cette offre"} <ArrowRight className="size-4" />
            </Link>
          )}
        </div>
      </div>
    </Reveal>
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
