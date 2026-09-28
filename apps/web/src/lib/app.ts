"use client";

// Alpha Edge SaaS: types of /api/app/* and client helpers (formatting, files, live run steps).

import { useEffect, useRef, useState } from "react";
import { api } from "./api";

// ---------------- types ----------------
export type Plan = "gratuit" | "starter" | "pro_trader" | "quant_elite";
export type AppMe = {
  tenant: string; plan: Plan; limits: Record<string, number>; usage: Record<string, { count: number; cost_usd: number }>; month: string;
  features: Record<string, boolean>; ai: boolean; market: { source: string | null; synthetic: boolean | null }; manifest: string;
};
export type Account = {
  id: string; label: string; broker: string; server: string; login: string; kind: "demo" | "real" | "prop"; access_mode: "csv" | "sync_ea" | "investor";
  server_winter_offset_h: number; server_dst_rule: "us" | "eu" | "none"; server_utc_offset_min: number | null; currency: string; starting_balance: number | null;
  prop_profile: string | null; last_sync_at: number | null; created_at: number; has_secret: boolean;
};
export type JournalEntry = { setup_model: string | null; emotion_before: string | null; emotion_after: string | null; followed_plan: boolean | null; mistakes: string[]; notes: string; rating: number | null };
export type Trade = {
  id: string; account_id: string; position_id: string; symbol: string; symbol_raw: string; side: "long" | "short"; volume: number; open_utc: number; close_utc: number | null;
  open_price: number; close_price: number | null; sl: number | null; tp: number | null; commission: number; swap: number; profit: number; net: number; risk_amount: number | null;
  r_multiple: number | null; r_source: "sl" | "plan" | "none"; session: string | null; killzone: string | null; macro: string | null; weekday: number | null; setup_model: string | null;
  plan_respected: boolean | null; source: string; journal: JournalEntry | null; executions?: { deal_id: string; time_utc: number; entry: string; price: number; volume: number; profit: number }[];
};
export type Group = { key: string; n: number; wins: number; win_rate: number | null; net: number; expectancy_r: number | null; r_count: number };
export type Kpis = {
  n: number; wins: number; losses: number; breakeven: number; win_rate: number | null; win_rate_ci95: [number, number] | null; expectancy_r: number | null; expectancy_r_ci95: [number, number] | null;
  r_coverage: number | null; avg_win_r: number | null; avg_loss_r: number | null; profit_factor: number | null; net_total: number; max_drawdown: number; max_drawdown_r: number | null;
  max_consecutive_losses: number; insufficient: boolean; sample_warning: boolean; min_trades: number; open_positions?: number | null;
  by_killzone: Group[]; by_setup: Group[]; by_weekday: Group[]; by_symbol: Group[]; by_session: Group[]; by_direction: Group[];
};
export type Flag = { kind: string; trade_ids: string[]; metric: string; value: number; threshold: number; detail: string };
export type Stats = { period: [number, number]; days: number; balance: number | null; kpis: Kpis; flags: Flag[]; equity: { t: number; net: number; r: number }[]; plan: TradingPlan };
export type TradingPlan = {
  markets: string[]; killzones: string[]; risk_per_trade_pct: number; max_daily_loss_pct: number; max_trades_per_day: number; revenge_minutes: number; size_up_factor: number; min_rr: number; setups: string[]; rules: string[];
};
export type Profile = { level: string; experience_months: number; goals: string[]; prop_firm: string | null; trades_manually: boolean; uses_eas: boolean; language: "fr" | "en" };
export type Lesson = { id: string; text: string; behavior: string; status: "proposed" | "accepted" | "edited" | "rejected" | "retired"; source_trade_ids: string[]; created_at?: number; effective_strength?: number | null };
export type Evidence = { source_id: string; field: string; value: string | number; as_of: number };
export type CoachVerdict = {
  agent: string; label: "ON_PLAN" | "MINOR_DRIFT" | "MAJOR_DRIFT" | "INSUFFICIENT_DATA"; label_fr: string; confidence: number; evidence: Evidence[]; summary: string; caveats: string[];
  trace_id: string; narrated_by: "llm" | "rules"; kpis: Kpis; flags: Flag[]; reflection_questions: string[]; lessons: Lesson[]; disclaimer: string; last_line: string;
};
export type Review = { id: string; status: string; error: string | null; verdict: CoachVerdict | null };
export type RunStep = { id: string; name: string; kind: string; status: string; t: number; ms: number | null };
export type Candidate = {
  model: string; direction: "long" | "short"; htf_bias: string; entry_zone: [number, number]; entry: number; invalidation: number; targets: number[]; rr: number; rule_score: number; min_score: number;
  relaxed: boolean; rules_passed: string[]; rules_failed: string[]; evidence_ids: string[]; description: string;
};
export type RiskGate = {
  decision: "PASS" | "REDUCE" | "BLOCK"; max_lots: number; risk_amount: number; risk_pct: number; profile: string; profile_verified: boolean; rules_applied: string[]; violations: string[];
  warnings: string[]; disagreement_logged: boolean; room?: Record<string, number>; state?: Record<string, number | string>; symbol?: string; account_id?: string; futures?: boolean;
};
export type IctCompact = {
  symbol: string; price: number; htf_bias: string; premium_discount: string; dealing_range: [number, number];
  time: { ny_time: string; killzone: string | null; macro_window: string | null; silver_bullet_window: string | null; midnight_open: number | null; daily_open_18h: number | null; amd_phase: string };
  unswept_pools: { side: string; level: number; source: string }[]; open_fvgs: { kind: string; top: number; bottom: number; status: string }[];
  structure: { kind: string; direction: string; level: number; timeframe: string }[]; rejections: string[]; caveats: string[];
};
export type SetupCard = {
  label: "VALID_BY_RULES" | "PARTIAL" | "INVALID" | "NO_SETUP" | "INSUFFICIENT_EVIDENCE"; confidence: number; summary: string; caveats: string[]; trace_id: string; narrated_by: "llm" | "rules";
  symbol: string; as_of: number; candidate: Candidate | null; ict: IctCompact; risk_gate: RiskGate | null; stats: { n: number; win_rate: number | null; expectancy_r: number | null; sample_warning: boolean } | null;
  plan_alignment: string[]; points_to_check: string[]; expires_at: number | null; disclaimer: string; debate?: { decision?: string; reasons?: string[]; caveat?: string } | null;
};
export type Analysis = { id: string; status: string; error: string | null; card: SetupCard | null; decision: string | null };
export type Citation = { doc_id: string; chunk_id: string; title: string; ref: string | null; timestamp_s: number | null };
export type MentorAnswer = { label: string; summary: string; caveats: string[]; narrated_by: string; citations: Citation[]; exercise: string | null; disclaimer: string; trace_id: string };
export type Notification = { id: string; kind: string; title: string; body: string; link: string | null; read_at: number | null; created_at: number };
export type Overview = {
  plan: Plan; limits: Record<string, number>; usage: AppMe["usage"]; features: Record<string, boolean>; ai: boolean; market: AppMe["market"];
  stats: { kpis: Partial<Kpis>; flags: Flag[]; equity: { t: number; net: number; r: number }[]; by_killzone: Group[] } | null;
  accounts: Account[] | null; last_review: { id: string; status: string; created_at: number; label: string | null } | null; lessons: Lesson[] | null;
  analyses: { id: string; symbol: string; label: string; decision: string | null; created_at: number; model: string | null; source: string }[] | null;
  briefing: { label: string; summary: string; session: string; high_impact_events: { title: string; currency: string; time_utc: number }[]; caveats: string[] } | null;
  guard: GuardStatus | null; notifications: number | null;
};
export type GuardStatus = {
  account_id: string; profile: string; profile_label: string; profile_verified: boolean; daily_used_pct?: number; max_used_pct?: number; alerts: { kind: string; level: number }[];
  limits: { daily_limit: number | null; daily_room: number | null; max_floor: number | null; max_room: number | null; current: number }; state: Record<string, number | string>; notes: string[];
  objectives?: {
    size_known: boolean; warnings: string[]; target?: { amount: number; progress_pct: number }; trading_days?: { done: number; required: number };
    consistency?: { best_day: number; share_pct: number; limit_pct: number; base: string }; max_contracts?: number;
  };
};

