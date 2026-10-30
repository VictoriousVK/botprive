"use client";

// Shared pieces of the trading space: data loading, section cards, candlestick chart with ICT
// levels, live run steps, copy fields, file input, breakdown tables.

import { Check, CircleAlert, CircleCheck, CircleDashed, Copy, Hourglass, LoaderCircle, Upload } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { Notice } from "@/components/ui";
import { KZ_LABEL, appApi, n2, pc, rr, tone, type Group, type RunStep } from "@/lib/app";

// ---------------- data ----------------
/** GET a JSON resource; ``reload`` refetches, ``set`` patches the local copy. */
export function useLoad<T>(path: string | null) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const reload = useCallback(async () => {
    if (!path) return;
    setLoading(true);
    try {
      setData(await appApi<T>(path));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erreur");
    } finally {
      setLoading(false);
    }
  }, [path]);
  useEffect(() => {
    reload();
  }, [reload]);
  return { data, error, loading, reload, set: setData };
}

/** Runs an action with a busy flag and a message; returns the result or null on error. */
export function useAction() {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "error"; text: string } | null>(null);
  const run = useCallback(async <T,>(fn: () => Promise<T>, ok?: string): Promise<T | null> => {
    setBusy(true);
    setMsg(null);
    try {
      const out = await fn();
      if (ok) setMsg({ kind: "ok", text: ok });
      return out;
    } catch (e) {
      setMsg({ kind: "error", text: e instanceof Error ? e.message : "Erreur" });
      return null;
    } finally {
      setBusy(false);
    }
  }, []);
  const note = msg ? <Notice kind={msg.kind} className="mt-3">{msg.text}</Notice> : null;
  return { busy, run, note, setMsg };
}

// ---------------- layout ----------------
export function Section({ title, icon, actions, children, className = "", id }: { title: ReactNode; icon?: ReactNode; actions?: ReactNode; children: ReactNode; className?: string; id?: string }) {
  return (
    <section className={`card min-w-0 p-5 sm:p-6 ${className}`} id={id}>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <h2 className="flex min-w-0 flex-1 items-center gap-2 font-semibold">
          {icon && <span className="text-brand-300">{icon}</span>}
          {title}
        </h2>
        {actions}
      </div>
      {children}
    </section>
  );
}

export function Seg<T extends string>({ value, options, onChange, label }: { value: T; options: [T, string][]; onChange: (v: T) => void; label: string }) {
  return (
    <div className="inline-flex rounded-lg border border-white/10 bg-white/[0.02] p-0.5" role="group" aria-label={label}>
      {options.map(([v, l]) => (
        <button key={v} type="button" onClick={() => onChange(v)} aria-pressed={v === value}
          className={`rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${v === value ? "bg-white/10 text-white" : "text-muted hover:text-white"}`}>
          {l}
        </button>
      ))}
    </div>
  );
}

export function LabelChip({ map, k }: { map: Record<string, [string, string]>; k: string | null | undefined }) {
  if (!k) return null;
  const [text, cls] = map[k] ?? [k, ""];
  return <span className={`chip ${cls}`}>{text}</span>;
}

export function Kv({ k, v, className = "" }: { k: ReactNode; v: ReactNode; className?: string }) {
  return (
    <div className={`flex items-baseline justify-between gap-4 border-b border-white/5 py-1.5 text-sm last:border-0 ${className}`}>
      <span className="text-muted">{k}</span>
      <span className="num text-right">{v}</span>
    </div>
  );
}

export function Bullets({ items, empty }: { items: string[]; empty?: string }) {
  if (!items.length) return empty ? <p className="text-sm text-faint">{empty}</p> : null;
  return (
    <ul className="grid gap-1.5 text-sm leading-relaxed text-fg/85">
      {items.map((x, i) => (
        <li key={i} className="flex gap-2"><span className="mt-2 size-1 shrink-0 rounded-full bg-brand-400" aria-hidden />{x}</li>
      ))}
    </ul>
  );
}

