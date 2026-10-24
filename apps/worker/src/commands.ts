import { InteractionContextType, PermissionFlagsBits, SlashCommandBuilder } from "discord.js";
import { PLANS } from "@vk/core";

const planChoices = Object.values(PLANS).map((p) => ({ name: p.label, value: p.id }));

/**
 * Commandes admin. Elles sont masquées aux membres (permission « Gérer les rôles » par défaut)
 * ET le bot vérifie à chaque appel que l'auteur a le rôle DISCORD_ADMIN_ROLE_ID.
 */
export const commandDefinitions = [
  new SlashCommandBuilder()
    .setName("abonne")
    .setDescription("Fiche d'abonnement d'un membre")
    .addUserOption((o) => o.setName("membre").setDescription("Le membre").setRequired(true)),
  new SlashCommandBuilder()
    .setName("ajouter")
    .setDescription("Ajouter des jours ou une formule (paiement manuel, geste commercial)")
    .addUserOption((o) => o.setName("membre").setDescription("Le membre").setRequired(true))
    .addIntegerOption((o) => o.setName("jours").setDescription("Nombre de jours (1 à 400)").setMinValue(1).setMaxValue(400))
    .addStringOption((o) => o.setName("formule").setDescription("Ou une formule complète").addChoices(...planChoices))
    .addStringOption((o) => o.setName("note").setDescription("Ex : Wave perso 50 000 FCFA").setMaxLength(200)),
  new SlashCommandBuilder()
    .setName("retirer")
    .setDescription("Suspendre l'accès d'un membre (retire le rôle)")
    .addUserOption((o) => o.setName("membre").setDescription("Le membre").setRequired(true))
    .addStringOption((o) => o.setName("raison").setDescription("Raison (journalisée)").setMaxLength(200)),
  new SlashCommandBuilder()
    .setName("expirations")
    .setDescription("Échéances à venir")
    .addIntegerOption((o) => o.setName("jours").setDescription("Horizon en jours (défaut 7)").setMinValue(1).setMaxValue(90)),
  new SlashCommandBuilder().setName("stats").setDescription("Chiffres clés du Live Club"),
].map((c) =>
  c
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageRoles)
    .setContexts(InteractionContextType.Guild)
    .toJSON(),
);
