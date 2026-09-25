// Same-origin JSON client for the platform API. Members and operators have separate sessions,
// each with its own CSRF token, sent in X-CSRF-Token on every state-changing call.

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const tokens: { member: string; operator: string } = { member: "", operator: "" };

export function setCsrf(kind: "member" | "operator", token: string) {
  tokens[kind] = token || "";
}

type Opts = { method?: string; body?: unknown; as?: "member" | "operator" };

export async function api<T = unknown>(path: string, { method = "GET", body, as = "member" }: Opts = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (method !== "GET" && tokens[as]) headers["X-CSRF-Token"] = tokens[as];
  let res: Response;
  try {
    res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: "same-origin", cache: "no-store" });
  } catch {
    throw new ApiError(0, "Connexion impossible : vérifiez votre réseau.");
  }
  let data: unknown = null;
  try {
    data = await res.json();
  } catch {
    /* empty body */
  }
  if (!res.ok) {
    const d = (data as { detail?: unknown } | null)?.detail;
    const msg = typeof d === "string" ? d : Array.isArray(d) ? "Champs invalides : vérifiez le formulaire." : `Erreur ${res.status}`;
    throw new ApiError(res.status, msg.charAt(0).toUpperCase() + msg.slice(1));
  }
  return data as T;
}

// ---------------- types ----------------
export type Highlight = { text: string; soon: boolean };
export type Product = {
  key: string; category: "abonnement" | "formation" | "mentorat" | "licence"; label: string; period: "month" | "once"; status: "available" | "soon" | "contact"; status_label: string;
  price_usd: number | null; price_xof: number | null; price_range_usd: [number, number] | null; alt_price: string; summary: string; audience: string[];
  highlights: Highlight[]; entitlements: string[]; featured: boolean; page: string; purchasable: boolean;
};
export type Founder = { name: string; role: string; initials: string; bio: string; mark?: string };
export type SiteInfo = {
  brand: { name: string; platform: string; tagline: string; pitch: string; country: string; contact_email: string };
  founders: Founder[];
  free: { label: string; summary: string; entitlements: string[] };
  products: Product[];
  categories: Record<string, string>;
  billing: { currency: string; usd_xof: number | null; durations: { months: number; free_months: number }[]; wave_manual: boolean };
  payment_methods: { name: string; status: "available" | "soon" }[];
  contact: { whatsapp: string; whatsapp_display: string; email: string };
  academy: { planned: { slug: string; title: string; subtitle: string; level: string }[] };
  entitlements: Record<string, string>;
  copytrading: "off" | "demo" | "live";
  wave: "api" | "manual" | "off";
  registration_open: boolean;
  version: string;
};
export type Robot = { key: string; name: string; status: string; status_label: string; headline: string; markets: string; access: string | null; description: string; timeframes: string[]; origin: string; params: number };
export type Quote = { symbol: string; label: string; price: number; digits: number; change_pct: number | null };
export type Quotes = { synthetic: boolean; source: string; quotes: Quote[] };
export type Access = { product: string; label: string; category: string; period: string; starts_at: number; expires_at: number | null; page: string };
export type Me = {
  id: number; email: string; name: string; phone: string | null; offer: string; offer_label: string; offer_expires_at: number | null; access: Access[];
  entitlements: string[]; community: { telegram?: string; discord?: string }; totp_enabled: boolean; created_at: number; csrf?: string;
};
export type Payment = { id: string; offer: string; offer_label: string; months: number; amount: number; currency: string; method: string; method_label: string; status: string; status_label: string; transaction_ref: string | null; launch_url: string | null; created_at: number; applied_at: number | null; email?: string; name?: string; note?: string | null };
export type CheckoutResult = { payment: Payment; launch_url?: string; manual?: { number: string | null; link: string | null; amount: number; reference: string } };
export type CourseSummary = { slug: string; title: string; subtitle: string; level: string; access: string; access_label: string; status: string; parts: number; duration_s: number; free_parts: number; planned?: boolean };
export type Player = { kind: "iframe" | "video"; src: string };
export type Part = { id: string; position: number; title: string; summary: string; duration_s: number; free_preview: boolean; locked: boolean; chapters: { t: number; title: string }[]; player: Player | null; progress: { position_s: number; completed: boolean } | null };
export type Course = { slug: string; title: string; subtitle: string; description: string; level: string; status: string; access: string; access_label: string; unlocked: boolean; parts: Part[] };
export type CurvePoint = { t: number; v: number };
export type Leader = {
  id: string; name: string; trader: string; bio: string; style: string; risk_level: number; ref_capital: number; status: string; status_label: string; followers: number; bot_id?: string | null;
  record: { source_mode: string; source_label: string; synthetic: boolean; closed_trades: number; win_rate: number | null; running: boolean; since: number | null; return_pct: number | null; max_drawdown_pct: number | null; curve: CurvePoint[] };
};
export type Follow = {
  id: string; leader: { id: string; name: string; trader: string }; mode: string; allocation: number; multiplier: number; max_drawdown_pct: number; status: string; stop_reason: string | null;
  start_ts: number; stop_ts: number | null; equity: number; pnl: number; return_pct: number; drawdown_pct: number; max_drawdown_seen_pct: number; curve: CurvePoint[]; source_label: string; synthetic: boolean;
};

// ---------------- formatting ----------------
export const fcfa = (n: number) => `${new Intl.NumberFormat("fr-FR").format(Math.round(n))} FCFA`;
export const dollars = (n: number) => `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 }).format(n)} $`;
export const whatsappLink = (number: string, text: string) => `https://wa.me/${number}?text=${encodeURIComponent(text)}`;
export const usd = (n: number, d = 2) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "USD", maximumFractionDigits: d, minimumFractionDigits: d }).format(n);
export const pct = (n: number | null | undefined, d = 2, sign = true) => (n == null || !Number.isFinite(n) ? "—" : `${sign && n > 0 ? "+" : ""}${n.toFixed(d).replace(".", ",")} %`);
export const price = (n: number, digits: number) => new Intl.NumberFormat("fr-FR", { minimumFractionDigits: Math.min(digits, 5), maximumFractionDigits: Math.min(digits, 5) }).format(n);
export const dateFr = (sec: number) => new Date(sec * 1000).toLocaleDateString("fr-FR", { day: "numeric", month: "short", year: "numeric" });
export const dateMs = (ms: number) => new Date(ms).toLocaleDateString("fr-FR", { day: "numeric", month: "short", year: "numeric" });
export function duration(s: number) {
  if (!s) return "—";
  const h = Math.floor(s / 3600);
  const m = Math.round((s % 3600) / 60);
  return h ? `${h} h ${String(m).padStart(2, "0")} min` : `${m} min`;
}
export const clock = (s: number) => {
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return (h ? `${h}:${String(m).padStart(2, "0")}` : `${m}`) + `:${String(sec).padStart(2, "0")}`;
};
