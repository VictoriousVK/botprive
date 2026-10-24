CREATE TYPE "public"."job_status" AS ENUM('queued', 'running', 'succeeded', 'dead');--> statement-breakpoint
CREATE TYPE "public"."payment_method" AS ENUM('card', 'mobile_money', 'manual');--> statement-breakpoint
CREATE TYPE "public"."payment_status" AS ENUM('pending', 'succeeded', 'failed', 'refunded');--> statement-breakpoint
CREATE TYPE "public"."renewal_mode" AS ENUM('auto_card', 'manual');--> statement-breakpoint
CREATE TYPE "public"."subscription_status" AS ENUM('pending_payment', 'active', 'renewal_due', 'grace_period', 'expired', 'canceled', 'refunded', 'suspended');--> statement-breakpoint
CREATE TABLE "audit_logs" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"actor_type" text NOT NULL,
	"actor_id" text,
	"action" text NOT NULL,
	"member_id" uuid,
	"details" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "jobs" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"type" text NOT NULL,
	"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"status" "job_status" DEFAULT 'queued' NOT NULL,
	"run_at" timestamp with time zone,
	"attempts" integer DEFAULT 0 NOT NULL,
	"max_attempts" integer DEFAULT 10 NOT NULL,
	"last_error" text,
	"locked_at" timestamp with time zone,
	"locked_by" text,
	"unique_key" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	CONSTRAINT "jobs_unique_key_unique" UNIQUE("unique_key")
);
--> statement-breakpoint
CREATE TABLE "members" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"discord_user_id" text NOT NULL,
	"discord_username" text,
	"email" text,
	"email_verified" boolean DEFAULT false NOT NULL,
	"name" text,
	"phone" text,
	"reconcile_exempt" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "members_discord_user_id_unique" UNIQUE("discord_user_id")
);
--> statement-breakpoint
CREATE TABLE "payments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"reference" text NOT NULL,
	"member_id" uuid NOT NULL,
	"subscription_id" uuid NOT NULL,
	"plan_id" text NOT NULL,
	"provider" text NOT NULL,
	"method" "payment_method" NOT NULL,
	"kind" text NOT NULL,
	"amount" integer NOT NULL,
	"currency" text NOT NULL,
	"status" "payment_status" DEFAULT 'pending' NOT NULL,
	"auto_renew" boolean DEFAULT false NOT NULL,
	"provider_transaction_id" text,
	"provider_checkout_id" text,
	"failure_reason" text,
	"verification" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"confirmed_at" timestamp with time zone,
	"refunded_at" timestamp with time zone,
	CONSTRAINT "payments_reference_unique" UNIQUE("reference"),
	CONSTRAINT "payments_provider_tx_unique" UNIQUE("provider","provider_transaction_id")
);
--> statement-breakpoint
CREATE TABLE "reminders" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"subscription_id" uuid NOT NULL,
	"period_end" timestamp with time zone NOT NULL,
	"offset_days" integer NOT NULL,
	"status" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "reminders_unique" UNIQUE("subscription_id","period_end","offset_days")
);
--> statement-breakpoint
CREATE TABLE "sessions" (
	"id" text PRIMARY KEY NOT NULL,
	"member_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "subscription_periods" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"subscription_id" uuid NOT NULL,
	"plan_id" text,
	"starts_at" timestamp with time zone NOT NULL,
	"ends_at" timestamp with time zone NOT NULL,
	"source" text NOT NULL,
	"payment_id" uuid,
	"days" integer,
	"created_by" text,
	"note" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "subscription_periods_payment_id_unique" UNIQUE("payment_id")
);
--> statement-breakpoint
CREATE TABLE "subscriptions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"member_id" uuid NOT NULL,
	"plan_id" text NOT NULL,
	"status" "subscription_status" NOT NULL,
	"status_reason" text,
	"status_changed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"renewal_mode" "renewal_mode" DEFAULT 'manual' NOT NULL,
	"provider" text,
	"provider_subscription_id" text,
	"provider_plan_id" text,
	"anchor_day" integer,
	"current_period_start" timestamp with time zone,
	"current_period_end" timestamp with time zone,
	"grace_ends_at" timestamp with time zone,
	"renewal_canceled_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "subscriptions_member_id_unique" UNIQUE("member_id"),
	CONSTRAINT "subscriptions_provider_sub_unique" UNIQUE("provider","provider_subscription_id")
);
--> statement-breakpoint
CREATE TABLE "webhook_events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"provider" text NOT NULL,
	"event_key" text NOT NULL,
	"event_type" text NOT NULL,
	"payload" jsonb NOT NULL,
	"status" text DEFAULT 'received' NOT NULL,
	"attempts" integer DEFAULT 1 NOT NULL,
	"error" text,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	"processed_at" timestamp with time zone,
	CONSTRAINT "webhook_events_provider_key_unique" UNIQUE("provider","event_key")
);
--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_member_id_members_id_fk" FOREIGN KEY ("member_id") REFERENCES "public"."members"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_subscription_id_subscriptions_id_fk" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "reminders" ADD CONSTRAINT "reminders_subscription_id_subscriptions_id_fk" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_member_id_members_id_fk" FOREIGN KEY ("member_id") REFERENCES "public"."members"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscription_periods" ADD CONSTRAINT "subscription_periods_subscription_id_subscriptions_id_fk" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscription_periods" ADD CONSTRAINT "subscription_periods_payment_id_payments_id_fk" FOREIGN KEY ("payment_id") REFERENCES "public"."payments"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_member_id_members_id_fk" FOREIGN KEY ("member_id") REFERENCES "public"."members"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "audit_member_idx" ON "audit_logs" USING btree ("member_id","created_at");--> statement-breakpoint
CREATE INDEX "jobs_status_run_at_idx" ON "jobs" USING btree ("status","run_at");--> statement-breakpoint
CREATE INDEX "payments_member_idx" ON "payments" USING btree ("member_id","created_at");--> statement-breakpoint
CREATE INDEX "payments_status_idx" ON "payments" USING btree ("status","created_at");--> statement-breakpoint
CREATE INDEX "payments_checkout_idx" ON "payments" USING btree ("provider","provider_checkout_id");--> statement-breakpoint
CREATE INDEX "periods_subscription_idx" ON "subscription_periods" USING btree ("subscription_id","ends_at");--> statement-breakpoint
CREATE INDEX "subscriptions_status_end_idx" ON "subscriptions" USING btree ("status","current_period_end");