// ---------------- labels ----------------
export const PLAN_LABEL: Record<string, string> = { gratuit: "Gratuit", starter: "Starter", pro_trader: "Pro Trader", quant_elite: "Quant Elite" };
export const FEATURE_OFFER: Record<string, string> = {
  journal: "Gratuit", coach: "Gratuit", analysis: "Starter", briefing: "Starter", mentor: "Starter", mt5_sync: "Pro Trader", prop_guard: "Pro Trader", tradingview: "Pro Trader",
  lab: "Pro Trader", ea_factory: "Quant Elite", public_api: "Quant Elite",
};
export const KZ_LABEL: Record<string, string> = { Asia: "Asie", London: "Londres", NY_AM: "NY AM", NY_Lunch: "NY Lunch", NY_PM: "NY PM" };
export const BEHAVIOR_LABEL: Record<string, string> = {
  overtrading: "Surtrading", revenge_trade: "Trade de revanche", size_up_after_loss: "Lot augmenté après une perte", plan_violation: "Hors plan", outside_killzone: "Hors killzone",
  news_window: "Près d'une annonce", stop_widened: "Stop élargi", early_exit: "Sortie précoce", risk_above_plan: "Risque au-delà du plan",
};
export const COACH_LABEL: Record<string, [string, string]> = {
  ON_PLAN: ["Conforme au plan", "chip-green"], MINOR_DRIFT: ["Écarts ponctuels", "chip-gold"], MAJOR_DRIFT: ["Écarts importants", "chip-red"], INSUFFICIENT_DATA: ["Échantillon insuffisant", ""],
};
export const SETUP_LABEL: Record<string, [string, string]> = {
  VALID_BY_RULES: ["Valide selon les règles", "chip-green"], PARTIAL: ["Partiel (passe relâchée)", "chip-gold"], INVALID: ["Invalidé", "chip-red"], NO_SETUP: ["Aucun setup", ""],
  INSUFFICIENT_EVIDENCE: ["Données insuffisantes", "chip-red"],
};
export const GATE_LABEL: Record<string, [string, string]> = { PASS: ["Risque conforme", "chip-green"], REDUCE: ["Taille réduite", "chip-gold"], BLOCK: ["Bloqué par le risk gate", "chip-red"] };
export const MODEL_LABEL: Record<string, string> = { SilverBullet: "Silver Bullet", MacroBreaker: "Macro Breaker", DailyOpenSweep: "Daily Open 18 h", Venom: "Venom", OTE: "OTE", Custom: "Personnalisé" };
export const EMOTIONS: [string, string][] = [["calme", "Calme"], ["confiant", "Confiant"], ["neutre", "Neutre"], ["hesitant", "Hésitant"], ["stresse", "Stressé"], ["frustre", "Frustré"], ["euphorique", "Euphorique"], ["fatigue", "Fatigué"], ["impatient", "Impatient"]];
export const MISTAKES: [string, string][] = [["entree_precoce", "Entrée trop tôt"], ["entree_tardive", "Entrée trop tard"], ["sans_setup", "Sans setup"], ["stop_deplace", "Stop déplacé"], ["sortie_precoce", "Sortie trop tôt"], ["taille_excessive", "Taille excessive"], ["hors_plan", "Hors plan"], ["revenge", "Revanche"], ["autre", "Autre"]];

