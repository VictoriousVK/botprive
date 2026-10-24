import { eq } from "drizzle-orm";
import { members, subscriptions } from "@vk/db";
import { audit } from "./audit";
import { CLUB, getPlan, WEEK_DAYS } from "./config/club";
import { addMinutes } from "./dates";
import { syncMemberAccess } from "./discord/access";
import { enqueue, type JobType } from "./jobs/queue";
import type { JobHandler } from "./jobs/runner";
import { renderNotification, type TemplateContext } from "./notifications/templates";
import type { NotificationTemplate } from "./outbox";
import { reverifyPendingPayment } from "./payments/webhooks";
import { reconcile, type WorkerDeps } from "./reconciliation";
import { getCatalog, getSettings, isDiscordActionLive, scheduleSummary, telegramLinkFor } from "./settings";
import { hasAccess, type SubscriptionStatus } from "./state-machine";
import { findMemberByDiscordId } from "./subscriptions/service";
import { createRenewalToken, signingSecret } from "./tokens";

interface NotifyPayload {
  memberId: string;
  template: NotificationTemplate;
  data?: { periodEnd?: string; offsetDays?: number };
}

/** Construit le contexte d'un message au moment de l'envoi, ou null s'il n'est plus pertinent. */
async function buildContext(deps: WorkerDeps, payload: NotifyPayload) {
  const [row] = await deps.db
    .select({ member: members, sub: subscriptions })
    .from(members)
    .leftJoin(subscriptions, eq(subscriptions.memberId, members.id))
    .where(eq(members.id, payload.memberId));
  if (!row?.sub) return null;
  const { member, sub } = row;
  const status = sub.status as SubscriptionStatus;
  const now = deps.now();

  // Un message programmé peut être devenu caduc (membre renouvelé entre-temps…).
  if (payload.template === "reminder") {
    if (!["active", "renewal_due"].includes(status)) return null;
    if (payload.data?.periodEnd && sub.currentPeriodEnd?.toISOString() !== payload.data.periodEnd) return null;
  }
  if (payload.template === "grace_started" && status !== "grace_period") return null;
  if (payload.template === "expired" && status !== "expired") return null;

  const plan = getPlan(sub.planId);
  const settings = await getSettings(deps.db);
  const catalogPlan = (await getCatalog(deps.db)).plans[plan.id];
  const appUrl = deps.env.APP_URL.replace(/\/$/, "");
  const token = createRenewalToken(signingSecret(deps.env), member.id, plan.id, now, CLUB.renewalLinkValidityDays);
  const ctx: TemplateContext = {
    memberName: member.name ?? member.discordUsername ?? "membre",
    planLabel: plan.label,
    priceXof: sub.renewalMode === "auto_card" && sub.recurringAmount ? sub.recurringAmount : catalogPlan.priceXof,
    liveSchedule: scheduleSummary(settings),
    scheduleDays: settings.schedule.days.map((d) => WEEK_DAYS.find((w) => w.day === d.day)!.label.toLowerCase()).join(", "),
    autoRenewActive: sub.renewalMode === "auto_card" && status !== "canceled",
    periodEnd: payload.data?.periodEnd ? new Date(payload.data.periodEnd) : sub.currentPeriodEnd,
    graceEndsAt: sub.graceEndsAt,
    renewalUrl: `${appUrl}/r/${token}`,
    accountUrl: `${appUrl}/espace`,
    inviteUrl: deps.env.DISCORD_INVITE_URL,
    telegramUrl: telegramLinkFor(settings, { hasAccess: hasAccess(status) }) ?? undefined,
    now,
  };
  // Mode observation : aucun message réel aux membres (sauf comptes de test).
  const live = isDiscordActionLive(settings, member.discordUserId);
  return { member, live, rendered: renderNotification(payload.template, ctx) };
}

/** Délais successifs de re-vérification d'un paiement en attente. */
const REVERIFY_DELAYS_MIN = [60, 6 * 60, 24 * 60];

export function createJobHandlers(deps: WorkerDeps): Record<JobType, JobHandler> {
  const syncCtx = { db: deps.db, discord: deps.discord, policy: deps.policy, now: deps.now };
  return {
    async sync_access(payload) {
      await syncMemberAccess(syncCtx, String(payload.memberId));
    },
    async sync_access_discord(payload) {
      const member = await findMemberByDiscordId(deps.db, String(payload.discordUserId));
      if (member) await syncMemberAccess(syncCtx, member.id);
    },
    async notify_dm(payload) {
      const built = await buildContext(deps, payload as unknown as NotifyPayload);
      if (!built?.rendered) return;
      if (!built.live) {
        await audit(deps.db, { actorType: "system", action: "notify.dm_simulated", memberId: built.member.id, details: { template: payload.template } }, deps.now());
        return;
      }
      const result = await deps.discord.sendDm(built.member.discordUserId, built.rendered.dm);
      if (result === "blocked") {
        await audit(deps.db, { actorType: "system", action: "notify.dm_blocked", memberId: built.member.id, details: { template: payload.template } }, deps.now());
      }
    },
    async notify_email(payload) {
      const built = await buildContext(deps, payload as unknown as NotifyPayload);
      if (!built?.rendered || !built.member.email) return;
      if (!built.live) {
        await audit(deps.db, { actorType: "system", action: "notify.email_simulated", memberId: built.member.id, details: { template: payload.template } }, deps.now());
        return;
      }
      await deps.email.send({ to: built.member.email, ...built.rendered.email });
    },
    async discord_log(payload) {
      await deps.discord.postLog(String(payload.content));
    },
    async reconcile() {
      await reconcile(deps);
    },
    async verify_pending_payment(payload) {
      const outcome = await reverifyPendingPayment(deps, String(payload.paymentId));
      if (outcome !== "pending") return;
      const round = Number(payload.round ?? 0);
      const delay = REVERIFY_DELAYS_MIN[round];
      if (delay !== undefined) {
        await enqueue(deps.db, "verify_pending_payment", { paymentId: payload.paymentId, round: round + 1 }, { runAt: addMinutes(deps.now(), delay) });
      }
    },
  };
}

