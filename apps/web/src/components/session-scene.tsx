"use client";

// The sign-up scene: a 24-hour New York dial with the ICT killzones and a needle at the real
// time, a candle tape drawing itself (an illustration, never data), and what the space does.

import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useMemo, useState } from "react";

// Same hours as the engine (hedgefund/saas/ingest.py KILLZONES), in New York minutes.
export const KILLZONES: [string, string, number, number, string][] = [
  ["Asia", "Asie", 1200, 1440, "#8fcbff"],
  ["London", "Londres", 120, 300, "#4fb0ff"],
  ["NY_AM", "New York AM", 420, 600, "#4be08a"],
  ["NY_Lunch", "Pause de midi", 720, 810, "#5d6a7e"],
  ["NY_PM", "New York PM", 810, 960, "#d4b374"],
];

function nyMinute(d: Date): number {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(d);
  const h = Number(parts.find((p) => p.type === "hour")?.value ?? 0);
  const m = Number(parts.find((p) => p.type === "minute")?.value ?? 0);
  return h * 60 + m;
}

export function useNyClock() {
  const [now, setNow] = useState<Date | null>(null);
  useEffect(() => {
    setNow(new Date());
    const t = window.setInterval(() => setNow(new Date()), 20_000);
    return () => window.clearInterval(t);
  }, []);
  if (!now) return null;
  const minute = nyMinute(now);
  const current = KILLZONES.find(([, , s, e]) => minute >= s && minute < e) ?? null;
  const upcoming = KILLZONES.map((k) => ({ k, wait: (k[2] - minute + 1440) % 1440 })).filter((x) => x.wait > 0).sort((a, b) => a.wait - b.wait)[0];
  return { minute, current, next: upcoming?.k ?? null, wait: upcoming?.wait ?? 0 };
}

const hhmm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const inH = (m: number) => (m >= 60 ? `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")}` : `${m} min`);

/** 24-hour dial: killzone arcs, a needle on New York time. */
export function KillzoneDial({ size = 220 }: { size?: number }) {
  const clock = useNyClock();
  const reduce = useReducedMotion();
  const r = size / 2 - 16;
  const c = size / 2;
  const pt = (minute: number, rad: number) => {
    const a = (minute / 1440) * Math.PI * 2 - Math.PI / 2;
    return [c + rad * Math.cos(a), c + rad * Math.sin(a)];
  };
  const arc = (s: number, e: number, rad: number) => {
    const [x1, y1] = pt(s, rad);
    const [x2, y2] = pt(e, rad);
    return `M${x1} ${y1} A${rad} ${rad} 0 ${e - s > 720 ? 1 : 0} 1 ${x2} ${y2}`;
  };
  const angle = clock ? (clock.minute / 1440) * 360 : 0;
  return (
    <div className="flex items-center gap-5">
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="shrink-0" role="img" aria-label={clock ? `Heure de New York ${hhmm(clock.minute)}` : "Horloge de New York"}>
        <circle cx={c} cy={c} r={r} fill="none" stroke="rgb(148 163 184 / .12)" strokeWidth="10" />
        {KILLZONES.map(([k, , s, e, col], i) => (
          <motion.path key={k} d={arc(s, e, r)} fill="none" stroke={col} strokeWidth={clock?.current?.[0] === k ? 12 : 8} strokeLinecap="round"
            initial={reduce ? false : { pathLength: 0, opacity: 0 }} animate={{ pathLength: 1, opacity: clock?.current?.[0] === k ? 1 : 0.55 }}
            transition={{ duration: 1.1, delay: 0.25 + i * 0.12, ease: [0.22, 1, 0.36, 1] }} />
        ))}
        {size >= 150 && [0, 6, 12, 18].map((h) => {
          const [x, y] = pt(h * 60, r - 24);
          return <text key={h} x={x} y={y + 3.5} fontSize="10" textAnchor="middle" fill="#5d6a7e" className="num">{String(h).padStart(2, "0")}</text>;
        })}
        {/* The transparent disc centred on the dial makes the group's box symmetric: it turns on the centre. */}
        <motion.g initial={reduce ? false : { rotate: angle - 90 }} animate={{ rotate: angle }} transition={{ type: "spring", stiffness: 40, damping: 14, delay: 0.4 }}>
          <circle cx={c} cy={c} r={r - 8} fill="transparent" />
          <line x1={c} y1={c} x2={c} y2={c - r + 14} stroke="#e9eef6" strokeWidth="2" strokeLinecap="round" />
          <circle cx={c} cy={c - r + 14} r="3.5" fill="#e9eef6" />
        </motion.g>
        <circle cx={c} cy={c} r="5" fill="#03050a" stroke="#e9eef6" strokeWidth="2" />
      </svg>
      <div className="min-w-0" aria-live="polite">
        <div className="eyebrow">New York · {clock ? hhmm(clock.minute) : "--:--"}</div>
        <div className="mt-2 font-[family-name:var(--font-display)] text-2xl font-bold leading-tight">
          {clock?.current ? <>Killzone <span style={{ color: clock.current[4] }}>{clock.current[1]}</span></> : "Hors killzone"}
        </div>
        {clock?.next && <p className="mt-1 text-sm text-muted">{clock.next[1]} dans {inH(clock.wait)}</p>}
      </div>
    </div>
  );
}

