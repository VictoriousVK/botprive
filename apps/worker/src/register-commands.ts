import { REST, Routes } from "discord.js";
import { loadEnv, required } from "@vk/core";
import { commandDefinitions } from "./commands";

/** Enregistre les commandes admin sur le serveur (à relancer après toute modification des commandes). */
const env = loadEnv();
const rest = new REST({ version: "10" }).setToken(required(env, "DISCORD_BOT_TOKEN"));
const result = (await rest.put(Routes.applicationGuildCommands(required(env, "DISCORD_CLIENT_ID"), required(env, "DISCORD_GUILD_ID")), {
  body: commandDefinitions,
})) as { name: string }[];
console.log(`Commandes enregistrées : ${result.map((c) => `/${c.name}`).join(", ")}`);
