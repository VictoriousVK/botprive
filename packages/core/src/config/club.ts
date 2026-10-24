/**
 * CONFIGURATION FIXE DU CLUB (structure, règles).
 *
 * Les valeurs modifiables sans toucher au code sont dans le tableau de bord (/admin) :
 * prix des formules, horaires des lives, lien Telegram, mode d'application des rôles Discord.
 * Leurs valeurs par défaut sont dans settings.ts. Les secrets vont dans .env.
 */

export type PlanId = "monthly" | "quarterly" | "annual";

/** Structure d'une formule. Les prix et textes sont des réglages (tableau de bord). */
export interface PlanDefinition {
  id: PlanId;
  /** Libellé affiché (site, messages, Discord). */
  label: string;
  /** Durée en mois calendaires (le jour d'ancrage est conservé). */
  months: number;
}

export const PLANS: Record<PlanId, PlanDefinition> = {
  monthly: { id: "monthly", label: "Mensuel", months: 1 },
  quarterly: { id: "quarterly", label: "Trimestriel", months: 3 },
  annual: { id: "annual", label: "Annuel", months: 12 },
};

export const PLAN_IDS = Object.keys(PLANS) as PlanId[];

export function getPlan(id: string): PlanDefinition {
  const plan = PLANS[id as PlanId];
  if (!plan) throw new Error(`Formule inconnue : ${id}`);
  return plan;
}

export function isPlanId(id: string): id is PlanId {
  return id in PLANS;
}

export const CLUB = {
  name: "V_ICT_ORIOUS Live Club",
  currency: "XOF" as const,
  /**
   * Fuseau d'affichage. Africa/Dakar = UTC+0 toute l'année (pas d'heure d'été) :
   * le jour calendaire UTC est donc le jour calendaire à Dakar. Les calculs de dates s'appuient dessus.
   */
  timezone: "Africa/Dakar",
  /** Délai de grâce après la fin de période, accès conservé. */
  graceDays: 3,
  /** Rappels avant l'échéance, en jours (J-3, J-1, J0). */
  reminderOffsetsDays: [3, 1, 0],
  /** Heure (Dakar) d'envoi des rappels. */
  reminderHourLocal: 9,
  /** Un paiement en attente est re-vérifié auprès du prestataire après ce délai (webhook perdu). */
  pendingPaymentReverifyAfterMinutes: 20,
  /** Au-delà, un paiement en attente est considéré comme abandonné. */
  pendingPaymentAbandonAfterHours: 48,
  /** Heure UTC de la réconciliation quotidienne. */
  reconciliationHourUtc: 4,
  /** Durée de validité des liens de renouvellement envoyés dans les rappels. */
  renewalLinkValidityDays: 10,
  launchDate: "2026-10-26",
  /** Numéro WhatsApp affiché (celui de l'affiche Live Club). À CONFIRMER. */
  whatsappNumber: "+221764139946",
  whatsappDisplay: "+221 76 413 99 46",
  quote: "C'est par la pratique que la théorie devient réalité.",
  signatures: ["Discipline · Analyse · Résultats", "Ensemble vers la liberté financière"],
} as const;

export const WEEK_DAYS = [
  { day: "LUN", label: "Lundi" },
  { day: "MAR", label: "Mardi" },
  { day: "MER", label: "Mercredi" },
  { day: "JEU", label: "Jeudi" },
  { day: "VEN", label: "Vendredi" },
  { day: "SAM", label: "Samedi" },
  { day: "DIM", label: "Dimanche" },
] as const;

export type WeekDay = (typeof WEEK_DAYS)[number]["day"];

export type ExpiryAction = "remove_role" | "kick";
