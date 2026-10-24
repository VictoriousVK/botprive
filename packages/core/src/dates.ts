import { CLUB } from "./config/club";

/*
 * Calcul des périodes d'abonnement.
 *
 * Tout est calculé côté serveur et stocké en UTC. Africa/Dakar étant UTC+0 sans heure d'été,
 * le jour calendaire UTC correspond au jour calendaire à Dakar : les opérations se font donc
 * sur les composantes UTC.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

export function daysInMonthUtc(year: number, monthIndex: number): number {
  return new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
}

/**
 * Ajoute `months` mois en visant le jour d'ancrage `anchorDay`.
 * Si ce jour n'existe pas dans le mois cible, on prend le dernier jour du mois :
 * 31 janv. → 28/29 févr. → 31 mars (l'ancrage est retrouvé le mois suivant).
 */
export function addMonthsAnchored(from: Date, months: number, anchorDay: number): Date {
  const total = from.getUTCMonth() + months;
  const year = from.getUTCFullYear() + Math.floor(total / 12);
  const month = ((total % 12) + 12) % 12;
  const day = Math.min(anchorDay, daysInMonthUtc(year, month));
  return new Date(
    Date.UTC(
      year,
      month,
      day,
      from.getUTCHours(),
      from.getUTCMinutes(),
      from.getUTCSeconds(),
      from.getUTCMilliseconds(),
    ),
  );
}

export function addDays(from: Date, days: number): Date {
  return new Date(from.getTime() + days * DAY_MS);
}

export function addMinutes(from: Date, minutes: number): Date {
  return new Date(from.getTime() + minutes * 60_000);
}

export interface PeriodContext {
  status: string;
  currentPeriodEnd: Date | null;
  anchorDay: number | null;
}

export interface ComputedPeriod {
  start: Date;
  end: Date;
  anchorDay: number;
  /** true si la période prolonge la précédente (renouvellement anticipé ou en grâce). */
  continued: boolean;
}

/** Statuts pour lesquels un paiement prolonge la période en cours plutôt que de repartir de zéro. */
const CONTINUABLE = new Set(["active", "renewal_due", "grace_period", "canceled", "suspended"]);

function canContinue(ctx: PeriodContext, now: Date, graceDays: number): ctx is PeriodContext & { currentPeriodEnd: Date } {
  if (!ctx.currentPeriodEnd || !CONTINUABLE.has(ctx.status)) return false;
  // Période en cours ou terminée depuis moins que le délai de grâce : on part de sa fin.
  return now.getTime() < addDays(ctx.currentPeriodEnd, graceDays).getTime();
}

/**
 * Nouvelle période payée pour une formule de `months` mois.
 * - Renouvellement anticipé : la période part de la fin de la période en cours (aucun jour perdu).
 * - Paiement pendant la grâce : la période part de la fin de la période échue (ancrage conservé).
 * - Sinon (nouvel abonné, expiré) : la période part du paiement, nouveau jour d'ancrage.
 */
export function computePaidPeriod(
  ctx: PeriodContext,
  months: number,
  now: Date,
  graceDays: number = CLUB.graceDays,
): ComputedPeriod {
  if (canContinue(ctx, now, graceDays)) {
    const start = ctx.currentPeriodEnd;
    const anchorDay = ctx.anchorDay ?? start.getUTCDate();
    return { start, end: addMonthsAnchored(start, months, anchorDay), anchorDay, continued: true };
  }
  const anchorDay = now.getUTCDate();
  return { start: now, end: addMonthsAnchored(now, months, anchorDay), anchorDay, continued: false };
}

/**
 * Jours offerts par l'admin (/ajouter). Le jour d'ancrage suit la nouvelle date de fin,
 * pour que le renouvellement mensuel suivant dure bien un mois.
 */
export function computeGrantedPeriod(
  ctx: PeriodContext,
  days: number,
  now: Date,
  graceDays: number = CLUB.graceDays,
): ComputedPeriod {
  const continued = canContinue(ctx, now, graceDays);
  const start = continued ? ctx.currentPeriodEnd! : now;
  const end = addDays(start, days);
  return { start, end, anchorDay: end.getUTCDate(), continued };
}

export function graceEnd(periodEnd: Date, graceDays: number = CLUB.graceDays): Date {
  return addDays(periodEnd, graceDays);
}

/**
 * Moment d'envoi d'un rappel J-`offsetDays` : à `hourLocal` heures (Dakar) le jour concerné,
 * sans jamais dépasser l'échéance elle-même (J0 envoyé au plus tard 1 h avant).
 */
export function reminderDueAt(periodEnd: Date, offsetDays: number, hourLocal: number = CLUB.reminderHourLocal): Date {
  const day = addDays(periodEnd, -offsetDays);
  const at = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), hourLocal, 0, 0, 0));
  const latest = new Date(periodEnd.getTime() - 60 * 60 * 1000);
  return at.getTime() > latest.getTime() ? latest : at;
}

const dateFormatter = new Intl.DateTimeFormat("fr-FR", {
  timeZone: CLUB.timezone,
  day: "numeric",
  month: "long",
  year: "numeric",
});

const dateTimeFormatter = new Intl.DateTimeFormat("fr-FR", {
  timeZone: CLUB.timezone,
  day: "numeric",
  month: "long",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

/** « 12 décembre 2026 » (fuseau Africa/Dakar). */
export function formatDate(date: Date): string {
  return dateFormatter.format(date);
}

/** « 12 décembre 2026 à 14:30 » (fuseau Africa/Dakar). */
export function formatDateTime(date: Date): string {
  return dateTimeFormatter.format(date);
}

export function daysBetween(from: Date, to: Date): number {
  return Math.ceil((to.getTime() - from.getTime()) / DAY_MS);
}

export function formatXof(amount: number): string {
  return `${new Intl.NumberFormat("fr-FR").format(amount).replace(/ | /g, " ")} FCFA`;
}
