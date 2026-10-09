"use client";

import { Gauge, ShieldCheck, SlidersHorizontal, Users } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { api, dateMs, pct, usd, type Follow, type Leader } from "@/lib/api";
import { useSession } from "@/lib/session";
import { AreaChart, Notice, Stat } from "./ui";

/** Risk settings of a copy, with what they mean in money. No performance is shown here. */
export function RiskControls({ value, onChange }: { value: { allocation: number; multiplier: number; max_drawdown_pct: number }; onChange: (v: { allocation: number; multiplier: number; max_drawdown_pct: number }) => void }) {
  const { allocation, multiplier, max_drawdown_pct } = value;
  const set = (k: keyof typeof value) => (e: React.ChangeEvent<HTMLInputElement>) => onChange({ ...value, [k]: Number(e.target.value) });
  return (
    <div className="grid gap-5">
      <Slider label="Capital alloué" value={usd(allocation, 0)} min={100} max={20000} step={100} v={allocation} onChange={set("allocation")} />
      <Slider label="Multiplicateur de risque" value={`× ${multiplier.toFixed(1).replace(".", ",")}`} min={0.1} max={3} step={0.1} v={multiplier} onChange={set("multiplier")} />
      <Slider label="Arrêt automatique si la perte atteint" value={`${max_drawdown_pct} %`} min={5} max={50} step={1} v={max_drawdown_pct} onChange={set("max_drawdown_pct")} />
      <div className="grid grid-cols-2 gap-3 rounded-xl border border-white/10 bg-ink-950/60 p-4">
        <Stat label="Perte max. tolérée" value={usd((allocation * max_drawdown_pct) / 100, 0)} tone="text-down-400" />
        <Stat label="Taille vs leader" value={`${(multiplier * 100).toFixed(0)} %`} hint="taille des positions, en proportion du capital de référence du leader" />
      </div>
    </div>
  );
}

function Slider({ label, value, min, max, step, v, onChange }: { label: string; value: string; min: number; max: number; step: number; v: number; onChange: (e: React.ChangeEvent<HTMLInputElement>) => void }) {
  const fill = ((v - min) / (max - min)) * 100;
  return (
    <label className="grid gap-2">
      <span className="flex items-baseline justify-between gap-3 text-sm">
        <span className="text-muted">{label}</span>
        <span className="num font-semibold">{value}</span>
      </span>
      <input
        type="range" min={min} max={max} step={step} value={v} onChange={onChange}
        className="h-2 w-full cursor-pointer appearance-none rounded-full accent-brand-400"
        style={{ background: `linear-gradient(90deg, #2a8fea ${fill}%, rgb(148 163 184 / .18) ${fill}%)` }}
      />
    </label>
  );
}

export function CopySteps() {
  const steps = [
    { icon: Users, title: "Choisissez une stratégie", text: "Chaque stratégie est reliée à un robot suivi par la plateforme. Son historique vient du journal, jamais d'une saisie manuelle." },
    { icon: SlidersHorizontal, title: "Réglez votre risque", text: "Capital alloué, multiplicateur, perte maximale : la copie suit vos règles, pas l'inverse." },
    { icon: ShieldCheck, title: "Gardez le contrôle", text: "Arrêt en un clic, arrêt automatique au seuil de perte choisi, et vos fonds restent chez votre courtier." },
  ];
  return (
    <ol className="grid gap-4">
      {steps.map((s, i) => (
        <li key={s.title} className="flex gap-4">
          <span className="grid size-10 shrink-0 place-items-center rounded-xl border border-brand-400/30 bg-brand-400/10 text-brand-300">
            <s.icon className="size-5" />
          </span>
          <div>
            <div className="font-semibold">
              <span className="num mr-2 text-faint">0{i + 1}</span>
              {s.title}
            </div>
            <p className="mt-1 text-sm leading-relaxed text-muted">{s.text}</p>
          </div>
        </li>
      ))}
    </ol>
  );
}

export function LeaderCard({ l, onFollow }: { l: Leader; onFollow?: (l: Leader) => void }) {
  const r = l.record;
  return (
    <article className="card card-hover flex flex-col p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h3 className="truncate font-[family-name:var(--font-display)] text-lg font-bold">{l.name}</h3>
          <p className="text-sm text-muted">par {l.trader}{l.style ? ` · ${l.style}` : ""}</p>
        </div>
        <span className={`chip ${l.status === "open" ? "chip-green" : "chip-gold"}`}>{l.status_label}</span>
      </div>
      <div className="mt-4">
        <AreaChart points={r.curve} height={110} label={`Évolution de ${l.name}`} />
      </div>
      <div className="mt-4 grid grid-cols-3 gap-3">
        <Stat label="Rendement" value={pct(r.return_pct)} tone={(r.return_pct ?? 0) >= 0 ? "text-up-400" : "text-down-400"} />
        <Stat label="Pire baisse" value={r.max_drawdown_pct == null ? "—" : pct(-r.max_drawdown_pct, 1)} tone="text-down-400" />
        <Stat label="Risque" value={<RiskDots n={l.risk_level} />} />
      </div>
      <p className="mt-3 text-xs leading-relaxed text-faint">
        Source : {r.source_label}
        {r.since ? ` · depuis le ${dateMs(r.since)}` : ""} · {r.closed_trades} trade{r.closed_trades > 1 ? "s" : ""} clôturé{r.closed_trades > 1 ? "s" : ""} · {l.followers} copieur{l.followers > 1 ? "s" : ""}
      </p>
      {r.synthetic && <p className="mt-2 text-xs text-gold-300">Prix simulés : ces chiffres ne reflètent pas un marché réel.</p>}
      {l.bio && <p className="mt-3 text-sm leading-relaxed text-muted">{l.bio}</p>}
      {onFollow && l.status === "open" && (
        <button className="btn btn-primary btn-sm mt-5" onClick={() => onFollow(l)}>
          Copier en démo
        </button>
      )}
    </article>
  );
}

