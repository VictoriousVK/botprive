import {
  adminGrant,
  adminSuspend,
  DomainError,
  formatDate,
  formatXof,
  getMemberOverview,
  getPlan,
  getStats,
  isPlanId,
  listExpiring,
  PLANS,
  STATUS_LABELS,
  type PlanId,
  type SubscriptionStatus,
  type WorkerDeps,
} from "@vk/core";

/*
 * Logique des commandes admin, indépendante de discord.js (testable).
 * Le contrôle du rôle admin est fait avant l'appel (voir bot.ts).
 */

export type AdminCommand =
  | { name: "abonne"; userId: string }
  | { name: "ajouter"; userId: string; username?: string; days?: number; planId?: string; note?: string }
  | { name: "retirer"; userId: string; reason?: string }
  | { name: "expirations"; days: number }
  | { name: "stats" };

const label = (status: string | null | undefined) => (status ? STATUS_LABELS[status as SubscriptionStatus] ?? status : "aucun abonnement");

export async function runAdminCommand(deps: WorkerDeps, invokerId: string, command: AdminCommand): Promise<string> {
  try {
    switch (command.name) {
      case "abonne": {
        const overview = await getMemberOverview(deps.db, command.userId);
        if (!overview) return `<@${command.userId}> n'est pas enregistré (aucune inscription ni paiement).`;
        const { member, subscription: sub, lastPayments } = overview;
        const lines = [
          `**Fiche de <@${member.discordUserId}>**${member.name ? ` · ${member.name}` : ""}`,
          `Statut : **${label(sub?.status)}**`,
        ];
        if (sub) {
          lines.push(`Formule : ${isPlanId(sub.planId) ? getPlan(sub.planId).label : sub.planId}`);
          if (sub.currentPeriodEnd) lines.push(`Fin de période : ${formatDate(sub.currentPeriodEnd)}${sub.status === "grace_period" && sub.graceEndsAt ? ` (grâce jusqu'au ${formatDate(sub.graceEndsAt)})` : ""}`);
          lines.push(`Renouvellement : ${sub.renewalMode === "auto_card" ? `automatique par carte (${sub.provider})` : "manuel (rappels)"}`);
        }
        lines.push(`Email : ${member.email ?? "—"} · Téléphone : ${member.phone ?? "—"}`);
        if (lastPayments.length) {
          lines.push("Derniers paiements :");
          for (const p of lastPayments) {
            lines.push(`• ${formatDate(p.createdAt)} · ${formatXof(p.amount)} · ${p.provider}/${p.method} · ${p.status} · \`${p.reference}\``);
          }
        }
        return lines.join("\n");
      }
      case "ajouter": {
        if (command.planId && !isPlanId(command.planId)) return `Formule inconnue : ${command.planId}`;
        if (!command.planId && !command.days) return "Indique `jours` ou `formule`.";
        const sub = await adminGrant(deps, {
          discordUserId: command.userId,
          username: command.username,
          days: command.days,
          planId: command.planId as PlanId | undefined,
          adminId: invokerId,
          note: command.note,
        });
        const what = command.planId ? `formule ${PLANS[command.planId as PlanId].label}` : `${command.days} jour(s)`;
        return `✅ <@${command.userId}> : ${what} ajouté(s). Accès jusqu'au **${formatDate(sub.currentPeriodEnd!)}**. Le rôle est attribué dans quelques secondes.`;
      }
      case "retirer": {
        await adminSuspend(deps, { discordUserId: command.userId, adminId: invokerId, reason: command.reason });
        return `🚫 Accès de <@${command.userId}> suspendu. Le rôle est retiré dans quelques secondes. (\`/ajouter\` pour le rétablir.)`;
      }
      case "expirations": {
        const rows = await listExpiring(deps.db, deps.now(), command.days);
        if (rows.length === 0) return `Aucune échéance dans les ${command.days} prochains jours.`;
        const lines = [`**${rows.length} échéance(s) dans les ${command.days} prochains jours**`];
        for (const r of rows.slice(0, 40)) {
          lines.push(`• <@${r.discordUserId}> · ${formatDate(r.currentPeriodEnd!)} · ${label(r.status)} · ${r.renewalMode === "auto_card" ? "auto carte" : "manuel"}`);
        }
        if (rows.length > 40) lines.push(`… et ${rows.length - 40} autre(s).`);
        return lines.join("\n");
      }
      case "stats": {
        const s = await getStats(deps.db, deps.now());
        const statusLine = Object.entries(s.byStatus)
          .map(([k, v]) => `${label(k)} : ${v}`)
          .join(" · ");
        return [
          `**Live Club : chiffres clés**`,
          `Membres avec accès : **${s.withAccess}** (dont ${s.autoRenew} en prélèvement auto)`,
          `Répartition : ${statusLine || "—"}`,
          `Encaissé sur 30 jours : **${formatXof(s.revenue30d)}** (${s.payments30d} paiement(s))`,
          `Échéances des 30 prochains jours : ${formatXof(s.forecast30d)} (prévisionnel)`,
        ].join("\n");
      }
    }
  } catch (error) {
    if (error instanceof DomainError) return `⚠️ ${error.message}`;
    throw error;
  }
}