export function Disclaimer({ text, narratedBy }: { text?: string; narratedBy?: string }) {
  return (
    <p className="mt-4 border-t border-white/5 pt-3 text-xs leading-relaxed text-faint">
      {narratedBy === "rules" && <>Rédigé par les règles (sans modèle de langage). </>}
      {narratedBy === "llm" && <>Chiffres calculés par les moteurs, texte rédigé par l&apos;IA. </>}
      {text ?? "Outil d'analyse et d'éducation, pas un conseil en investissement. Le trading comporte un risque de perte en capital."}
    </p>
  );
}

// ---------------- inputs ----------------
export function CopyField({ label, value, secret = false }: { label: string; value: string; secret?: boolean }) {
  const [done, setDone] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      setDone(true);
      setTimeout(() => setDone(false), 1500);
    } catch {
      /* clipboard refused: the text stays selectable */
    }
  };
  return (
    <label className="field">
      <span>{label}</span>
      <div className="flex gap-2">
        <input className={`input num text-xs ${secret ? "text-gold-300" : ""}`} readOnly value={value} onFocus={(e) => e.currentTarget.select()} />
        <button type="button" className="btn btn-ghost btn-sm shrink-0" onClick={copy} aria-label={`Copier : ${label}`}>
          {done ? <Check className="size-4" aria-hidden /> : <Copy className="size-4" aria-hidden />}
        </button>
      </div>
    </label>
  );
}

export function FileDrop({ accept, onFile, busy, hint }: { accept: string; onFile: (f: File) => void; busy?: boolean; hint: string }) {
  const ref = useRef<HTMLInputElement>(null);
  const [over, setOver] = useState(false);
  return (
    <div
      onDragOver={(e) => { e.preventDefault(); setOver(true); }}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => { e.preventDefault(); setOver(false); const f = e.dataTransfer.files?.[0]; if (f) onFile(f); }}
      className={`grid place-items-center gap-2 rounded-xl border border-dashed px-4 py-8 text-center transition-colors ${over ? "border-brand-400 bg-brand-400/5" : "border-white/15"}`}
    >
      {busy ? <LoaderCircle className="size-6 animate-spin text-brand-300" aria-hidden /> : <Upload className="size-6 text-brand-300" aria-hidden />}
      <button type="button" className="btn btn-ghost btn-sm" disabled={busy} onClick={() => ref.current?.click()}>Choisir un fichier</button>
      <p className="max-w-sm text-xs text-muted">{hint}</p>
      <input ref={ref} type="file" accept={accept} className="sr-only" onChange={(e) => { const f = e.target.files?.[0]; if (f) onFile(f); e.target.value = ""; }} />
    </div>
  );
}

// ---------------- runs ----------------
const STEP_ICON: Record<string, ReactNode> = {
  ok: <CircleCheck className="size-4 text-up-400" aria-hidden />,
  error: <CircleAlert className="size-4 text-down-400" aria-hidden />,
  running: <LoaderCircle className="size-4 animate-spin text-brand-300" aria-hidden />,
  waiting: <Hourglass className="size-4 text-gold-400" aria-hidden />,
};

export function RunSteps({ steps, status }: { steps: RunStep[]; status: string | null }) {
  if (!status) return null;
  const nodes = steps.filter((s) => s.kind !== "tool" || steps.length < 14);
  return (
    <div className="rounded-xl border border-white/10 bg-ink-900/60 p-4" aria-live="polite">
      <div className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">
        {status === "running" ? "Analyse en cours" : status === "waiting" ? "En attente de votre décision" : status === "done" ? "Terminé" : status === "failed" ? "Échec" : "Suivi interrompu"}
      </div>
      <ol className="grid gap-1.5 text-sm">
        {nodes.map((s) => (
          <li key={s.id} className="flex items-center gap-2">
            {STEP_ICON[s.status] ?? <CircleDashed className="size-4 text-faint" aria-hidden />}
            <span className={s.kind === "tool" || s.kind === "guardrail" ? "text-muted" : ""}>{s.name}</span>
            {s.ms != null && <span className="num ml-auto text-xs text-faint">{s.ms < 1000 ? `${s.ms} ms` : `${n2(s.ms / 1000, 1)} s`}</span>}
          </li>
        ))}
        {status === "running" && !nodes.length && <li className="text-muted">Mise en file…</li>}
      </ol>
    </div>
  );
}

