"use client";

import { motion, useReducedMotion } from "framer-motion";
import { ArrowRight, Brain, ChartLine, CircleCheck, Crown, Download, Infinity as InfinityIcon, Quote, Target, Users } from "lucide-react";
import Link from "next/link";
import { VFMark } from "@/components/brand";
import { PriceTag, WhatsAppButton } from "@/components/products";
import { Notice, Reveal } from "@/components/ui";
import { BONUSES, MODULES, PILLARS, QUOTES } from "@/content/victorious-trader";
import { useSession } from "@/lib/session";

const ICONS = { target: Target, chart: ChartLine, brain: Brain, infinity: InfinityIcon } as const;

function BuyButtons({ center = false }: { center?: boolean }) {
  const { site, me } = useSession();
  const owned = !!me?.access?.some((a) => a.product === "formation_ict") || !!me?.entitlements.includes("formation_ict");
  const product = site?.products.find((p) => p.key === "formation_ict");
  return (
    <div className={`flex flex-col gap-3 sm:flex-row ${center ? "sm:justify-center" : ""}`}>
      {owned ? (
        <Link href="/academie/cours/?c=victorious-trader" className="btn btn-gold">
          Accéder à ma formation <ArrowRight className="size-4" />
        </Link>
      ) : product?.purchasable ? (
        <Link href="/compte/?offre=formation_ict&mois=0" className="btn btn-gold">
          Rejoindre V_ICT <ArrowRight className="size-4" />
        </Link>
      ) : null}
      <WhatsAppButton text="Bonjour Victor, j'ai une question sur la formation Victorious Trader." label="Poser une question" />
    </div>
  );
}

