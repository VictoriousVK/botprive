import { z } from "zod";
import type { ExpiryAction } from "./club";

const csv = z
  .string()
  .optional()
  .transform((v) =>
    (v ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  );

const optional = z
  .string()
  .optional()
  .transform((v) => (v && v.trim() !== "" ? v.trim() : undefined));

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  APP_URL: z.string().url().default("http://localhost:3000"),
  DATABASE_URL: optional,
  SESSION_SECRET: optional,

  DISCORD_CLIENT_ID: optional,
  DISCORD_CLIENT_SECRET: optional,
  DISCORD_BOT_TOKEN: optional,
  DISCORD_GUILD_ID: optional,
  DISCORD_MEMBER_ROLE_ID: optional,
  DISCORD_ADMIN_ROLE_ID: optional,
  DISCORD_LOG_CHANNEL_ID: optional,
  DISCORD_EXEMPT_USER_IDS: csv,
  DISCORD_EXEMPT_ROLE_IDS: csv,
  DISCORD_INVITE_URL: z.string().url().default("https://discord.gg/SMFqgxbb6"),
  DISCORD_API_BASE_URL: z.string().url().default("https://discord.com/api/v10"),
  EXPIRY_ACTION: z.enum(["remove_role", "kick"]).default("remove_role"),

  TELEGRAM_INVITE_URL: optional,

  PAYMENT_PROVIDER_CARD: z.enum(["flutterwave", "none"]).default("flutterwave"),
  PAYMENT_PROVIDER_MOBILE_MONEY: z.enum(["wave", "flutterwave", "none"]).default("flutterwave"),

  FLW_SECRET_KEY: optional,
  FLW_WEBHOOK_HASH: optional,
  FLW_API_BASE_URL: z.string().url().default("https://api.flutterwave.com"),
  FLW_MOBILE_MONEY_OPTION: z.string().default("mobilemoneyfranco"),
  FLW_PLAN_ID_MONTHLY: optional,
  FLW_PLAN_ID_QUARTERLY: optional,
  FLW_PLAN_ID_ANNUAL: optional,

  WAVE_API_KEY: optional,
  WAVE_WEBHOOK_SECRET: optional,
  WAVE_API_BASE_URL: z.string().url().default("https://api.wave.com"),

  EMAIL_PROVIDER: z.enum(["resend", "console"]).default("console"),
  RESEND_API_KEY: optional,
  EMAIL_FROM: z.string().default("V_ICT_ORIOUS Live Club <onboarding@resend.dev>"),
  EMAIL_REPLY_TO: optional,
});

export type RawEnv = z.infer<typeof envSchema>;

export interface AppEnv extends RawEnv {
  EXPIRY_ACTION: ExpiryAction;
}

export function loadEnv(source: Record<string, string | undefined> = process.env): AppEnv {
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("\n");
    throw new Error(`Configuration .env invalide :\n${issues}`);
  }
  const env = parsed.data;
  if (env.NODE_ENV === "production") {
    if (!env.SESSION_SECRET || env.SESSION_SECRET.length < 32) {
      throw new Error("SESSION_SECRET doit faire au moins 32 caractères en production");
    }
  }
  return env;
}

/** Récupère une variable obligatoire pour le composant qui l'utilise, avec un message clair. */
export function required<K extends keyof AppEnv>(env: AppEnv, key: K): NonNullable<AppEnv[K]> {
  const value = env[key];
  if (value === undefined || value === null || value === "") {
    throw new Error(`Variable d'environnement manquante : ${String(key)} (à définir dans .env)`);
  }
  return value as NonNullable<AppEnv[K]>;
}
