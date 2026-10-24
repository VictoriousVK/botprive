import { eq } from "drizzle-orm";
import { members, subscriptions, type Db, type Member } from "@vk/db";
import { audit } from "../audit";
import type { ExpiryAction } from "../config/club";
import { postLog } from "../outbox";
import { getSettings, isDiscordActionLive } from "../settings";
import { hasAccess, type SubscriptionStatus } from "../state-machine";

export interface GuildMemberInfo {
  userId: string;
  roles: string[];
  username?: string;
  isBot?: boolean;
}

/**
 * Accès au serveur Discord. Les erreurs transitoires (réseau, 5xx, 429) lèvent
 * ExternalServiceError(transient) : la tâche est réessayée plus tard.
 */
export interface DiscordGateway {
  /** null si l'utilisateur n'est pas sur le serveur. */
  getMember(userId: string): Promise<GuildMemberInfo | null>;
  listMembers(): Promise<GuildMemberInfo[]>;
  addRole(userId: string, roleId: string, reason: string): Promise<void>;
  removeRole(userId: string, roleId: string, reason: string): Promise<void>;
  kick(userId: string, reason: string): Promise<void>;
  /** « blocked » : le membre n'accepte pas les messages privés. */
  sendDm(userId: string, content: string): Promise<"sent" | "blocked">;
  postLog(content: string): Promise<void>;
}

export interface AccessPolicy {
  memberRoleId: string;
  /** Membres et rôles jamais touchés par l'automatisation (admins, modérateurs, invités spéciaux). */
  exemptUserIds: string[];
  exemptRoleIds: string[];
  expiryAction: ExpiryAction;
}

export function isExempt(policy: AccessPolicy, guildMember: GuildMemberInfo | null, member?: Pick<Member, "reconcileExempt"> | null): boolean {
  if (member?.reconcileExempt) return true;
  if (!guildMember) return false;
  if (guildMember.isBot) return true;
  if (policy.exemptUserIds.includes(guildMember.userId)) return true;
  return guildMember.roles.some((r) => policy.exemptRoleIds.includes(r));
}

export type SyncResult =
  | "granted"
  | "revoked"
  | "kicked"
  | "unchanged"
  | "not_in_guild"
  | "exempt"
  | "unknown_member"
  /** Mode observation : le changement aurait eu lieu, rien n'a été modifié sur Discord. */
  | "simulated_grant"
  | "simulated_revoke";

interface SyncCtx {
  db: Db;
  discord: DiscordGateway;
  policy: AccessPolicy;
  now: () => Date;
}

/**
 * Aligne le rôle Discord sur l'état en base (« état désiré ») : idempotent,
 * insensible à l'ordre des événements, rejouable autant de fois que nécessaire.
 */
export async function syncMemberAccess(ctx: SyncCtx, memberId: string, options: { quiet?: boolean } = {}): Promise<SyncResult> {
  const [row] = await ctx.db
    .select({ member: members, status: subscriptions.status })
    .from(members)
    .leftJoin(subscriptions, eq(subscriptions.memberId, members.id))
    .where(eq(members.id, memberId));
  if (!row) return "unknown_member";
  const { member } = row;
  const status = row.status as SubscriptionStatus | null;

  const guildMember = await ctx.discord.getMember(member.discordUserId);
  if (!guildMember) return "not_in_guild";
  if (isExempt(ctx.policy, guildMember, member)) return "exempt";

  const hasRole = guildMember.roles.includes(ctx.policy.memberRoleId);
  const shouldHaveRole = hasAccess(status);
  const now = ctx.now();

  // Mode observation (réglage du tableau de bord) : aucune modification réelle, sauf comptes de test.
  if (shouldHaveRole !== hasRole && !isDiscordActionLive(await getSettings(ctx.db), member.discordUserId)) {
    const action = shouldHaveRole ? "attribué" : "retiré";
    await audit(ctx.db, { actorType: "system", action: shouldHaveRole ? "discord.role_grant_simulated" : "discord.role_revoke_simulated", memberId, details: { status } }, now);
    if (!options.quiet) {
      await postLog(ctx.db, `🧪 Mode observation : le rôle abonné serait ${action} à <@${member.discordUserId}> (${status ?? "aucun abonnement"}). Aucun changement réel.`);
    }
    return shouldHaveRole ? "simulated_grant" : "simulated_revoke";
  }

  if (shouldHaveRole && !hasRole) {
    await ctx.discord.addRole(member.discordUserId, ctx.policy.memberRoleId, "Abonnement actif");
    await audit(ctx.db, { actorType: "system", action: "discord.role_granted", memberId, details: { status } }, now);
    await postLog(ctx.db, `🎟️ Rôle abonné attribué à <@${member.discordUserId}>`);
    return "granted";
  }
  if (!shouldHaveRole && hasRole) {
    if (ctx.policy.expiryAction === "kick" && status === "expired") {
      await ctx.discord.kick(member.discordUserId, "Abonnement expiré");
      await audit(ctx.db, { actorType: "system", action: "discord.kicked", memberId, details: { status } }, now);
      await postLog(ctx.db, `👢 <@${member.discordUserId}> expulsé (abonnement expiré)`);
      return "kicked";
    }
    await ctx.discord.removeRole(member.discordUserId, ctx.policy.memberRoleId, `Accès terminé (${status ?? "aucun abonnement"})`);
    await audit(ctx.db, { actorType: "system", action: "discord.role_removed", memberId, details: { status } }, now);
    await postLog(ctx.db, `🔒 Rôle abonné retiré à <@${member.discordUserId}> (${status ?? "aucun abonnement"})`);
    return "revoked";
  }
  return "unchanged";
}