function RiskDots({ n }: { n: number }) {
  return (
    <span className="inline-flex gap-1" aria-label={`Risque ${n} sur 5`}>
      {[1, 2, 3, 4, 5].map((i) => (
        <span key={i} className={`h-3 w-1.5 rounded-sm ${i <= n ? (n >= 4 ? "bg-down-400" : n === 3 ? "bg-gold-400" : "bg-up-400") : "bg-white/10"}`} />
      ))}
    </span>
  );
}

export function FollowForm({ leader, onDone, onCancel }: { leader: Leader; onDone: (f: Follow) => void; onCancel: () => void }) {
  const { me } = useSession();
  const [v, setV] = useState({ allocation: 1000, multiplier: 1, max_drawdown_pct: 20 });
  const [accept, setAccept] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  if (!me)
    return (
      <Notice>
        <Link href="/compte/?vue=inscription" className="font-semibold text-brand-300 underline">Créez un compte gratuit</Link> pour copier une stratégie en démo.
      </Notice>
    );
  const submit = async () => {
    setBusy(true);
    setErr(null);
    try {
      onDone(await api<Follow>("/api/m/copy", { method: "POST", body: { leader_id: leader.id, ...v, accept_risk: accept, mode: "demo" } }));
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="grid gap-5">
      <div>
        <p className="eyebrow">Copie en démo</p>
        <h3 className="mt-1 font-[family-name:var(--font-display)] text-xl font-bold">{leader.name}</h3>
      </div>
      <RiskControls value={v} onChange={setV} />
      <label className="flex gap-3 text-sm leading-relaxed text-muted">
        <input type="checkbox" className="mt-1 size-4 accent-brand-500" checked={accept} onChange={(e) => setAccept(e.target.checked)} />
        <span>
          Je comprends que cette copie est une <strong className="text-fg">démonstration</strong> (aucun ordre n&apos;est passé pour moi), que les résultats
          passés ou simulés ne garantissent rien, et que le trading peut entraîner la perte de tout le capital engagé.
        </span>
      </label>
      {err && <Notice kind="error">{err}</Notice>}
      <div className="flex gap-2">
        <button className="btn btn-primary" onClick={submit} disabled={!accept || busy}>
          <Gauge className="size-4" /> Lancer la copie démo
        </button>
        <button className="btn btn-ghost" onClick={onCancel}>Annuler</button>
      </div>
    </div>
  );
}

export function FollowCard({ f, onStop }: { f: Follow; onStop?: (f: Follow) => void }) {
  const active = f.status === "active";
  return (
    <div className="card p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="font-semibold">{f.leader.name}</div>
          <div className="text-xs text-muted">
            par {f.leader.trader} · démarrée le {dateMs(f.start_ts)} · {f.mode === "demo" ? "démo" : "réel"}
          </div>
        </div>
        <span className={`chip ${active ? "chip-green" : "chip"}`}>{active ? "Active" : "Arrêtée"}</span>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Stat label="Valeur" value={usd(f.equity)} />
        <Stat label="Résultat" value={pct(f.return_pct)} tone={f.pnl >= 0 ? "text-up-400" : "text-down-400"} />
        <Stat label="Baisse actuelle" value={pct(-f.drawdown_pct, 1)} tone="text-down-400" />
        <Stat label="Arrêt à" value={`−${f.max_drawdown_pct} %`} />
      </div>
      <div className="mt-4">
        <AreaChart points={f.curve} height={90} baseline={f.allocation} label="Valeur de la copie" />
      </div>
      {f.stop_reason && <p className="mt-3 text-xs text-gold-300">{f.stop_reason}</p>}
      <p className="mt-2 text-xs text-faint">{f.source_label}{f.synthetic ? " : prix simulés, résultat non représentatif d'un marché réel." : ""}</p>
      {active && onStop && (
        <button className="btn btn-danger btn-sm mt-4" onClick={() => onStop(f)}>
          Arrêter la copie
        </button>
      )}
    </div>
  );
}
