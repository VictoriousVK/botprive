import { sql } from "drizzle-orm";
import {
  bigserial,
  boolean,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  text,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";

// Toutes les dates sont stockées en UTC (timestamptz). L'affichage se fait en Africa/Dakar.
const ts = (name: string) => timestamp(name, { withTimezone: true, mode: "date" });

export const subscriptionStatusEnum = pgEnum("subscription_status", [
  "pending_payment",
  "active",
  "renewal_due",
  "grace_period",
  "expired",
  "canceled",
  "refunded",
  "suspended",
]);

export const renewalModeEnum = pgEnum("renewal_mode", ["auto_card", "manual"]);

export const paymentStatusEnum = pgEnum("payment_status", [
  "pending",
  "succeeded",
  "failed",
  "refunded",
]);

export const paymentMethodEnum = pgEnum("payment_method", ["card", "mobile_money", "manual"]);

export const jobStatusEnum = pgEnum("job_status", ["queued", "running", "succeeded", "dead"]);

export const members = pgTable("members", {
  id: uuid("id").primaryKey().defaultRandom(),
  discordUserId: text("discord_user_id").notNull().unique(),
  discordUsername: text("discord_username"),
  email: text("email"),
  emailVerified: boolean("email_verified").notNull().default(false),
  name: text("name"),
  phone: text("phone"),
  reconcileExempt: boolean("reconcile_exempt").notNull().default(false),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

// Un seul abonnement par membre : la ligne évolue dans le temps (machine à états),
// l'historique est conservé dans subscription_periods et payments.
export const subscriptions = pgTable(
  "subscriptions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    memberId: uuid("member_id")
      .notNull()
      .unique()
      .references(() => members.id, { onDelete: "restrict" }),
    planId: text("plan_id").notNull(),
    status: subscriptionStatusEnum("status").notNull(),
    statusReason: text("status_reason"),
    statusChangedAt: ts("status_changed_at").notNull().defaultNow(),
    renewalMode: renewalModeEnum("renewal_mode").notNull().default("manual"),
    provider: text("provider"),
    providerSubscriptionId: text("provider_subscription_id"),
    providerPlanId: text("provider_plan_id"),
    anchorDay: integer("anchor_day"),
    currentPeriodStart: ts("current_period_start"),
    currentPeriodEnd: ts("current_period_end"),
    graceEndsAt: ts("grace_ends_at"),
    renewalCanceledAt: ts("renewal_canceled_at"),
    // Montant prélevé par le prestataire à chaque échéance (figé à l'activation du prélèvement automatique).
    recurringAmount: integer("recurring_amount"),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
  },
  (t) => [
    unique("subscriptions_provider_sub_unique").on(t.provider, t.providerSubscriptionId),
    index("subscriptions_status_end_idx").on(t.status, t.currentPeriodEnd),
  ],
);

export const payments = pgTable(
  "payments",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    // Notre référence (tx_ref / client_reference) envoyée au prestataire.
    reference: text("reference").notNull().unique(),
    memberId: uuid("member_id")
      .notNull()
      .references(() => members.id, { onDelete: "restrict" }),
    subscriptionId: uuid("subscription_id")
      .notNull()
      .references(() => subscriptions.id, { onDelete: "restrict" }),
    planId: text("plan_id").notNull(),
    provider: text("provider").notNull(),
    method: paymentMethodEnum("method").notNull(),
    kind: text("kind").notNull(), // initial | renewal | recurring
    amount: integer("amount").notNull(), // XOF : pas de sous-unité
    currency: text("currency").notNull(),
    status: paymentStatusEnum("status").notNull().default("pending"),
    autoRenew: boolean("auto_renew").notNull().default(false),
    providerTransactionId: text("provider_transaction_id"),
    providerCheckoutId: text("provider_checkout_id"),
    failureReason: text("failure_reason"),
    verification: jsonb("verification"),
    createdAt: ts("created_at").notNull().defaultNow(),
    confirmedAt: ts("confirmed_at"),
    refundedAt: ts("refunded_at"),
  },
  (t) => [
    unique("payments_provider_tx_unique").on(t.provider, t.providerTransactionId),
    index("payments_member_idx").on(t.memberId, t.createdAt),
    index("payments_status_idx").on(t.status, t.createdAt),
    index("payments_checkout_idx").on(t.provider, t.providerCheckoutId),
  ],
);

export const subscriptionPeriods = pgTable(
  "subscription_periods",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    subscriptionId: uuid("subscription_id")
      .notNull()
      .references(() => subscriptions.id, { onDelete: "restrict" }),
    planId: text("plan_id"),
    startsAt: ts("starts_at").notNull(),
    endsAt: ts("ends_at").notNull(),
    source: text("source").notNull(), // payment | admin | import
    // Contrainte d'unicité : un paiement ne prolonge qu'une seule fois.
    paymentId: uuid("payment_id")
      .unique()
      .references(() => payments.id, { onDelete: "restrict" }),
    days: integer("days"),
    createdBy: text("created_by"),
    note: text("note"),
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [index("periods_subscription_idx").on(t.subscriptionId, t.endsAt)],
);

export const webhookEvents = pgTable(
  "webhook_events",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    provider: text("provider").notNull(),
    eventKey: text("event_key").notNull(),
    eventType: text("event_type").notNull(),
    payload: jsonb("payload").notNull(),
    status: text("status").notNull().default("received"), // received | processed | ignored | unmatched | error
    attempts: integer("attempts").notNull().default(1),
    error: text("error"),
    receivedAt: ts("received_at").notNull().defaultNow(),
    processedAt: ts("processed_at"),
  },
  (t) => [unique("webhook_events_provider_key_unique").on(t.provider, t.eventKey)],
);