export function FormationView() {
  const { site } = useSession();
  const reduce = useReducedMotion();
  const product = site?.products.find((p) => p.key === "formation_ict");
  return (
    <div className="relative">
      {/* ---------- hero ---------- */}
      <section className="relative isolate overflow-hidden border-b border-gold-400/15">
        <div className="grid-bg absolute inset-0 -z-10 opacity-60" aria-hidden />
        <div className="absolute -left-40 -top-40 -z-10 size-[40rem] rounded-full bg-gold-500/15 blur-[130px]" aria-hidden />
        <div className="absolute -bottom-52 right-0 -z-10 size-[34rem] rounded-full bg-brand-500/10 blur-[130px]" aria-hidden />
        <div className="container-x grid items-center gap-12 py-14 lg:grid-cols-[1.15fr_0.85fr] lg:py-20">
          <div>
            <motion.div initial={reduce ? false : { opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="flex flex-wrap items-center gap-2">
              <span className="chip chip-gold"><Crown className="size-3" /> Programme officiel</span>
              <span className="chip">Formation ICT · 16 modules</span>
            </motion.div>
            <motion.h1
              initial={reduce ? false : { opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.1, ease: [0.22, 1, 0.36, 1] }}
              className="h-display text-gold mt-6 text-[clamp(2.6rem,1.4rem+5vw,5.2rem)] uppercase"
            >
              Victorious Trader
            </motion.h1>
            <motion.div initial={reduce ? false : { opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.35 }} className="mt-4 flex items-center gap-3">
              <span className="grid size-11 place-items-center rounded-xl border border-gold-500/40 bg-ink-900"><VFMark size={26} /></span>
              <div>
                <div className="font-[family-name:var(--font-display)] text-lg font-bold">par Victor Faye</div>
                <div className="text-xs uppercase tracking-[0.18em] text-gold-300">Trader · Data scientist</div>
              </div>
            </motion.div>
            <p className="mt-6 max-w-xl text-base leading-relaxed text-muted sm:text-lg">
              Le programme complet pour maîtriser la méthode ICT : IPDA, AMD, cycles de 90 minutes, Silver Bullet, modèles de market maker, SMT, gaps
              d&apos;ouverture… appliqués sur des cas réels du NAS100, de l&apos;or (XAUUSD) et de l&apos;EUR/USD.
            </p>
            <div className="card-gold mt-8 flex flex-col gap-5 p-5 sm:flex-row sm:items-center sm:justify-between">
              {product ? <PriceTag p={product} /> : <span className="num text-3xl font-semibold">899 $</span>}
              <BuyButtons />
            </div>
            <p className="mt-4 text-xs text-faint">Paiement unique avec Wave · accès à vie · groupe d&apos;élite inclus</p>
          </div>
          <Reveal className="mx-auto w-full max-w-sm">
            <figure className="relative">
              <div className="absolute -inset-4 -z-10 rounded-[2rem] bg-gold-500/20 blur-2xl" aria-hidden />
              <img
                src="/brand/victorious-trader-programme.jpg"
                alt="Affiche du programme officiel Victorious Trader, formation ICT par Victor Faye : les 16 modules et les avantages inclus."
                width={1024}
                height={1536}
                className="w-full rounded-2xl border border-gold-400/30 shadow-2xl"
              />
              <figcaption className="mt-3 text-center">
                <a href="/brand/victorious-trader-programme.jpg" download className="inline-flex items-center gap-2 text-sm text-gold-300 hover:underline">
                  <Download className="size-4" /> Télécharger l&apos;affiche du programme
                </a>
              </figcaption>
            </figure>
          </Reveal>
        </div>
      </section>

      {/* ---------- pillars ---------- */}
      <section className="container-x py-14">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {PILLARS.map((p, i) => {
            const Icon = ICONS[p.icon];
            return (
              <Reveal key={p.title} delay={i * 0.06}>
                <div className="card-gold flex h-full items-center gap-4 p-5">
                  <span className="grid size-11 shrink-0 place-items-center rounded-xl border border-gold-400/35 text-gold-300"><Icon className="size-5" /></span>
                  <span className="text-sm font-semibold leading-snug">{p.title}</span>
                </div>
              </Reveal>
            );
          })}
        </div>
        <p className="mt-8 text-center text-xs font-semibold uppercase tracking-[0.35em] text-gold-300/80">Analyser · Apprendre · Trader · Réussir</p>
      </section>

      {/* ---------- programme ---------- */}
      <section id="programme" className="container-x scroll-mt-24 pb-16">
        <Reveal className="text-center">
          <p className="eyebrow !text-gold-300">Le programme de la formation</p>
          <h2 className="h-section mt-3">16 modules, de l&apos;IPDA au Friday Model</h2>
        </Reveal>
        <div className="mt-10 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {MODULES.map((m, i) => (
            <Reveal key={m.n} delay={(i % 4) * 0.05} className="h-full">
              <article className="card card-hover h-full p-5">
                <div className="flex items-start gap-4">
                  <span className="num grid size-11 shrink-0 place-items-center rounded-xl bg-gradient-to-b from-[#f0d48f] to-[#a8812f] text-base font-bold text-[#1a1205]">
                    {String(m.n).padStart(2, "0")}
                  </span>
                  <div className="min-w-0">
                    <h3 className="font-semibold leading-snug">
                      <span className="text-gold-300">Module {m.n} :</span> {m.title}
                    </h3>
                    {m.subtitle && <p className="text-xs text-muted">{m.subtitle}</p>}
                  </div>
                </div>
                <ul className="mt-4 grid gap-2 text-sm">
                  {m.points.map((pt) => (
                    <li key={pt} className="flex gap-2.5 text-fg/85">
                      <CircleCheck className="mt-0.5 size-4 shrink-0 text-gold-400" /> {pt}
                    </li>
                  ))}
                </ul>
              </article>
            </Reveal>
          ))}
        </div>
      </section>

      {/* ---------- bonuses + elite group ---------- */}
      <section className="container-x grid gap-5 pb-16 lg:grid-cols-[1.2fr_0.8fr]">
        <Reveal>
          <div className="card-gold h-full p-7">
            <p className="eyebrow !text-gold-300">En plus</p>
            <ul className="mt-5 grid gap-3 sm:grid-cols-2">
              {BONUSES.map((b) => (
                <li key={b} className="flex items-center gap-3 text-sm font-medium">
                  <CircleCheck className="size-5 shrink-0 text-gold-400" /> {b}
                </li>
              ))}
            </ul>
          </div>
        </Reveal>
        <Reveal delay={0.08}>
          <div className="card-gold h-full p-7">
            <div className="flex items-center gap-3">
              <Users className="size-7 text-gold-300" />
              <h3 className="font-[family-name:var(--font-display)] text-lg font-bold">Accès à vie au groupe de traders d&apos;élite</h3>
            </div>
            <p className="mt-3 text-sm leading-relaxed text-muted">Échange, analyse, opportunités, entraide : une communauté active, engagée et ambitieuse, sur Telegram et Discord.</p>
          </div>
        </Reveal>
      </section>

      {/* ---------- honesty + final call ---------- */}
      <section className="container-x">
        <Notice className="mb-10">
          Les modules sont publiés en vidéo au fil des tournages ; votre accès, acquis à vie, comprend chaque module dès sa sortie. La formation transmet une
          méthode : elle ne garantit aucun résultat, et le trading comporte un risque de perte en capital.
        </Notice>
        <Reveal>
          <div className="relative overflow-hidden rounded-3xl border border-gold-400/30 bg-gradient-to-br from-gold-500/15 via-ink-800 to-ink-900 px-6 py-14 text-center sm:px-12">
            <Quote className="mx-auto size-8 text-gold-400" aria-hidden />
            <p className="mx-auto mt-4 max-w-2xl font-[family-name:var(--font-display)] text-2xl font-bold italic sm:text-3xl">{QUOTES[1]}</p>
            <p className="mt-2 text-sm text-gold-300">Victor Faye</p>
            <h2 className="text-gold mt-10 font-[family-name:var(--font-display)] text-3xl font-extrabold uppercase sm:text-4xl">Rejoins V_ICT</h2>
            <p className="mt-2 text-muted">et passe au niveau supérieur</p>
            <div className="mt-8">
              <BuyButtons center />
            </div>
            <p className="mt-10 text-xs font-semibold uppercase tracking-[0.35em] text-faint">Discipline / Stratégie / Liberté financière</p>
          </div>
        </Reveal>
      </section>
    </div>
  );
}
