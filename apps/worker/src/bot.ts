import { Client, Events, GatewayIntentBits, MessageFlags, type ChatInputCommandInteraction } from "discord.js";
import { audit, enqueue, type Logger, type WorkerDeps } from "@vk/core";
import { runAdminCommand, type AdminCommand } from "./admin-commands";

export interface BotConfig {
  token: string;
  guildId: string;
  adminRoleId: string;
}

function hasRole(interaction: ChatInputCommandInteraction, roleId: string): boolean {
  const member = interaction.member;
  if (!member) return false;
  const roles = member.roles;
  return Array.isArray(roles) ? roles.includes(roleId) : roles.cache.has(roleId);
}

function toCommand(interaction: ChatInputCommandInteraction): AdminCommand | null {
  const user = interaction.options.getUser("membre");
  switch (interaction.commandName) {
    case "abonne":
      return user ? { name: "abonne", userId: user.id } : null;
    case "ajouter":
      return user
        ? {
            name: "ajouter",
            userId: user.id,
            username: user.username,
            days: interaction.options.getInteger("jours") ?? undefined,
            planId: interaction.options.getString("formule") ?? undefined,
            note: interaction.options.getString("note") ?? undefined,
          }
        : null;
    case "retirer":
      return user ? { name: "retirer", userId: user.id, reason: interaction.options.getString("raison") ?? undefined } : null;
    case "expirations":
      return { name: "expirations", days: interaction.options.getInteger("jours") ?? 7 };
    case "stats":
      return { name: "stats" };
    default:
      return null;
  }
}

/** Client Discord (gateway) : commandes admin et arrivée de nouveaux membres. */
export function createBot(deps: WorkerDeps, config: BotConfig, logger: Logger): Client {
  // Server Members (intent privilégié) : nécessaire pour l'événement d'arrivée et la réconciliation.
  const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers] });

  client.once(Events.ClientReady, (c) => {
    logger.info(`Bot connecté en tant que ${c.user.tag}`);
  });

  // Un abonné qui rejoint (ou rejoint à nouveau) le serveur récupère son rôle automatiquement.
  client.on(Events.GuildMemberAdd, (member) => {
    if (member.guild.id !== config.guildId) return;
    enqueue(deps.db, "sync_access_discord", { discordUserId: member.id }).catch((e) => logger.error(`guildMemberAdd : ${String(e)}`));
  });

  client.on(Events.InteractionCreate, async (interaction) => {
    if (!interaction.isChatInputCommand()) return;
    if (interaction.guildId !== config.guildId || !hasRole(interaction, config.adminRoleId)) {
      await interaction.reply({ content: "⛔ Commande réservée à l'administration du Live Club.", flags: MessageFlags.Ephemeral });
      await audit(deps.db, { actorType: "admin", actorId: interaction.user.id, action: "admin.command_denied", details: { command: interaction.commandName } }, deps.now());
      return;
    }
    const command = toCommand(interaction);
    if (!command) {
      await interaction.reply({ content: "Commande inconnue.", flags: MessageFlags.Ephemeral });
      return;
    }
    await interaction.deferReply({ flags: MessageFlags.Ephemeral });
    try {
      const content = await runAdminCommand(deps, interaction.user.id, command);
      await audit(deps.db, { actorType: "admin", actorId: interaction.user.id, action: `admin.command.${command.name}`, details: { ...command } }, deps.now());
      await interaction.editReply({ content: content.slice(0, 2000), allowedMentions: { parse: [] } });
    } catch (error) {
      logger.error(`/${interaction.commandName} : ${error instanceof Error ? error.message : String(error)}`);
      await interaction.editReply({ content: "❌ Erreur interne, détails dans les logs du worker." });
    }
  });

  client.on(Events.Error, (error) => logger.error(`Discord : ${error.message}`));
  return client;
}
