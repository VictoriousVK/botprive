import { eq, inArray } from "drizzle-orm";
import { members, subscriptionPeriods, subscriptions } from "@vk/db";
import { audit } from "./audit";
import { getPlan, type PlanId } from "./config/club";
import { addDays, addMonthsAnchored, formatDate, graceEnd } from "./dates";
import type { CoreDeps } from "./deps";
import { postLog, requestAccessSync } from "./outbox";
import { STATUS_LABELS, statusAfterReactivation, type SubscriptionStatus } from "./state-machine";
import { RENEWAL_WINDOW_DAYS, upsertMember } from "./subscriptions/service";

/*
 * Import des membres existants (CSV : discord_user_id, nom, email, téléphone, formule, date_de_fin).
 * Ils ne repaient pas : leur période actuelle est reprise telle quelle.
 *  1. previewImport : vérifie chaque ligne sans rien écrire (format, doublons, dates, présence Discord).
 *  2. importMembers : importe les lignes valides. Idempotent (un membre déjà présent avec une période est ignoré).
 * L'import ne modifie pas directement Discord : les rôles suivent le mode choisi dans le tableau de bord
 * (en mode observation, rien n'est changé sur le serveur).
 */

export interface ImportRow {
  discord_user_id?: string;
  nom?: string;
  email?: string;
  telephone?: string;
  formule?: string;
  date_de_fin?: string;
}

export type DiscordPresence = "present" | "absent" | "unverified";

export interface ImportPreviewRow {
  line: number;
  discordUserId: string;
  name: string | null;
  email: string | null;
  phone: string | null;
  planId: PlanId | null;
  endDate: Date | null;
  /** ok : importable · warning : importable, à vérifier · error : rejetée · skip : déjà présent, ignorée */
  level: "ok" | "warning" | "error" | "skip";
  messages: string[];
  discord: DiscordPresence;
  resultingStatus: SubscriptionStatus | null;
}

export interface ImportPreview {
  rows: ImportPreviewRow[];
  summary: { total: number; importable: number; warnings: number; errors: number; skipped: number };
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

/** En-têtes CSV tolérants : « Téléphone », « date de fin » → telephone, date_de_fin. */
export function normalizeHeader(header: string): string {
  return header.trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\s+/g, "_");
}

export const IMPORT_TEMPLATE_CSV =
  "discord_user_id,nom,email,téléphone,formule,date_de_fin\n" +
  "123456789012345678,Awa Diop,awa@exemple.sn,+221770000001,Mensuel,2026-11-30\n" +
  "234567890123456789,Moussa Ndiaye,,+221770000002,Trimestriel,15/01/2027\n";

function statusFor(end: Date, now: Date): SubscriptionStatus {
  return statusAfterReactivation({ status: "active", currentPeriodEnd: end, graceEndsAt: graceEnd(end) }, now, RENEWAL_WINDOW_DAYS);
}

