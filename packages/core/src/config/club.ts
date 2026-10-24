/**
 * FICHIER DE CONFIGURATION UNIQUE DU CLUB.
 *
 * Tarifs, durées, libellés, délai de grâce et rappels se modifient ICI et nulle part ailleurs.
 * Les secrets et identifiants (Discord, prestataires) vont dans le fichier .env.
 *
 * ⚠️ Valeurs « À CONFIRMER » : prix FCFA proposés à titre indicatif (≈ 575 FCFA/$), à fixer par Victor.
 */

export type PlanId = "monthly" | "quarterly" | "annual";

export interface Plan {
  id: PlanId;
  /** Libellé affiché (site, messages, Discord). */
  label: string;
  /** Durée en mois calendaires (le jour d'ancrage est conservé). */
  months: number;
  /** Prix affiché en dollars (vitrine uniquement, jamais encaissé). */
  priceUsd: number;
  /** Prix encaissé en FCFA (XOF). Fixe, jamais converti à la volée. */
  priceXof: number;
  badge?: string;
  tagline: string;
}

export const PLANS: Record<PlanId, Plan> = {
  monthly: {
    id: "monthly",
    label: "Mensuel",
    months: 1,
    priceUsd: 85,
    priceXof: 50_000, // À CONFIRMER
    tagline: "Pour découvrir le club",
  },
  quarterly: {
    id: "quarterly",
    label: "Trimestriel",
    months: 3,
    priceUsd: 200,
    priceXof: 115_000, // À CONFIRMER
    badge: "Le + avantageux",
    tagline: "3 mois de pratique en direct",
  },
  annual: {
    id: "annual",
    label: "Annuel",
    months: 12,
    // ⚠️ À REVOIR : 900 $ > 4 × 200 $ (trimestriel). Prix repris des affiches en attendant ta décision.
    priceUsd: 900,
    priceXof: 520_000, // À CONFIRMER
    tagline: "Une année complète avec le club",
  },
};

export const PLAN_IDS = Object.keys(PLANS) as PlanId[];

export function getPlan(id: string): Plan {
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
  schedule: [
    { day: "MAR", label: "Mardi" },
    { day: "MER", label: "Mercredi" },
    { day: "VEN", label: "Vendredi" },
  ],
  /** Horaires des lives : à compléter (affichés sur le site et dans les rappels). */
  liveHours: null as string | null,
  /** Numéro WhatsApp affiché (celui de l'affiche Live Club). À CONFIRMER. */
  whatsappNumber: "+221764139946",
  whatsappDisplay: "+221 76 413 99 46",
  quote: "C'est par la pratique que la théorie devient réalité.",
  signatures: ["Discipline · Analyse · Résultats", "Ensemble vers la liberté financière"],
} as const;

export type ExpiryAction = "remove_role" | "kick";
