"use client";

import { motion, useReducedMotion } from "framer-motion";
import { useId } from "react";

/* Vector redraws of the two logos supplied by the founders (the originals were small
   screenshots). Replace the paths by the designer's source files when available. */

const BIRD_WING = "M102 66 C98 50 88 38 70 28 C72 34 72 38 70 41 C64 36 58 33 50 32 C54 38 56 42 56 46 C50 43 44 42 38 43 C44 48 48 52 50 56 C45 56 40 57 35 59 C50 72 64 81 82 86 Z";
const BIRD_BODY = "M140 66 L128 60 C125 52 111 51 106 59 C98 70 84 84 64 94 L38 103 L57 106 L43 119 C70 117 96 107 112 91 C120 83 125 75 128 71 Z";
const ARROW = "M40 148 L62 124 L80 138 L118 100 L132 112 L158 76";
const BARS = [
  { x: 92, y: 150 },
  { x: 111, y: 136 },
  { x: 130, y: 120 },
  { x: 149, y: 102 },
];

type EmblemProps = { size?: number | string; animated?: boolean; className?: string; bg?: string; title?: string };

/** Liberté Financière emblem: ring, dove, rising arrow, bar chart. */
export function Emblem({ size = 48, animated = false, className, bg = "#03050a", title = "Liberté Financière" }: EmblemProps) {
  const id = useId().replace(/:/g, "");
  const reduce = useReducedMotion();
  const play = animated && !reduce;
  const t = (d: number) => ({ duration: 1, delay: d, ease: [0.22, 1, 0.36, 1] as const });
  return (
    <svg viewBox="0 0 200 200" width={size} height={size} className={className} role="img" aria-label={title}>
      <defs>
        <linearGradient id={`r${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#6cc0ff" />
          <stop offset="1" stopColor="#1668c9" />
        </linearGradient>
        <linearGradient id={`b${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#6cc0ff" />
          <stop offset="1" stopColor="#1f7fe0" />
        </linearGradient>
        <linearGradient id={`c${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3a9bff" />
          <stop offset="1" stopColor="#0f4c99" />
        </linearGradient>
        <linearGradient id={`u${id}`} x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stopColor="#1fae5b" />
          <stop offset="1" stopColor="#5ef09a" />
        </linearGradient>
        <clipPath id={`k${id}`}>
          <circle cx="100" cy="100" r="85" />
        </clipPath>
      </defs>
      <motion.circle
        cx="100" cy="100" r="90" fill="none" stroke={`url(#r${id})`} strokeWidth="7" strokeLinecap="round"
        initial={play ? { pathLength: 0, rotate: -90 } : false} animate={{ pathLength: 1, rotate: -90 }} transition={t(0)}
        style={{ transformOrigin: "100px 100px" }}
      />
      <g clipPath={`url(#k${id})`} fill={`url(#c${id})`}>
        {BARS.map((b, i) => (
          <motion.rect
            key={b.x} x={b.x} y={b.y} width="13" height={200 - b.y} rx="2"
            initial={play ? { scaleY: 0 } : false} animate={{ scaleY: 1 }} transition={t(0.35 + i * 0.1)}
            style={{ transformOrigin: `${b.x}px 200px` }}
          />
        ))}
      </g>
      <motion.g
        fill={`url(#b${id})`} stroke={bg} strokeWidth="4" paintOrder="stroke" strokeLinejoin="round"
        initial={play ? { opacity: 0, x: -26, y: 18, rotate: -8 } : false} animate={{ opacity: 1, x: 0, y: 0, rotate: 0 }} transition={t(0.55)}
        style={{ transformOrigin: "90px 80px" }}
      >
        <motion.path d={BIRD_WING} animate={play ? { rotate: [0, -5, 0] } : undefined} transition={{ duration: 3.2, repeat: Infinity, ease: "easeInOut", delay: 1.6 }} style={{ transformOrigin: "95px 78px" }} />
        <path d={BIRD_BODY} />
      </motion.g>
      <g fill="none" strokeLinecap="round" strokeLinejoin="round">
        <motion.path d={ARROW} stroke={bg} strokeWidth="15" initial={play ? { pathLength: 0 } : false} animate={{ pathLength: 1 }} transition={t(0.8)} />
        <motion.path d={ARROW} stroke={`url(#u${id})`} strokeWidth="8" initial={play ? { pathLength: 0 } : false} animate={{ pathLength: 1 }} transition={t(0.8)} />
      </g>
      <motion.path
        d="M170 58 L150 66 L167 81 Z" fill="#5ef09a" stroke="#5ef09a" strokeWidth="3" strokeLinejoin="round"
        initial={play ? { opacity: 0, scale: 0.4 } : false} animate={{ opacity: 1, scale: 1 }} transition={t(1.55)}
        style={{ transformOrigin: "160px 68px" }}
      />
    </svg>
  );
}

/** Victor Faye monogram (VF), light version for dark backgrounds, with the gold accent. */
export function VFMark({ size = 28, className, title = "Victor Faye" }: { size?: number; className?: string; title?: string }) {
  return (
    <svg viewBox="0 0 120 92" width={size} height={(size * 92) / 120} className={className} role="img" aria-label={title}>
      <g fill="#f4f1ea">
        <path d="M2 6 L27 6 L49 58 L71 6 L118 6 L111 20 L80 20 L51 86 L41 86 Z" />
        <path d="M74 32 L104 32 L98 45 L68 45 Z" />
      </g>
      <g fill="#c9a45c">
        <path d="M29.5 6 L33 6 L50.6 47.5 L48.8 51.8 Z" />
        <path d="M80.2 22.5 L110 22.5 L108.8 25 L79.1 25 Z" />
        <path d="M67.4 47.5 L97.2 47.5 L96 50 L66.3 50 Z" />
      </g>
    </svg>
  );
}

/** Wordmark "LIBERTÉ / FINANCIÈRE", as in the original logo. */
export function Wordmark({ className = "", compact = false }: { className?: string; compact?: boolean }) {
  return (
    <span className={`inline-flex flex-col leading-none font-[family-name:var(--font-display)] ${className}`}>
      <span className={`font-extrabold tracking-[0.08em] text-white ${compact ? "text-[15px]" : "text-[1.35em]"}`}>LIBERTÉ</span>
      <span className={`font-semibold tracking-[0.155em] text-white/85 ${compact ? "mt-[3px] text-[9.5px]" : "mt-[0.28em] text-[0.62em]"}`}>FINANCIÈRE</span>
    </span>
  );
}

/** Co-branded lockup: Liberté Financière first, the founder's VF monogram in miniature. */
export function Lockup({ withFounder = true }: { withFounder?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <Emblem size={38} />
      <Wordmark compact />
      {withFounder && (
        <span className="ml-0.5 inline-flex items-center border-l border-white/10 pl-2.5 sm:ml-1 sm:pl-3" title="Cofondé par Victor Faye">
          <VFMark size={18} />
        </span>
      )}
    </span>
  );
}

/** Founder initials badge (used where no personal logo exists). */
export function Initials({ text, className = "" }: { text: string; className?: string }) {
  return (
    <span className={`inline-flex items-center justify-center rounded-2xl border border-gold-500/40 bg-gradient-to-br from-ink-700 to-ink-900 font-[family-name:var(--font-display)] font-extrabold tracking-wider text-gold-300 ${className}`}>
      {text}
    </span>
  );
}
