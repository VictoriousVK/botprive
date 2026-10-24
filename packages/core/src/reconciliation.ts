import { and, eq, gte, lte } from "drizzle-orm";
import { members, payments, subscriptions } from "@vk/db";
import { audit } from "./audit";
import { CLUB } from "./config/club";
import { addDays, addMinutes } from "./dates";
import type { DiscordGateway, AccessPolicy } from "./discord/access";
import { isExempt, syncMemberAccess } from "./discord/access";
import type { CoreDeps } from "./deps";
import type { EmailSender } from "./notifications/email";
import { postLog } from "./outbox";
import { reverifyPendingPayment } from "./payments/webhooks";
import { hasAccess, type SubscriptionStatus } from "./state-machine";
import { applyTimeTransitions } from "./subscriptions/service";

export interface WorkerDeps extends CoreDeps {
  discord: DiscordGateway;
  email: EmailSender;
  policy: AccessPolicy;
}

export interface ReconciliationReport {
  roleRemoved: string[];
  roleGranted: string[];
  notInGuild: string[];
  exemptSkipped: number;
  paymentsRecovered: string[];
  paymentsFailed: string[];
  errors: string[];
}

/**
 * Réconciliation quotidienne base ↔ paiements ↔ rôles Discord réels.
 * Répare ce qui est récupérable, journalise le reste, ne touche jamais aux exceptions
 * (admins, modérateurs, invités spéciaux : DISCORD_EXEMPT_USER_IDS / DISCORD_EXEMPT_ROLE_IDS).
 */
export async function reconcile(deps: WorkerDeps): Promise<ReconciliationReport> {
  const now = deps.now();
  const report: ReconciliationReport = {
    roleRemoved: [],
    roleGranted: [],
    notInGuild: [],
    exemptSkipped: 0,
    paymentsRecovered: [],
    paymentsFailed: [],
    errors: [],
  };

  // 1. Paiements restés en attente (webhook perdu) : re-vérification serveur à serveur.
  const pending = await deps.db
    .select({ id: payments.id, reference: payments.reference })
    .from(payments)
    .where(
      and(
        eq(payments.status, "pending"),
        lte(payments.createdAt, addMinutes(now, -CLUB.pendingPaymentReverifyAfterMinutes)),
        gte(payments.createdAt, addDays(now, -7)),
      ),
    );
  for (const p of pending) {
    try {
      const outcome = await reverifyPendingPayment(deps, p.id);
      if (outcome === "succeeded") report.paymentsRecovered.push(p.reference);
      if (outcome === "failed") report.paymentsFailed.push(p.reference);
    } catch (error) {
      report.errors.push(`paiement ${p.reference} : ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  // 2. Statuts à jour avant de comparer avec Discord.
  await applyTimeTransitions(deps);

  // 3. Comparaison avec les rôles réels.
  const guildMembers = await deps.discord.listMembers();
  const guildById = new Map(guildMembers.map((m) => [m.userId, m]));
  const rows = await deps.db
    .select({ member: members, status: subscriptions.status })
    .from(members)
    .leftJoin(subscriptions, eq(subscriptions.memberId, members.id));
  const dbById = new Map(rows.map((r) => [r.member.discordUserId, r]));

  const ctx = { db: deps.db, discord: deps.discord, policy: deps.policy, now: deps.now };

  // Rôle sans abonnement valide → retiré.
  for (const gm of guildMembers) {
    if (!gm.roles.includes(deps.policy.memberRoleId)) continue;
    const row = dbById.get(gm.userId);
    if (isExempt(deps.policy, gm, row?.member)) {
      report.exemptSkipped++;
      continue;
    }
    if (hasAccess(row?.status as SubscriptionStatus | null)) continue;
    try {
      if (row) {
        const result = await syncMemberAccess(ctx, row.member.id);
        if (result === "revoked" || result === "kicked") report.roleRemoved.push(gm.userId);
      } else {
        await deps.discord.removeRole(gm.userId, deps.policy.memberRoleId, "Réconciliation : aucun abonnement");
        await audit(deps.db, { actorType: "system", action: "reconcile.role_removed_unknown", details: { discordUserId: gm.userId } }, now);
        report.roleRemoved.push(gm.userId);
      }
    } catch (error) {
      report.errors.push(`retrait <@${gm.userId}> : ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  // Abonnement valide sans rôle → réparé.
  for (const row of rows) {
    if (!hasAccess(row.status as SubscriptionStatus | null)) continue;
    const gm = guildById.get(row.member.discordUserId);
    if (!gm) {
      report.notInGuild.push(row.member.discordUserId);
      continue;
    }
    if (gm.roles.includes(deps.policy.memberRoleId) || isExempt(deps.policy, gm, row.member)) continue;
    try {
      const result = await syncMemberAccess(ctx, row.member.id);
      if (result === "granted") report.roleGranted.push(row.member.discordUserId);
    } catch (error) {
      report.errors.push(`attribution <@${row.member.discordUserId}> : ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  await audit(deps.db, { actorType: "system", action: "reconcile.completed", details: { ...report } }, now);
  const list = (ids: string[]) => (ids.length ? ids.slice(0, 15).map((id) => `<@${id}>`).join(", ") + (ids.length > 15 ? "…" : "") : "aucun");
  await postLog(
    deps.db,
    [
      `🧮 **Réconciliation quotidienne**`,
      `Rôles retirés : ${report.roleRemoved.length} (${list(report.roleRemoved)})`,
      `Rôles réparés : ${report.roleGranted.length} (${list(report.roleGranted)})`,
      `Abonnés absents du serveur : ${report.notInGuild.length} (${list(report.notInGuild)})`,
      `Paiements récupérés : ${report.paymentsRecovered.length} · abandonnés : ${report.paymentsFailed.length}`,
      `Exceptions ignorées : ${report.exemptSkipped}`,
      ...(report.errors.length ? [`⚠️ Erreurs (${report.errors.length}) : ${report.errors.slice(0, 5).join(" | ")}`] : []),
    ].join("\n"),
  );
  return report;
}
