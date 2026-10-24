import type { Db } from "@vk/db";
import { enqueue } from "./jobs/queue";

/*
 * Effets de bord différés : enregistrés en base dans la même transaction que le changement
 * métier, puis exécutés (et réessayés) par le worker.
 */

export type NotificationTemplate =
  | "welcome"
  | "renewed"
  | "reminder"
  | "grace_started"
  | "expired"
  | "renewal_canceled"
  | "admin_granted";

export async function notifyMember(
  db: Db,
  memberId: string,
  template: NotificationTemplate,
  data: Record<string, unknown> = {},
): Promise<void> {
  await enqueue(db, "notify_dm", { memberId, template, data });
  await enqueue(db, "notify_email", { memberId, template, data });
}

/** Message dans le salon de logs privé. */
export async function postLog(db: Db, content: string): Promise<void> {
  await enqueue(db, "discord_log", { content });
}

/** Aligne le rôle Discord du membre sur son statut d'abonnement. */
export async function requestAccessSync(db: Db, memberId: string): Promise<void> {
  await enqueue(db, "sync_access", { memberId });
}
