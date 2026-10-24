import { and, eq, inArray, isNull, lt, lte, or, sql } from "drizzle-orm";
import { jobs, type Db, type Job } from "@vk/db";

/*
 * File de tâches persistante en base (aucun setTimeout en mémoire).
 * - Réservation atomique avec FOR UPDATE SKIP LOCKED (plusieurs workers possibles).
 * - Réessais avec backoff exponentiel.
 * - Récupération des tâches verrouillées par un worker arrêté brutalement.
 */

export type JobType =
  | "sync_access"
  | "sync_access_discord"
  | "notify_dm"
  | "notify_email"
  | "discord_log"
  | "reconcile"
  | "verify_pending_payment";

export interface EnqueueOptions {
  runAt?: Date;
  maxAttempts?: number;
  /** Si fournie, la tâche n'est créée qu'une fois pour cette clé (contrainte d'unicité). */
  uniqueKey?: string;
}

const DEFAULT_MAX_ATTEMPTS: Partial<Record<JobType, number>> = {
  // Discord peut être indisponible plusieurs heures : on insiste (~ 1 jour au total).
  sync_access: 30,
  sync_access_discord: 30,
  discord_log: 20,
  notify_dm: 8,
  notify_email: 8,
  reconcile: 5,
  verify_pending_payment: 10,
};

export async function enqueue(
  db: Db,
  type: JobType,
  payload: Record<string, unknown>,
  options: EnqueueOptions = {},
): Promise<number | null> {
  const rows = await db
    .insert(jobs)
    .values({
      type,
      payload,
      runAt: options.runAt ?? null,
      maxAttempts: options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS[type] ?? 10,
      uniqueKey: options.uniqueKey ?? null,
    })
    .onConflictDoNothing({ target: jobs.uniqueKey })
    .returning({ id: jobs.id });
  return rows[0]?.id ?? null;
}

/** Réserve jusqu'à `limit` tâches prêtes. */
export async function claimJobs(db: Db, workerId: string, limit: number, now: Date): Promise<Job[]> {
  const ready = db
    .select({ id: jobs.id })
    .from(jobs)
    .where(and(eq(jobs.status, "queued"), or(isNull(jobs.runAt), lte(jobs.runAt, now))))
    .orderBy(sql`${jobs.runAt} asc nulls first`, jobs.id)
    .limit(limit)
    .for("update", { skipLocked: true });

  return db
    .update(jobs)
    .set({
      status: "running",
      lockedAt: now,
      lockedBy: workerId,
      attempts: sql`${jobs.attempts} + 1`,
      updatedAt: now,
    })
    .where(inArray(jobs.id, ready))
    .returning();
}

export async function completeJob(db: Db, jobId: number, now: Date): Promise<void> {
  await db
    .update(jobs)
    .set({ status: "succeeded", completedAt: now, updatedAt: now, lockedAt: null, lockedBy: null })
    .where(eq(jobs.id, jobId));
}

/** Délai avant le prochain essai : 15 s, 30 s, 1 min… plafonné à 1 h. */
export function backoffMs(attempts: number): number {
  return Math.min(15_000 * 2 ** Math.max(0, attempts - 1), 60 * 60 * 1000);
}

export interface FailOutcome {
  dead: boolean;
  nextRunAt?: Date;
}

export async function failJob(
  db: Db,
  job: Job,
  error: unknown,
  now: Date,
  options: { retryable?: boolean } = {},
): Promise<FailOutcome> {
  const message = error instanceof Error ? error.message : String(error);
  const retryable = options.retryable ?? true;
  if (!retryable || job.attempts >= job.maxAttempts) {
    await db
      .update(jobs)
      .set({ status: "dead", lastError: message, updatedAt: now, lockedAt: null, lockedBy: null, completedAt: now })
      .where(eq(jobs.id, job.id));
    return { dead: true };
  }
  const nextRunAt = new Date(now.getTime() + backoffMs(job.attempts));
  await db
    .update(jobs)
    .set({ status: "queued", lastError: message, runAt: nextRunAt, updatedAt: now, lockedAt: null, lockedBy: null })
    .where(eq(jobs.id, job.id));
  return { dead: false, nextRunAt };
}

/**
 * Remet en file les tâches restées « running » au-delà de `staleAfterMs`
 * (worker arrêté ou redémarré pendant l'exécution).
 */
export async function recoverStaleJobs(db: Db, now: Date, staleAfterMs = 10 * 60 * 1000): Promise<number> {
  const rows = await db
    .update(jobs)
    .set({
      status: "queued",
      lockedAt: null,
      lockedBy: null,
      runAt: now,
      updatedAt: now,
      lastError: "Verrou expiré : worker arrêté pendant l'exécution, tâche relancée",
    })
    .where(and(eq(jobs.status, "running"), lt(jobs.lockedAt, new Date(now.getTime() - staleAfterMs))))
    .returning({ id: jobs.id });
  return rows.length;
}
