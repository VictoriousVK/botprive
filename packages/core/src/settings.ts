import { z } from "zod";
import { settings as settingsTable, type Db } from "@vk/db";
import { audit } from "./audit";
import { PLAN_IDS, PLANS, WEEK_DAYS, type PlanDefinition, type PlanId, type WeekDay } from "./config/club";
import { DomainError } from "./errors";

/*
 * Réglages modifiables depuis le tableau de bord, stockés en base (table settings).
 * Chaque réglage a un schéma de validation et une valeur par défaut.
 * Aucun montant en FCFA n'est fixé par défaut : Victor les saisit puis les valide.
 */

const planSettingsSchema = z.object({
  /** Prix affiché en dollars (vitrine). null = non affiché. */
  priceUsd: z.number().int().positive().max(100_000).nullable(),
  /** Prix encaissé en FCFA. null = formule pas encore achetable. */
  priceXof: z.number().int().min(100).max(10_000_000).nullable(),
  badge: z.string().trim().max(40).nullable(),
  tagline: z.string().trim().max(140),
  /** Formule proposée à la vente. */
  enabled: z.boolean(),
  /** Plan récurrent Flutterwave correspondant à ce prix (renouvellement automatique par carte). */
  flutterwavePlanId: z.string().trim().max(40).nullable(),
});

