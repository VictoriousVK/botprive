"use client";

import { motion, useReducedMotion, useScroll, useTransform } from "framer-motion";
import { ArrowRight, Bot, Copy, Smartphone } from "lucide-react";
import Link from "next/link";
import { useMemo, useRef } from "react";
import { Emblem, Initials, VFMark, Wordmark } from "./brand";

/** Decorative candlestick tape drifting behind the hero (not market data). */
function CandleTape() {
  const candles = useMemo(() => {
    let s = 7;
    const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
    let p = 100;
    return Array.from({ length: 64 }, (_, i) => {
      const o = p;
      const c = o + (rnd() - 0.47) * 7;
      const h = Math.max(o, c) + rnd() * 4;
      const l = Math.min(o, c) - rnd() * 4;
      p = c;
      return { i, o, c, h, l };
    });
  }, []);
  const lo = Math.min(...candles.map((k) => k.l));
  const hi = Math.max(...candles.map((k) => k.h));
  const y = (v: number) => 180 - ((v - lo) / (hi - lo)) * 160;
  const tape = (dx: number) =>
    candles.map((k) => {
      const x = dx + k.i * 18 + 9;
      const up = k.c >= k.o;
      return (
        <g key={`${dx}-${k.i}`} stroke={up ? "#4be08a" : "#ef5354"} fill={up ? "#4be08a" : "#ef5354"}>
          <line x1={x} x2={x} y1={y(k.h)} y2={y(k.l)} strokeWidth="1.2" />
          <rect x={x - 4.5} y={y(Math.max(k.o, k.c))} width="9" height={Math.max(1.5, Math.abs(y(k.o) - y(k.c)))} rx="1" />
        </g>
      );
    });
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-0 h-56 overflow-hidden opacity-[0.13] [mask-image:linear-gradient(transparent,#000_40%,#000_70%,transparent)]" aria-hidden>
      <svg viewBox="0 0 2304 200" preserveAspectRatio="xMinYMid slice" className="h-full w-[200%] animate-ticker [animation-duration:90s]">
        {tape(0)}
        {tape(1152)}
      </svg>
    </div>
  );
}

function FloatingChip({ children, className, delay }: { children: React.ReactNode; className: string; delay: number }) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      className={`absolute hidden items-center gap-2 rounded-2xl border border-white/10 bg-ink-800/80 px-3.5 py-2.5 text-xs font-semibold shadow-2xl backdrop-blur-md sm:flex ${className}`}
      initial={reduce ? false : { opacity: 0, y: 12, scale: 0.95 }}
      animate={reduce ? undefined : { opacity: 1, y: [0, -6, 0], scale: 1 }}
      transition={{ opacity: { delay, duration: 0.6 }, scale: { delay, duration: 0.6 }, y: { delay: delay + 0.6, duration: 5, repeat: Infinity, ease: "easeInOut" } }}
    >
      {children}
    </motion.div>
  );
}