// ---------------- tables ----------------
export function GroupTable({ rows, keyLabel, label }: { rows: Group[]; keyLabel: string; label?: Record<string, string> }) {
  if (!rows.length) return <p className="text-sm text-faint">Pas encore de données.</p>;
  return (
    <div className="overflow-x-auto">
      <table className="table">
        <thead>
          <tr><th>{keyLabel}</th><th className="text-right">Trades</th><th className="text-right">Réussite</th><th className="text-right">Espérance</th><th className="text-right">Net</th></tr>
        </thead>
        <tbody>
          {rows.map((g) => (
            <tr key={g.key}>
              <td>{(label ?? { ...KZ_LABEL, "—": "Hors killzone" })[g.key] ?? g.key}</td>
              <td className="num text-right">{g.n}</td>
              <td className="num text-right">{pc(g.win_rate, 0)}</td>
              <td className={`num text-right ${tone(g.expectancy_r)}`}>{g.r_count ? rr(g.expectancy_r) : "—"}</td>
              <td className={`num text-right ${tone(g.net)}`}>{n2(g.net)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ---------------- charts ----------------
export type Bar = [number, number, number, number, number]; // open time, o, h, l, c
export type Level = { price: number; label: string; color?: string; dash?: boolean };
export type Zone = { top: number; bottom: number; label?: string; color?: string };
export type Mark = { t: number; price: number; label: string; color?: string };

const fmtPrice = (x: number) => (Math.abs(x) >= 1000 ? n2(x, 1) : Math.abs(x) >= 10 ? n2(x, 2) : n2(x, 5));

/** Candlestick chart with horizontal levels and shaded zones (FVG, entry zone). Pure SVG. */
export function Candles({ bars, levels = [], zones = [], marks = [], height = 320, label, picked, onPick }: {
  bars: Bar[]; levels?: Level[]; zones?: Zone[]; marks?: Mark[]; height?: number; label: string; picked?: number | null; onPick?: (i: number) => void;
}) {
  if (bars.length < 2) {
    return <div className="grid place-items-center rounded-xl border border-dashed border-white/10 text-sm text-faint" style={{ height }}>Pas de cours disponibles</div>;
  }
  const W = 760;
  const AX = 64; // right axis
  const PW = W - AX;
  const H = height;
  let lo = Math.min(...bars.map((b) => b[3]));
  let hi = Math.max(...bars.map((b) => b[2]));
  const visible = (p: number) => p >= lo - (hi - lo) * 0.35 && p <= hi + (hi - lo) * 0.35;
  for (const l of levels) if (visible(l.price)) { lo = Math.min(lo, l.price); hi = Math.max(hi, l.price); }
  for (const z of zones) if (visible(z.top) || visible(z.bottom)) { lo = Math.min(lo, z.bottom); hi = Math.max(hi, z.top); }
  const pad = (hi - lo || 1) * 0.06;
  lo -= pad;
  hi += pad;
  const y = (p: number) => H - ((p - lo) / (hi - lo)) * H;
  const step = PW / bars.length;
  const bw = Math.max(1, step * 0.62);
  const ticks = Array.from({ length: 5 }, (_, i) => lo + ((hi - lo) * (i + 0.5)) / 5);
  const inView = (p: number) => p >= lo && p <= hi;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="block h-auto w-full" role="img" aria-label={label}>
      {ticks.map((t) => (
        <g key={t}>
          <line x1={0} x2={PW} y1={y(t)} y2={y(t)} stroke="rgb(148 163 184 / .08)" />
          <text x={PW + 6} y={y(t) + 3} fontSize="10" fill="#5d6a7e" className="num">{fmtPrice(t)}</text>
        </g>
      ))}
      {zones.map((z, i) => {
        const top = Math.min(hi, z.top);
        const bot = Math.max(lo, z.bottom);
        if (top <= bot) return null;
        return (
          <g key={`z${i}`}>
            <rect x={0} width={PW} y={y(top)} height={Math.max(1, y(bot) - y(top))} fill={z.color ?? "rgb(79 176 255 / .10)"} />
            {z.label && <text x={4} y={y(top) + 11} fontSize="10" fill="#93a1b5">{z.label}</text>}
          </g>
        );
      })}
      {picked != null && picked >= 0 && picked < bars.length && <rect x={picked * step} width={step} y={0} height={H} fill="rgb(212 179 116 / .14)" />}
      {bars.map((b, i) => {
        const [, o, h, l, c] = b;
        const x = i * step + step / 2;
        const up = c >= o;
        const col = up ? "#4be08a" : "#ef5354";
        return (
          <g key={b[0]}>
            <line x1={x} x2={x} y1={y(h)} y2={y(l)} stroke={col} strokeWidth="1" />
            <rect x={x - bw / 2} width={bw} y={y(Math.max(o, c))} height={Math.max(1, Math.abs(y(o) - y(c)))} fill={col} opacity={up ? 0.9 : 0.85} />
          </g>
        );
      })}
      {marks.map((m, i) => {
        const k = bars.findIndex((b) => b[0] === m.t);
        if (k < 0 || !inView(m.price)) return null;
        return (
          <g key={`m${i}`}>
            <circle cx={k * step + step / 2} cy={y(m.price)} r={4} fill="none" stroke={m.color ?? "#d4b374"} strokeWidth="1.5" />
            <text x={k * step + step / 2} y={y(m.price) - 7} fontSize="9" fill={m.color ?? "#d4b374"} textAnchor="middle">{m.label}</text>
          </g>
        );
      })}
      {onPick && bars.map((b, i) => (
        <rect key={`p${b[0]}`} x={i * step} width={step} y={0} height={H} fill="transparent" className="cursor-crosshair" onClick={() => onPick(i)}>
          <title>{new Date(b[0]).toISOString().slice(0, 16).replace("T", " ")} UTC</title>
        </rect>
      ))}
      {levels.filter((l) => inView(l.price)).map((l, i) => (
        <g key={`l${i}`}>
          <line x1={0} x2={PW} y1={y(l.price)} y2={y(l.price)} stroke={l.color ?? "#d4b374"} strokeWidth="1" strokeDasharray={l.dash ? "5 4" : undefined} />
          <rect x={PW} y={y(l.price) - 8} width={AX} height={16} fill={l.color ?? "#d4b374"} opacity=".9" rx="3" />
          <text x={PW + 4} y={y(l.price) + 3.5} fontSize="10" fill="#06101c" fontWeight="600" className="num">{fmtPrice(l.price)}</text>
          <text x={PW - 4} y={y(l.price) - 4} fontSize="10" fill={l.color ?? "#d4b374"} textAnchor="end">{l.label}</text>
        </g>
      ))}
    </svg>
  );
}

/** Horizontal gauge (0 to 100 %), for loss limits and quotas. */
export function Gauge({ value, label, hint }: { value: number | null | undefined; label: string; hint?: string }) {
  const v = Math.max(0, Math.min(100, value ?? 0));
  const col = v >= 90 ? "bg-down-500" : v >= 70 ? "bg-gold-400" : "bg-up-400";
  return (
    <div>
      <div className="flex items-baseline justify-between text-sm">
        <span className="text-muted">{label}</span>
        <span className="num">{value == null ? "—" : `${n2(v, 1)} %`}</span>
      </div>
      <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-white/5" role="meter" aria-valuenow={v} aria-valuemin={0} aria-valuemax={100} aria-label={label}>
        <div className={`h-full rounded-full ${col}`} style={{ width: `${v}%` }} />
      </div>
      {hint && <p className="mt-1 text-xs text-faint">{hint}</p>}
    </div>
  );
}