// File de tâches persistante : survit aux redémarrages du worker.
export const jobs = pgTable(
  "jobs",
  {
    id: bigserial("id", { mode: "number" }).primaryKey(),
    type: text("type").notNull(),
    payload: jsonb("payload").notNull().default(sql`'{}'::jsonb`),
    status: jobStatusEnum("status").notNull().default("queued"),
    // null = dès que possible ; sinon pas avant cette date (réessai, tâche programmée).
    runAt: ts("run_at"),
    attempts: integer("attempts").notNull().default(0),
    maxAttempts: integer("max_attempts").notNull().default(10),
    lastError: text("last_error"),
    lockedAt: ts("locked_at"),
    lockedBy: text("locked_by"),
    // Clé d'unicité optionnelle pour les tâches à n'exécuter qu'une fois (ex : réconciliation du jour).
    uniqueKey: text("unique_key").unique(),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
    completedAt: ts("completed_at"),
  },
  (t) => [index("jobs_status_run_at_idx").on(t.status, t.runAt)],
);

export const reminders = pgTable(
  "reminders",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    subscriptionId: uuid("subscription_id")
      .notNull()
      .references(() => subscriptions.id, { onDelete: "cascade" }),
    periodEnd: ts("period_end").notNull(),
    offsetDays: integer("offset_days").notNull(),
    status: text("status").notNull(), // sent | skipped
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [unique("reminders_unique").on(t.subscriptionId, t.periodEnd, t.offsetDays)],
);

export const auditLogs = pgTable(
  "audit_logs",
  {
    id: bigserial("id", { mode: "number" }).primaryKey(),
    actorType: text("actor_type").notNull(), // system | admin | member | provider
    actorId: text("actor_id"),
    action: text("action").notNull(),
    memberId: uuid("member_id"),
    details: jsonb("details"),
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [index("audit_member_idx").on(t.memberId, t.createdAt)],
);

export const sessions = pgTable("sessions", {
  // SHA-256 du jeton de session : le jeton brut n'est jamais stocké.
  id: text("id").primaryKey(),
  memberId: uuid("member_id")
    .notNull()
    .references(() => members.id, { onDelete: "cascade" }),
  createdAt: ts("created_at").notNull().defaultNow(),
  expiresAt: ts("expires_at").notNull(),
});

// Réglages modifiables depuis le tableau de bord (tarifs, horaires, Telegram, mode Discord…).
export const settings = pgTable("settings", {
  key: text("key").primaryKey(),
  value: jsonb("value").notNull(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
  updatedBy: text("updated_by"),
});

export type Member = typeof members.$inferSelect;
export type Subscription = typeof subscriptions.$inferSelect;
export type Payment = typeof payments.$inferSelect;
export type SubscriptionPeriod = typeof subscriptionPeriods.$inferSelect;
export type Job = typeof jobs.$inferSelect;
export type WebhookEvent = typeof webhookEvents.$inferSelect;