/** Vérifie chaque ligne sans rien écrire. checkDiscord (optionnel) contrôle la présence sur le serveur. */
export async function previewImport(
  deps: Pick<CoreDeps, "db" | "now">,
  rows: ImportRow[],
  options: { checkDiscord?: (discordUserId: string) => Promise<DiscordPresence>; maxDiscordChecks?: number } = {},
): Promise<ImportPreview> {
  const now = deps.now();
  const seen = new Set<string>();
  const ids = rows.map((r) => (r.discord_user_id ?? "").trim()).filter((id) => /^\d{17,20}$/.test(id));
  const existing = ids.length
    ? await deps.db
        .select({ discordUserId: members.discordUserId, end: subscriptions.currentPeriodEnd, status: subscriptions.status })
        .from(members)
        .leftJoin(subscriptions, eq(subscriptions.memberId, members.id))
        .where(inArray(members.discordUserId, ids))
    : [];
  const existingById = new Map(existing.map((e) => [e.discordUserId, e]));
  let discordChecks = 0;

  const out: ImportPreviewRow[] = [];
  for (const [index, row] of rows.entries()) {
    const line = index + 2; // ligne 1 = en-tête
    const discordUserId = (row.discord_user_id ?? "").trim();
    const r: ImportPreviewRow = {
      line,
      discordUserId,
      name: row.nom?.trim() || null,
      email: (row.email ?? "").trim() || null,
      phone: (row.telephone ?? "").trim() || null,
      planId: normalizePlan(row.formule),
      endDate: parseEndDate(row.date_de_fin),
      level: "ok",
      messages: [],
      discord: "unverified",
      resultingStatus: null,
    };
    const error = (m: string) => {
      r.level = "error";
      r.messages.push(m);
    };
    const warn = (m: string) => {
      if (r.level === "ok") r.level = "warning";
      r.messages.push(m);
    };

    if (!/^\d{17,20}$/.test(discordUserId)) error(`identifiant Discord invalide « ${discordUserId} » (17 à 20 chiffres attendus)`);
    else if (seen.has(discordUserId)) error("identifiant Discord en double dans le fichier");
    seen.add(discordUserId);
    if (!r.planId) error(`formule inconnue « ${row.formule ?? ""} » (mensuel, trimestriel ou annuel)`);
    if (!r.endDate) error(`date de fin invalide « ${row.date_de_fin ?? ""} » (AAAA-MM-JJ ou JJ/MM/AAAA)`);
    if (r.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(r.email)) error(`email invalide « ${r.email} »`);
    if (r.phone && !/^\+?[0-9 ()-]{6,20}$/.test(r.phone)) warn(`téléphone au format inhabituel « ${r.phone} »`);
    if (!r.email) warn("pas d'email : rappels par message Discord uniquement");

    if (r.level !== "error") {
      const end = r.endDate!;
      r.resultingStatus = statusFor(end, now);
      if (r.resultingStatus === "expired") warn(`date de fin passée : importé comme expiré (aucun accès)`);
      if (r.resultingStatus === "grace_period") warn(`échéance dépassée : importé en période de grâce jusqu'au ${formatDate(graceEnd(end))}`);
      if (r.planId && end.getTime() > addDays(now, getPlan(r.planId).months * 31 + 31).getTime()) {
        warn(`date de fin lointaine pour une formule ${getPlan(r.planId).label.toLowerCase()} : à vérifier`);
      }
      const known = existingById.get(discordUserId);
      if (known?.end) {
        r.level = "skip";
        r.messages = [`déjà enregistré (${STATUS_LABELS[known.status as SubscriptionStatus] ?? known.status}, fin le ${formatDate(known.end)}) : ligne ignorée`];
      }
      if (r.level !== "skip" && options.checkDiscord && discordChecks < (options.maxDiscordChecks ?? 500)) {
        discordChecks++;
        r.discord = await options.checkDiscord(discordUserId);
        if (r.discord === "absent") warn("absent du serveur Discord : le rôle sera attribué à son arrivée");
      }
    }
    out.push(r);
  }

  return {
    rows: out,
    summary: {
      total: out.length,
      importable: out.filter((r) => r.level === "ok" || r.level === "warning").length,
      warnings: out.filter((r) => r.level === "warning").length,
      errors: out.filter((r) => r.level === "error").length,
      skipped: out.filter((r) => r.level === "skip").length,
    },
  };
}

export async function importMembers(
  deps: Pick<CoreDeps, "db" | "now">,
  rows: ImportRow[],
  options: { dryRun?: boolean; adminId?: string } = {},
): Promise<ImportReport> {
  const now = deps.now();
  const preview = await previewImport(deps, rows);
  const report: ImportReport = {
    created: 0,
    skipped: preview.summary.skipped,
    errors: preview.rows.filter((r) => r.level === "error").map((r) => ({ line: r.line, message: r.messages.join(" ; ") })),
  };
  const importable = preview.rows.filter((r) => r.level === "ok" || r.level === "warning");
  if (options.dryRun) {
    report.created = importable.length;
    return report;
  }

  for (const r of importable) {
    const created = await deps.db.transaction(async (tx) => {
      const member = await upsertMember(tx, { discordUserId: r.discordUserId, name: r.name, email: r.email, phone: r.phone }, now);
      const [existing] = await tx.select().from(subscriptions).where(eq(subscriptions.memberId, member.id)).for("update");
      if (existing?.currentPeriodEnd) return false; // importé entre-temps
      const plan = getPlan(r.planId!);
      const end = r.endDate!;
      const start = addMonthsAnchored(end, -plan.months, end.getUTCDate());
      const status = statusFor(end, now);
      const values = {
        planId: plan.id,
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
      await tx.insert(subscriptionPeriods).values({ subscriptionId, planId: plan.id, startsAt: start, endsAt: end, source: "import", createdBy: options.adminId ?? "import", createdAt: now });
      await audit(tx, { actorType: "admin", actorId: options.adminId ?? "import", action: "member.imported", memberId: member.id, details: { planId: plan.id, end: end.toISOString(), status } }, now);
      await requestAccessSync(tx, member.id);
      return true;
    });
    if (created) report.created++;
    else report.skipped++;
  }

  if (report.created > 0) {
    await postLog(deps.db, `📥 Import CSV : ${report.created} membre(s) importé(s), ${report.skipped} déjà présent(s), ${report.errors.length} ligne(s) rejetée(s).`);
  }
  return report;
}
