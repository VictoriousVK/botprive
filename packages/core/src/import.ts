import { eq } from "drizzle-orm";
import { subscriptionPeriods, subscriptions } from "@vk/db";
import { audit } from "./audit";
import { getPlan, type PlanId } from "./config/club";
import { addMonthsAnchored, graceEnd } from "./dates";
import type { CoreDeps } from "./deps";
import { postLog, requestAccessSync } from "./outbox";
import { statusAfterReactivation } from "./state-machine";
import { getSubscriptionForMember, RENEWAL_WINDOW_DAYS, upsertMember } from "./subscriptions/service";

/*
 * Import des membres existants (CSV : discord_user_id, nom, email, téléphone, formule, date_de_fin).
 * Ils ne repaient pas : leur période actuelle est reprise telle quelle. Idempotent : un membre
 * déjà présent avec une période n'est pas modifié.
 */

export interface ImportRow {
  discord_user_id?: string;
  nom?: string;
  email?: string;
  telephone?: string;
  formule?: string;
  date_de_fin?: string;
}

export interface ImportReport {
  created: number;
  skipped: number;
  errors: { line: number; message: string }[];
}

const PLAN_ALIASES: Record<string, PlanId> = {
  mensuel: "monthly",
  monthly: "monthly",
  mois: "monthly",
  "1 mois": "monthly",
  trimestriel: "quarterly",
  quarterly: "quarterly",
  "3 mois": "quarterly",
  annuel: "annual",
  annual: "annual",
  "12 mois": "annual",
};

export function normalizePlan(value: string | undefined): PlanId | null {
  const key = (value ?? "").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  return PLAN_ALIASES[key] ?? null;
}

/** « 2026-12-12 » ou « 12/12/2026 » → fin de journée à Dakar (23:59:59 UTC). */
export function parseEndDate(value: string | undefined): Date | null {
  const v = (value ?? "").trim();
  let y: number, m: number, d: number;
  let match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  if (match) {
    [y, m, d] = [Number(match[1]), Number(match[2]), Number(match[3])];
  } else if ((match = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(v))) {
    [d, m, y] = [Number(match[1]), Number(match[2]), Number(match[3])];
  } else {
    return null;
  }
  const date = new Date(Date.UTC(y, m - 1, d, 23, 59, 59));
  return date.getUTCMonth() === m - 1 && date.getUTCDate() === d ? date : null;
}

export async function importMembers(
  deps: Pick<CoreDeps, "db" | "now">,
  rows: ImportRow[],
  options: { dryRun?: boolean; adminId?: string } = {},
): Promise<ImportReport> {
  const now = deps.now();
  const report: ImportReport = { created: 0, skipped: 0, errors: [] };
  const seen = new Set<string>();

  for (const [index, row] of rows.entries()) {
    const line = index + 2; // ligne 1 = en-tête
    const discordUserId = (row.discord_user_id ?? "").trim();
    if (!/^\d{17,20}$/.test(discordUserId)) {
      report.errors.push({ line, message: `discord_user_id invalide « ${discordUserId} » (17 à 20 chiffres attendus)` });
      continue;
    }
    if (seen.has(discordUserId)) {
      report.errors.push({ line, message: `discord_user_id en double dans le fichier` });
      continue;
    }
    seen.add(discordUserId);
    const planId = normalizePlan(row.formule);
    if (!planId) {
      report.errors.push({ line, message: `formule inconnue « ${row.formule ?? ""} » (mensuel, trimestriel, annuel)` });
      continue;
    }
    const end = parseEndDate(row.date_de_fin);
    if (!end) {
      report.errors.push({ line, message: `date_de_fin invalide « ${row.date_de_fin ?? ""} » (AAAA-MM-JJ ou JJ/MM/AAAA)` });
      continue;
    }
    const email = (row.email ?? "").trim() || null;
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      report.errors.push({ line, message: `email invalide « ${email} »` });
      continue;
    }
    if (options.dryRun) {
      report.created++;
      continue;
    }

    const created = await deps.db.transaction(async (tx) => {
      const member = await upsertMember(tx, { discordUserId, name: row.nom?.trim() || null, email, phone: row.telephone?.trim() || null }, now);
      const existing = await getSubscriptionForMember(tx, member.id);
      if (existing?.currentPeriodEnd) return false;
      const plan = getPlan(planId);
      const start = addMonthsAnchored(end, -plan.months, end.getUTCDate());
      const status = statusAfterReactivation({ status: "active", currentPeriodEnd: end, graceEndsAt: graceEnd(end) }, now, RENEWAL_WINDOW_DAYS);
      const values = {
        planId,
        status,
        statusReason: "import CSV",
        statusChangedAt: now,
        renewalMode: "manual" as const,
        anchorDay: end.getUTCDate(),
        currentPeriodStart: start,
        currentPeriodEnd: end,
        graceEndsAt: graceEnd(end),
        updatedAt: now,
      };
      let subscriptionId: string;
      if (existing) {
        await tx.update(subscriptions).set(values).where(eq(subscriptions.id, existing.id));
        subscriptionId = existing.id;
      } else {
        const [sub] = await tx.insert(subscriptions).values({ ...values, memberId: member.id, createdAt: now }).returning({ id: subscriptions.id });
        subscriptionId = sub!.id;
      }
      await tx.insert(subscriptionPeriods).values({ subscriptionId, planId, startsAt: start, endsAt: end, source: "import", createdBy: options.adminId ?? "import", createdAt: now });
      await audit(tx, { actorType: "admin", actorId: options.adminId ?? "import", action: "member.imported", memberId: member.id, details: { planId, end: end.toISOString(), status } }, now);
      await requestAccessSync(tx, member.id);
      return true;
    });
    if (created) report.created++;
    else report.skipped++;
  }

  if (!options.dryRun && report.created > 0) {
    await postLog(deps.db, `📥 Import CSV : ${report.created} membre(s) importé(s), ${report.skipped} déjà présent(s), ${report.errors.length} erreur(s).`);
  }
  return report;
}
