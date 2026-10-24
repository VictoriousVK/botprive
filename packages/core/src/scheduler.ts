import { CLUB } from "./config/club";
import type { CoreDeps } from "./deps";
import { enqueue, recoverStaleJobs } from "./jobs/queue";
import { processReminders } from "./reminders";
import { applyTimeTransitions, type TimeTransitionChange } from "./subscriptions/service";

export interface TickReport {
  recoveredJobs: number;
  transitions: TimeTransitionChange[];
  remindersSent: number;
  reconciliationScheduled: boolean;
}

/**
 * Passage périodique du worker (chaque minute). Tout est calculé depuis l'état en base :
 * après un redémarrage, le premier passage rattrape les échéances manquées.
 */
export async function runScheduledTick(deps: Pick<CoreDeps, "db" | "now" | "logger">): Promise<TickReport> {
  const now = deps.now();
  const recoveredJobs = await recoverStaleJobs(deps.db, now);
  const transitions = await applyTimeTransitions(deps);
  const remindersSent = await processReminders(deps);
  let reconciliationScheduled = false;
  if (now.getUTCHours() >= CLUB.reconciliationHourUtc) {
    const day = now.toISOString().slice(0, 10);
    reconciliationScheduled = (await enqueue(deps.db, "reconcile", {}, { uniqueKey: `reconcile:${day}`, runAt: now })) !== null;
  }
  if (recoveredJobs || transitions.length || remindersSent || reconciliationScheduled) {
    deps.logger.info(
      `Passage planifié : ${transitions.length} transition(s), ${remindersSent} rappel(s), ${recoveredJobs} tâche(s) récupérée(s)${reconciliationScheduled ? ", réconciliation programmée" : ""}`,
    );
  }
  return { recoveredJobs, transitions, remindersSent, reconciliationScheduled };
}
