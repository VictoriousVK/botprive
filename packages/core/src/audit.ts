import { auditLogs, type Db } from "@vk/db";

export type ActorType = "system" | "admin" | "member" | "provider";

export interface AuditEntry {
  actorType: ActorType;
  actorId?: string | null;
  action: string;
  memberId?: string | null;
  details?: Record<string, unknown>;
}

/** Journal d'audit en base. Ne jamais y mettre de secret, de jeton ou de numéro de carte. */
export async function audit(db: Db, entry: AuditEntry, now: Date = new Date()): Promise<void> {
  await db.insert(auditLogs).values({
    actorType: entry.actorType,
    actorId: entry.actorId ?? null,
    action: entry.action,
    memberId: entry.memberId ?? null,
    details: entry.details ?? null,
    createdAt: now,
  });
}