// ---------------- formatting ----------------
const nf = (d: number) => new Intl.NumberFormat("fr-FR", { minimumFractionDigits: d, maximumFractionDigits: d });
export const n2 = (x: number | null | undefined, d = 2) => (x == null || !Number.isFinite(x) ? "—" : nf(d).format(x));
export const rr = (x: number | null | undefined) => (x == null ? "—" : `${x > 0 ? "+" : ""}${nf(2).format(x)} R`);
export const pc = (x: number | null | undefined, d = 1) => (x == null ? "—" : `${nf(d).format(x * 100)} %`);
export const money = (x: number | null | undefined, cur = "USD") => (x == null ? "—" : new Intl.NumberFormat("fr-FR", { style: "currency", currency: cur.length === 3 ? cur : "USD", maximumFractionDigits: 2 }).format(x));
export const when = (ms: number | null | undefined) => (ms ? new Date(ms).toLocaleString("fr-FR", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—");
export const day = (ms: number) => new Date(ms).toLocaleDateString("fr-FR", { day: "numeric", month: "short" });
export const tone = (x: number | null | undefined) => (x == null ? "" : x > 0 ? "text-up-400" : x < 0 ? "text-down-400" : "");

export async function fileToBase64(file: File): Promise<string> {
  const buf = new Uint8Array(await file.arrayBuffer());
  let s = "";
  for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(s);
}

export async function appApi<T = unknown>(path: string, method = "GET", body?: unknown): Promise<T> {
  return api<T>(path, { method, body });
}

/** Live steps of an agent run (server-sent events), then the final status. */
export function useRunStream(traceId: string | null, onEnd?: (status: string) => void) {
  const [steps, setSteps] = useState<RunStep[]>([]);
  const [status, setStatus] = useState<string | null>(null);
  const cb = useRef(onEnd);
  cb.current = onEnd;
  useEffect(() => {
    if (!traceId) return;
    setSteps([]);
    setStatus("running");
    const es = new EventSource(`/api/app/runs/${traceId}/stream`, { withCredentials: true });
    es.addEventListener("step", (e) => {
      const s = JSON.parse((e as MessageEvent).data) as RunStep;
      setSteps((prev) => [...prev.filter((p) => p.id !== s.id), s].sort((a, b) => a.t - b.t));
    });
    es.addEventListener("end", (e) => {
      const st = (JSON.parse((e as MessageEvent).data) as { status: string }).status;
      setStatus(st);
      es.close();
      cb.current?.(st);
    });
    es.onerror = () => {
      es.close();
      setStatus((s) => (s === "running" ? "unknown" : s));
      cb.current?.("unknown");
    };
    return () => es.close();
  }, [traceId]);
  return { steps, status };
}