export function Hero() {
  const ref = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });
  const emblemY = useTransform(scrollYProgress, [0, 1], [0, reduce ? 0 : 90]);
  const glow = useTransform(scrollYProgress, [0, 1], [1, 0.3]);

  return (
    <section ref={ref} className="relative isolate overflow-hidden">
      <div className="grid-bg absolute inset-0 -z-10" aria-hidden />
      <motion.div style={{ opacity: glow }} className="absolute -right-40 -top-40 -z-10 size-[42rem] rounded-full bg-brand-500/20 blur-[120px]" aria-hidden />
      <div className="absolute -bottom-40 -left-40 -z-10 size-[34rem] rounded-full bg-up-500/10 blur-[120px]" aria-hidden />
      <CandleTape />

      <div className="container-x grid items-center gap-8 pb-20 pt-8 lg:grid-cols-[1.02fr_1fr] lg:gap-6 lg:pb-28 lg:pt-14">
        {/* Emblem close-up: first on phones, on the right on large screens */}
        <motion.div style={{ y: emblemY }} className="relative order-first mx-auto flex w-full max-w-[30rem] flex-col items-center lg:order-last">
          <div className="relative aspect-square w-[min(78vw,26rem)] lg:w-[27rem]">
            <motion.div
              className="absolute inset-[-8%] rounded-full border border-brand-400/15"
              animate={reduce ? undefined : { rotate: 360 }}
              transition={{ duration: 60, repeat: Infinity, ease: "linear" }}
              aria-hidden
            >
              <span className="absolute left-1/2 top-0 size-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-brand-400 shadow-[0_0_14px_4px_rgb(79_176_255/0.6)]" />
            </motion.div>
            <motion.div
              className="absolute inset-[-18%] rounded-full border border-dashed border-white/[0.06]"
              animate={reduce ? undefined : { rotate: -360 }}
              transition={{ duration: 90, repeat: Infinity, ease: "linear" }}
              aria-hidden
            >
              <span className="absolute bottom-[14%] right-[6%] size-1.5 rounded-full bg-up-400 shadow-[0_0_12px_3px_rgb(75_224_138/0.6)]" />
            </motion.div>
            <div className="absolute inset-[12%] rounded-full bg-brand-500/25 blur-3xl" aria-hidden />
            <Emblem size="100%" animated className="relative drop-shadow-[0_20px_60px_rgba(42,143,234,0.35)]" />
            <FloatingChip className="-left-10 top-[16%]" delay={1.8}>
              <Bot className="size-4 text-brand-300" /> ICT Ultimate Pro v6.20 <span className="chip chip-blue !py-0">bêta</span>
            </FloatingChip>
            <FloatingChip className="-right-8 top-[52%]" delay={2.1}>
              <Copy className="size-4 text-up-300" /> Copytrading démo
            </FloatingChip>
            <FloatingChip className="bottom-[4%] left-[2%]" delay={2.4}>
              <Smartphone className="size-4 text-[#1dc8ff]" /> Paiement Wave
            </FloatingChip>
          </div>
          <motion.div initial={reduce ? false : { opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 1.2, duration: 0.8 }} className="mt-7">
            <Wordmark className="text-[2.1rem] sm:text-[2.6rem]" />
          </motion.div>
        </motion.div>

        <div className="relative text-center lg:text-left">
          <motion.div initial={reduce ? false : { opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }} className="inline-flex flex-wrap items-center justify-center gap-2">
            <span className="chip chip-green">
              <span className="size-1.5 rounded-full bg-up-400 animate-pulse-dot" /> Phase 0 · bêta privée
            </span>
            <span className="chip">MetaTrader 5 · FCFA</span>
          </motion.div>
          <motion.h1
            initial={reduce ? false : { opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.1, ease: [0.22, 1, 0.36, 1] }}
            className="h-display mt-5 text-[clamp(2.2rem,1.2rem+3.4vw,3.9rem)]"
          >
            La méthode des traders, <span className="text-gradient">au service de votre liberté financière.</span>
          </motion.h1>
          <motion.p initial={reduce ? false : { opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8, delay: 0.25 }} className="mx-auto mt-6 max-w-xl text-base leading-relaxed text-muted sm:text-lg lg:mx-0">
            Des robots de trading pour MetaTrader 5 issus de nos propres EA, une académie vidéo pour maîtriser la méthode ICT et le risque, et un copytrading
            où vous gardez la main sur chaque réglage. Paiement par Wave, en FCFA.
          </motion.p>
          <motion.div initial={reduce ? false : { opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.7, delay: 0.4 }} className="mt-8 flex flex-col items-center gap-3 sm:flex-row sm:justify-center lg:justify-start">
            <Link href="/compte/?vue=inscription" className="btn btn-primary w-full sm:w-auto">
              Créer mon compte gratuit <ArrowRight className="size-4" />
            </Link>
            <Link href="/robots/" className="btn btn-ghost w-full sm:w-auto">
              Découvrir les robots
            </Link>
          </motion.div>
          <motion.div initial={reduce ? false : { opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.7, duration: 0.8 }} className="mt-10 flex items-center justify-center gap-3 lg:justify-start">
            <div className="flex -space-x-2">
              <Initials text="KD" className="size-10 text-xs ring-4 ring-ink-950" />
              <span className="grid size-10 place-items-center rounded-2xl border border-gold-500/40 bg-ink-900 ring-4 ring-ink-950">
                <VFMark size={24} />
              </span>
            </div>
            <p className="text-left text-sm leading-snug text-muted">
              Fondé par <span className="font-semibold text-fg">Khalifa Diop</span>, trader expert,
              <br className="hidden sm:block" /> et <span className="font-semibold text-fg">Victor Faye</span>, trader et data scientist.
            </p>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