function tape(n: number, seed = 7) {
  let s = seed;
  const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  let p = 100;
  return Array.from({ length: n }, (_, i) => {
    const drift = i > n * 0.55 && i < n * 0.62 ? 2.4 : (rnd() - 0.48) * 1.6;
    const o = p;
    const cl = o + drift;
    const h = Math.max(o, cl) + rnd() * 0.9;
    const l = Math.min(o, cl) - rnd() * 0.9;
    p = cl;
    return { o, h, l, c: cl };
  });
}

/** Decorative candles that draw themselves, with a fair value gap and a scan line. */
export function CandleTape({ height = 150 }: { height?: number }) {
  const reduce = useReducedMotion();
  const bars = useMemo(() => tape(42), []);
  const W = 520;
  const lo = Math.min(...bars.map((b) => b.l));
  const hi = Math.max(...bars.map((b) => b.h));
  const y = (v: number) => height - 8 - ((v - lo) / (hi - lo)) * (height - 16);
  const step = W / bars.length;
  const g = bars.findIndex((_, i) => i > bars.length * 0.55) + 1;
  const gap = bars[g - 1] && bars[g + 1] && bars[g + 1].l > bars[g - 1].h ? { top: bars[g + 1].l, bottom: bars[g - 1].h } : null;
  return (
    <div className="relative" aria-hidden>
      <svg viewBox={`0 0 ${W} ${height}`} className="block h-auto w-full">
        {gap && (
          <motion.rect x={(g - 1) * step} width={W - (g - 1) * step} y={y(gap.top)} height={Math.max(2, y(gap.bottom) - y(gap.top))} fill="rgb(75 224 138 / .10)"
            initial={reduce ? false : { opacity: 0, scaleX: 0 }} animate={{ opacity: 1, scaleX: 1 }} style={{ originX: 0 }} transition={{ delay: 1.6, duration: 0.8 }} />
        )}
        {bars.map((b, i) => {
          const up = b.c >= b.o;
          const col = up ? "#4be08a" : "#ef5354";
          const x = i * step + step / 2;
          return (
            <motion.g key={i} initial={reduce ? false : { opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 + i * 0.03, duration: 0.35 }}>
              <line x1={x} x2={x} y1={y(b.h)} y2={y(b.l)} stroke={col} strokeWidth="1" />
              <rect x={x - step * 0.3} width={step * 0.6} y={y(Math.max(b.o, b.c))} height={Math.max(1.5, Math.abs(y(b.o) - y(b.c)))} fill={col} rx="0.5" />
            </motion.g>
          );
        })}
        {!reduce && (
          <motion.line x1={0} x2={0} y1={0} y2={height} stroke="rgb(143 203 255 / .55)" strokeWidth="1.5"
            animate={{ x1: [0, W], x2: [0, W], opacity: [0, 1, 1, 0] }} transition={{ duration: 6, repeat: Infinity, ease: "linear", delay: 2.2 }} />
        )}
      </svg>
      <span className="absolute bottom-1 right-2 text-[10px] uppercase tracking-widest text-faint">Illustration</span>
    </div>
  );
}

const LINES = [
  ["Journal", "votre historique MT5 ou futures, importé et classé par killzone"],
  ["Coach IA", "vos écarts au plan, mesurés sur vos trades, et des leçons que vous validez"],
  ["Garde-fou", "vos limites Topstep, Tradeify, FundingPips ou FTMO, suivies en continu"],
] as const;

export function ValueLines() {
  const reduce = useReducedMotion();
  return (
    <ul className="grid gap-3">
      {LINES.map(([k, v], i) => (
        <motion.li key={k} className="flex gap-3 text-sm leading-relaxed" initial={reduce ? false : { opacity: 0, x: -12 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.9 + i * 0.25, duration: 0.5 }}>
          <span className="num mt-0.5 text-brand-300">›</span>
          <span><span className="font-semibold text-fg">{k}</span> <span className="text-muted">{v}</span></span>
        </motion.li>
      ))}
    </ul>
  );
}
