import { and, eq, gt, lt } from "drizzle-orm";
import { members, sessions, type Db, type Member } from "@vk/db";
import { addDays } from "./dates";
import { newSessionToken, sessionIdFromToken } from "./tokens";

export const SESSION_DAYS = 30;

export async function createSession(db: Db, memberId: string, now: Date): Promise<{ token: string; expiresAt: Date }> {
  const { token, id } = newSessionToken();
  const expiresAt = addDays(now, SESSION_DAYS);
  await db.insert(sessions).values({ id, memberId, createdAt: now, expiresAt });
  return { token, expiresAt };
}

/** Membre associé au cookie de session, ou null (jeton inconnu ou expiré). */
export async function getSessionMember(db: Db, token: string | undefined | null, now: Date): Promise<Member | null> {
  if (!token || token.length > 200) return null;
  const [row] = await db
    .select({ member: members })
    .from(sessions)
    .innerJoin(members, eq(members.id, sessions.memberId))
    .where(and(eq(sessions.id, sessionIdFromToken(token)), gt(sessions.expiresAt, now)));
  return row?.member ?? null;
}

export async function deleteSession(db: Db, token: string): Promise<void> {
  await db.delete(sessions).where(eq(sessions.id, sessionIdFromToken(token)));
}

export async function purgeExpiredSessions(db: Db, now: Date): Promise<void> {
  await db.delete(sessions).where(lt(sessions.expiresAt, addDays(now, -1)));
}
