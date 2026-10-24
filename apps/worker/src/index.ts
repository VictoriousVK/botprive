import os from "node:os";
import { REST } from "discord.js";
import {
  consoleLogger,
  createEmailSender,
  createJobHandlers,
  createProviderRegistry,
  getSettings,
  JobRunner,
  seedSettingsFromEnv,
  loadEnv,
  postLog,
  purgeExpiredSessions,
  required,
  runScheduledTick,
  type WorkerDeps,
} from "@vk/core";
import { createDb, runMigrations } from "@vk/db";
import { createBot } from "./bot";
import { RestDiscordGateway } from "./discord-gateway";

/*
 * Process permanent : bot Discord + exécution des tâches + passages planifiés.
 * Tout l'état est en base : on peut l'arrêter et le relancer à tout moment.
 */

const logger = consoleLogger;
const env = loadEnv();
const databaseUrl = required(env, "DATABASE_URL");

if (process.env.RUN_MIGRATIONS !== "false") {
  await runMigrations(databaseUrl);
  logger.info("Migrations à jour");
}

const { db, close } = createDb(databaseUrl);
await seedSettingsFromEnv(db, env);
const token = required(env, "DISCORD_BOT_TOKEN");
const guildId = required(env, "DISCORD_GUILD_ID");
const rest = new REST({ version: "10" }).setToken(token);

const deps: WorkerDeps = {
  db,
  env,
  now: () => new Date(),
  logger,
  providers: createProviderRegistry(env, undefined, logger),
  discord: new RestDiscordGateway(rest, guildId, env.DISCORD_LOG_CHANNEL_ID),
  email: createEmailSender(env, logger),
  policy: {
    memberRoleId: required(env, "DISCORD_MEMBER_ROLE_ID"),
    exemptUserIds: env.DISCORD_EXEMPT_USER_IDS,
    exemptRoleIds: [...env.DISCORD_EXEMPT_ROLE_IDS, ...(env.DISCORD_ADMIN_ROLE_ID ? [env.DISCORD_ADMIN_ROLE_ID] : [])],
    expiryAction: env.EXPIRY_ACTION,
  },
};

const runner = new JobRunner(db, createJobHandlers(deps), {
  workerId: `${os.hostname()}-${process.pid}`,
  concurrency: 4,
  pollIntervalMs: 2000,
  logger,
  async onDead(job, error) {
    if (job.type === "discord_log") return; // éviter une boucle si le salon de logs est inaccessible
    await postLog(db, `❌ Tâche \`${job.type}\` #${job.id} abandonnée après ${job.attempts} essais : ${error instanceof Error ? error.message : String(error)}`);
  },
});

let ticking = false;
async function tick() {
  if (ticking) return;
  ticking = true;
  try {
    await runScheduledTick(deps);
    await purgeExpiredSessions(db, new Date());
  } catch (error) {
    logger.error(`Passage planifié en erreur : ${error instanceof Error ? error.message : String(error)}`);
  } finally {
    ticking = false;
  }
}

const bot = createBot(deps, { token, guildId, adminRoleId: required(env, "DISCORD_ADMIN_ROLE_ID") }, logger);

runner.start();
await tick();
const interval = setInterval(tick, 60_000);
try {
  await bot.login(token);
} catch (error) {
  // L'hébergeur relance le process ; les tâches en attente sont conservées en base.
  logger.error(`Connexion à Discord impossible (token, intents ou réseau ?) : ${error instanceof Error ? error.message : String(error)}`);
  await runner.stop();
  await close();
  process.exit(1);
}
{
  const settings = await getSettings(db);
  const modes = [
    `paiements : ${env.PAYMENT_MODE === "live" ? "RÉELS" : "mode test (aucun encaissement réel)"}`,
    `Discord : ${settings.discordSync.mode === "live" ? "rôles appliqués" : `🧪 observation (aucun rôle modifié${settings.discordSync.testUserIds.length ? `, sauf ${settings.discordSync.testUserIds.length} compte(s) de test` : ""})`}`,
    ...deps.providers.disabled.map((d) => `⚠️ ${d.id} écarté : ${d.reason}`),
  ];
  if (env.PAYMENT_MODE === "live" && settings.discordSync.mode === "observe") {
    modes.push("⚠️ Paiements réels mais rôles en observation : les nouveaux abonnés ne recevront pas leur rôle.");
  }
  await postLog(db, `🟢 Worker démarré · ${modes.join(" · ")}`);
}
logger.info("Worker démarré");

let stopping = false;
async function shutdown(signal: string) {
  if (stopping) return;
  stopping = true;
  logger.info(`${signal} reçu : arrêt propre…`);
  clearInterval(interval);
  await runner.stop();
  await bot.destroy();
  await close();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
