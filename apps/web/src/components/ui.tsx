"use client";

import { motion, useReducedMotion } from "framer-motion";
import { LoaderCircle, TriangleAlert, Info, CircleCheck } from "lucide-react";
import { useId, type ReactNode } from "react";
import type { CurvePoint } from "@/lib/api";

export function Reveal({ children, delay = 0, className = "", y = 18 }: { children: ReactNode; delay?: number; className?: string; y?: number }) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      className={className}
      initial={reduce ? false : { opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-60px" }}
      transition={{ duration: 0.6, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  );
}

export function SectionHead({ eyebrow, title, children, center = false }: { eyebrow: string; title: ReactNode; children?: ReactNode; center?: boolean }) {
  return (
    <Reveal className={`max-w-3xl ${center ? "mx-auto text-center" : ""}`}>
      <p className="eyebrow">{eyebrow}</p>
      <h2 className="h-section mt-3">{title}</h2>
      {children && <div className="mt-4 text-base leading-relaxed text-muted sm:text-lg">{children}</div>}
    </Reveal>
  );
}

export function Spinner({ label = "Chargement…" }: { label?: string }) {
  return (
    <span className="inline-flex items-center gap-2 text-sm text-muted" role="status">
      <LoaderCircle className="size-4 animate-spin" aria-hidden /> {label}
    </span>
  );
}

export function Notice({ kind = "info", children, className = "" }: { kind?: "info" | "warn" | "error" | "ok"; children: ReactNode; className?: string }) {
  const map = {
    info: ["border-brand-400/30 bg-brand-400/5 text-brand-300", Info],
    warn: ["border-gold-400/35 bg-gold-400/5 text-gold-300", TriangleAlert],
    error: ["border-down-500/40 bg-down-500/5 text-down-400", TriangleAlert],
    ok: ["border-up-400/35 bg-up-400/5 text-up-300", CircleCheck],
  } as const;
  const [cls, Icon] = map[kind];
  return (
    <div className={`flex gap-3 rounded-xl border px-4 py-3 text-sm leading-relaxed ${cls} ${className}`} role={kind === "error" ? "alert" : undefined}>
      <Icon className="mt-0.5 size-4 shrink-0" aria-hidden />
      <div className="min-w-0 text-fg/90">{children}</div>
    </div>
  );
}

/** Area chart for a series of points (percent or value). Pure SVG, scales to its container. */
export function AreaChart({ points, height = 140, baseline = 0, className = "", label }: { points: CurvePoint[]; height?: number; baseline?: number | null; className?: string; label: string }) {
  const id = useId().replace(/:/g, "");
  if (points.length < 2) {
    return (
      <div className={`grid place-items-center rounded-xl border border-dashed border-white/10 text-sm text-faint ${className}`} style={{ height }}>
        Historique en cours de constitution
      </div>
    );
  }
  const W = 600;
  const vs = points.map((p) => p.v);
  let lo = Math.min(...vs, baseline ?? Infinity);
  let hi = Math.max(...vs, baseline ?? -Infinity);
  if (hi - lo < 1e-9) {
    hi += 1;
    lo -= 1;
  }
  const pad = (hi - lo) * 0.12;
  lo -= pad;
  hi += pad;
  const t0 = points[0].t;
  const t1 = points[points.length - 1].t || t0 + 1;
  const x = (t: number) => ((t - t0) / (t1 - t0 || 1)) * W;
  const y = (v: number) => height - ((v - lo) / (hi - lo)) * height;
  const line = points.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)} ${y(p.v).toFixed(1)}`).join(" ");
  const up = vs[vs.length - 1] >= (baseline ?? vs[0]);
  const color = up ? "#4be08a" : "#ef5354";
  return (
    <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" className={`block w-full ${className}`} style={{ height }} role="img" aria-label={label}>
      <defs>
        <linearGradient id={`g${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color} stopOpacity="0.28" />
          <stop offset="1" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      {baseline != null && <line x1="0" x2={W} y1={y(baseline)} y2={y(baseline)} stroke="rgb(148 163 184 / .25)" strokeDasharray="4 5" vectorEffect="non-scaling-stroke" />}
      <path d={`${line} L${W} ${height} L0 ${height} Z`} fill={`url(#g${id})`} />
      <path d={line} fill="none" stroke={color} strokeWidth="2" vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
    </svg>
  );
}

export function Stat({ label, value, tone = "", hint }: { label: string; value: ReactNode; tone?: string; hint?: string }) {
  return (
    <div className="min-w-0">
      <div className="text-[11px] font-semibold uppercase tracking-wider text-faint">{label}</div>
      <div className={`num mt-1 truncate text-lg font-semibold ${tone}`} title={hint}>
        {value}
      </div>
    </div>
  );
}

export function Empty({ icon, title, children }: { icon?: ReactNode; title: string; children?: ReactNode }) {
  return (
    <div className="card grid place-items-center gap-2 px-6 py-12 text-center">
      {icon && <div className="text-brand-300">{icon}</div>}
      <div className="font-semibold">{title}</div>
      {children && <div className="max-w-md text-sm text-muted">{children}</div>}
    </div>
  );
}
