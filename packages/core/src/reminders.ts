import { and, gt, inArray, lte } from "drizzle-orm";
import { reminders, subscriptions } from "@vk/db";
import { CLUB } from "./config/club";
import { addDays, reminderDueAt } from "./dates";
import type { CoreDeps } from "./deps";
import { notifyMember } from "./outbox";

/*
 * Rappels avant échéance (J-3, J-1, J0 par défaut, configurables dans club.ts).
 * - Un rappel n'est envoyé qu'une fois par période (contrainte d'unicité).
 * - Si plusieurs rappels sont dus en même temps (worker arrêté, abonné tardif), seul le plus
 *   proche de l'échéance est envoyé ; les autres sont marqués « skipped ».
 * - Le contenu dépend du mode : prélèvement carte actif = simple avis, sans lien de paiement.
 * - Aucun rappel pour un renouvellement annulé.
 */
export async function processReminders(deps: Pick<CoreDeps, "db" | "now">): Promise<number> {
  const now = deps.now();
  const offsets = [...CLUB.reminderOffsetsDays].sort((a, b) => b - a);
  if (offsets.length === 0) return 0;
  const horizon = addDays(now, offsets[0]! + 1);

  const candidates = await deps.db
    .select()
    .from(subscriptions)
    .where(
      and(
        inArray(subscriptions.status, ["active", "renewal_due"]),
        gt(subscriptions.currentPeriodEnd, now),
        lte(subscriptions.currentPeriodEnd, horizon),
      ),
    );

  let sent = 0;
  for (const sub of candidates) {
    const periodEnd = sub.currentPeriodEnd!;
    const due = offsets.filter((o) => now.getTime() >= reminderDueAt(periodEnd, o).getTime());
    if (due.length === 0) continue;
    const latest = Math.min(...due);
    const didSend = await deps.db.transaction(async (tx) => {
      const inserted = await tx
        .insert(reminders)
        .values(due.map((offsetDays) => ({ subscriptionId: sub.id, periodEnd, offsetDays, status: offsetDays === latest ? "sent" : "skipped", createdAt: now })))
        .onConflictDoNothing()
        .returning({ offsetDays: reminders.offsetDays });
      if (!inserted.some((r) => r.offsetDays === latest)) return false;
      await notifyMember(tx, sub.memberId, "reminder", { periodEnd: periodEnd.toISOString(), offsetDays: latest });
      return true;
    });
    if (didSend) sent++;
  }
  return sent;
}
