import type { Db, Job } from "@vk/db";
import { claimJobs, completeJob, failJob } from "./queue";
import type { Logger } from "../logger";

export type JobHandler = (payload: Record<string, unknown>, ctx: { job: Job; now: Date }) => Promise<void>;

/** Erreur définitive : la tâche n'est pas réessayée. */
export class PermanentJobError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PermanentJobError";
  }
}

export interface JobRunnerOptions {
  workerId: string;
  concurrency?: number;
  pollIntervalMs?: number;
  now?: () => Date;
  logger: Logger;
  onDead?: (job: Job, error: unknown) => Promise<void> | void;
}

export class JobRunner {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private stopping = false;
  private inFlight: Promise<number> | null = null;

  constructor(
    private readonly db: Db,
    private readonly handlers: Record<string, JobHandler>,
    private readonly options: JobRunnerOptions,
  ) {}

  private now(): Date {
    return this.options.now ? this.options.now() : new Date();
  }

  /** Traite un lot de tâches prêtes. Retourne le nombre de tâches traitées. */
  async runOnce(): Promise<number> {
    const now = this.now();
    const batch = await claimJobs(this.db, this.options.workerId, this.options.concurrency ?? 4, now);
    await Promise.all(batch.map((job) => this.execute(job)));
    return batch.length;
  }

  /** Vide la file (utile pour les tests et la simulation). */
  async drain(maxRounds = 50): Promise<number> {
    let total = 0;
    for (let i = 0; i < maxRounds; i++) {
      const n = await this.runOnce();
      total += n;
      if (n === 0) break;
    }
    return total;
  }

  private async execute(job: Job): Promise<void> {
    const handler = this.handlers[job.type];
    const log = this.options.logger;
    if (!handler) {
      await failJob(this.db, job, new Error(`Aucun gestionnaire pour la tâche « ${job.type} »`), this.now(), {
        retryable: false,
      });
      return;
    }
    try {
      await handler(job.payload as Record<string, unknown>, { job, now: this.now() });
      await completeJob(this.db, job.id, this.now());
    } catch (error) {
      const retryable = !(error instanceof PermanentJobError);
      const outcome = await failJob(this.db, job, error, this.now(), { retryable });
      const message = error instanceof Error ? error.message : String(error);
      if (outcome.dead) {
        log.error(`Tâche ${job.type}#${job.id} abandonnée après ${job.attempts} essai(s) : ${message}`);
        await this.options.onDead?.(job, error);
      } else {
        log.warn(
          `Tâche ${job.type}#${job.id} en échec (essai ${job.attempts}/${job.maxAttempts}), nouvel essai à ${outcome.nextRunAt?.toISOString()} : ${message}`,
        );
      }
    }
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    const loop = async () => {
      if (this.stopping) return;
      try {
        this.inFlight = this.runOnce();
        const n = await this.inFlight;
        this.inFlight = null;
        // S'il restait du travail, on enchaîne immédiatement.
        this.timer = setTimeout(loop, n > 0 ? 0 : this.options.pollIntervalMs ?? 2000);
      } catch (error) {
        this.inFlight = null;
        this.options.logger.error(`Boucle de tâches : ${error instanceof Error ? error.message : String(error)}`);
        this.timer = setTimeout(loop, 5000);
      }
    };
    void loop();
  }

  /** Arrêt propre : n'accepte plus de tâches et attend celles en cours. */
  async stop(): Promise<void> {
    this.stopping = true;
    if (this.timer) clearTimeout(this.timer);
    if (this.inFlight) await this.inFlight.catch(() => 0);
    this.running = false;
  }
}