export const SETTINGS_SCHEMAS = {
  plans: z.object({ monthly: planSettingsSchema, quarterly: planSettingsSchema, annual: planSettingsSchema }),
  pricing: z.object({
    /** Les montants FCFA ont été validés par Victor (obligatoire pour encaisser en mode réel). */
    validated: z.boolean(),
    validatedAt: z.string().nullable(),
    validatedBy: z.string().nullable(),
  }),
  schedule: z.object({
    days: z
      .array(
        z.object({
          day: z.enum(WEEK_DAYS.map((d) => d.day) as [WeekDay, ...WeekDay[]]),
          /** Horaire libre (ex : « 20h00 – 22h00 »). null = à venir. */
          time: z.string().trim().max(60).nullable(),
        }),
      )
      .min(1)
      .max(7),
    format: z.string().trim().max(80),
    note: z.string().trim().max(240).nullable(),
  }),
  telegram: z.object({
    url: z
      .string()
      .trim()
      .url()
      .regex(/^https:\/\/t\.me\//, "Le lien doit commencer par https://t.me/")
      .nullable(),
    /** public : visible sur l'accueil et par tous ; members : réservé aux membres actifs (espace membre, messages). */
    visibility: z.enum(["public", "members"]),
  }),
  discordSync: z.object({
    /**
     * observe : rien n'est modifié sur Discord (rôles, expulsions, messages privés) ; les actions sont simulées et journalisées.
     * live : les rôles et messages sont appliqués réellement.
     */
    mode: z.enum(["observe", "live"]),
    /** Comptes de test pour lesquels les actions sont réelles, même en mode observation. */
    testUserIds: z.array(z.string().regex(/^\d{17,20}$/)).max(50),
  }),
};

export type SettingKey = keyof typeof SETTINGS_SCHEMAS;
export type Settings = { [K in SettingKey]: z.infer<(typeof SETTINGS_SCHEMAS)[K]> };
export type PlanSettings = z.infer<typeof planSettingsSchema>;

export const DEFAULT_SETTINGS: Settings = {
  plans: {
    // Prix en dollars repris des affiches ; prix FCFA à saisir et valider dans le tableau de bord.
    monthly: { priceUsd: 85, priceXof: null, badge: null, tagline: "Pour découvrir le club", enabled: true, flutterwavePlanId: null },
    quarterly: { priceUsd: 200, priceXof: null, badge: "Le + avantageux", tagline: "3 mois de pratique en direct", enabled: true, flutterwavePlanId: null },
    annual: { priceUsd: 900, priceXof: null, badge: null, tagline: "Une année complète avec le club", enabled: true, flutterwavePlanId: null },
  },
  pricing: { validated: false, validatedAt: null, validatedBy: null },
  schedule: {
    days: [
      { day: "MAR", time: null },
      { day: "MER", time: null },
      { day: "VEN", time: null },
    ],
    format: "Live · Q&A · Débrief",
    note: null,
  },
  // Lien fourni par TELEGRAM_INVITE_URL au premier démarrage (jamais écrit dans le code : le dépôt peut être public).
  telegram: { url: null, visibility: "public" },
  discordSync: { mode: "observe", testUserIds: [] },
};

// ─── Lecture (avec cache court) ─────────────────────────────────────────────

const CACHE_MS = Number(process.env.SETTINGS_CACHE_MS ?? 10_000);

declare global {
  // Partagé par tout le processus : Next.js peut charger ce module plusieurs fois (une copie par route),
  // et une modification enregistrée depuis /admin doit vider le cache lu par toutes les pages.
  var __vkSettingsCache: WeakMap<object, { at: number; value: Settings }> | undefined;
}
const cache = (globalThis.__vkSettingsCache ??= new WeakMap());

export function clearSettingsCache(db: Db): void {
  cache.delete(db);
}

/** Tous les réglages (valeurs en base fusionnées avec les valeurs par défaut). */
export async function getSettings(db: Db): Promise<Settings> {
  const hit = cache.get(db);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.value;
  const rows = await db.select().from(settingsTable);
  const value = structuredClone(DEFAULT_SETTINGS) as Settings;
  for (const row of rows) {
    const key = row.key as SettingKey;
    const schema = SETTINGS_SCHEMAS[key];
    if (!schema) continue;
    const parsed = schema.safeParse(row.value);
    if (parsed.success) (value as Record<string, unknown>)[key] = parsed.data;
  }
  cache.set(db, { at: Date.now(), value });
  return value;
}

// ─── Valeurs initiales depuis l'environnement ───────────────────────────────

/**
 * Au démarrage : si le lien Telegram n'a jamais été enregistré, on reprend TELEGRAM_INVITE_URL.
 * Ensuite, seul le tableau de bord fait foi (la variable n'écrase jamais un réglage existant).
 */
export async function seedSettingsFromEnv(db: Db, env: { TELEGRAM_INVITE_URL?: string }): Promise<void> {
  if (!env.TELEGRAM_INVITE_URL) return;
  const parsed = SETTINGS_SCHEMAS.telegram.safeParse({ url: env.TELEGRAM_INVITE_URL, visibility: "public" });
  if (!parsed.success) return;
  const inserted = await db
    .insert(settingsTable)
    .values({ key: "telegram", value: parsed.data, updatedBy: "env:TELEGRAM_INVITE_URL" })
    .onConflictDoNothing({ target: settingsTable.key })
    .returning({ key: settingsTable.key });
  if (inserted.length) clearSettingsCache(db);
}

// ─── Écriture (validée et journalisée) ──────────────────────────────────────

export async function updateSetting<K extends SettingKey>(
  db: Db,
  key: K,
  input: unknown,
  actorId: string,
  now: Date = new Date(),
): Promise<Settings[K]> {
  const parsed = SETTINGS_SCHEMAS[key].safeParse(input);
  if (!parsed.success) {
    throw new DomainError("invalid_setting", parsed.error.issues.map((i) => `${i.path.join(".") || key} : ${i.message}`).join(" ; "));
  }
  const before = (await getSettings(db))[key];
  await db
    .insert(settingsTable)
    .values({ key, value: parsed.data as object, updatedAt: now, updatedBy: actorId })
    .onConflictDoUpdate({ target: settingsTable.key, set: { value: parsed.data as object, updatedAt: now, updatedBy: actorId } });
  clearSettingsCache(db);
  await audit(db, { actorType: "admin", actorId, action: `settings.${key}.updated`, details: { before, after: parsed.data } }, now);
  return parsed.data as Settings[K];
}

/**
 * Met à jour les formules. Si un prix FCFA change :
 *  - le plan Flutterwave associé est détaché (il garde l'ancien montant) ;
 *  - la validation des tarifs est annulée (à revalider).
 */
export async function updatePlans(db: Db, input: Settings["plans"], actorId: string, now: Date = new Date()) {
  const current = (await getSettings(db)).plans;
  const next = structuredClone(input);
  let priceChanged = false;
  for (const id of PLAN_IDS) {
    if (current[id].priceXof !== next[id].priceXof) {
      priceChanged = true;
      if (current[id].flutterwavePlanId && next[id].flutterwavePlanId === current[id].flutterwavePlanId) next[id].flutterwavePlanId = null;
    }
  }
  const saved = await updateSetting(db, "plans", next, actorId, now);
  if (priceChanged && (await getSettings(db)).pricing.validated) {
    await updateSetting(db, "pricing", { validated: false, validatedAt: null, validatedBy: null }, actorId, now);
  }
  return saved;
}

/** Validation explicite des tarifs par Victor. */
export async function validatePricing(db: Db, actorId: string, now: Date = new Date()) {
  const { plans } = await getSettings(db);
  const missing = PLAN_IDS.filter((id) => plans[id].enabled && plans[id].priceXof === null);
  if (missing.length) {
    throw new DomainError("prices_missing", `Prix FCFA manquant pour : ${missing.map((id) => PLANS[id].label).join(", ")}`);
  }
  return updateSetting(db, "pricing", { validated: true, validatedAt: now.toISOString(), validatedBy: actorId }, actorId, now);
}

// ─── Catalogue des formules ─────────────────────────────────────────────────

export interface CatalogPlan extends PlanDefinition, PlanSettings {
  /** Proposée et achetable (activée + prix FCFA défini). */
  purchasable: boolean;
}

export interface Catalog {
  plans: Record<PlanId, CatalogPlan>;
  list: CatalogPlan[];
  pricesValidated: boolean;
}

export async function getCatalog(db: Db): Promise<Catalog> {
  const s = await getSettings(db);
  const plans = {} as Record<PlanId, CatalogPlan>;
  for (const id of PLAN_IDS) {
    const conf = s.plans[id];
    plans[id] = { ...PLANS[id], ...conf, purchasable: conf.enabled && conf.priceXof !== null };
  }
  return { plans, list: PLAN_IDS.map((id) => plans[id]), pricesValidated: s.pricing.validated };
}

/** Réglage de rôles : l'action Discord sur cet utilisateur est-elle réelle ? */
export function isDiscordActionLive(s: Settings, discordUserId: string): boolean {
  return s.discordSync.mode === "live" || s.discordSync.testUserIds.includes(discordUserId);
}

/** Lien Telegram visible pour ce visiteur ? (null = non affiché) */
export function telegramLinkFor(s: Settings, viewer: { hasAccess: boolean }): string | null {
  if (!s.telegram.url) return null;
  if (s.telegram.visibility === "public") return s.telegram.url;
  return viewer.hasAccess ? s.telegram.url : null;
}

/** Libellé des horaires (ex : « MAR 20h00 · MER 20h00 · VEN à venir »). */
export function scheduleSummary(s: Settings): string | null {
  const withTime = s.schedule.days.filter((d) => d.time);
  if (withTime.length === 0) return null;
  return s.schedule.days.map((d) => `${WEEK_DAYS.find((w) => w.day === d.day)!.label} ${d.time ?? "(horaire à venir)"}`).join(" · ");
}

export async function setDiscordSync(db: Db, value: Settings["discordSync"], actorId: string, now: Date = new Date()) {
  return updateSetting(db, "discordSync", value, actorId, now);
}

