import type { DiscordPresence } from "@vk/core";
import { getEnv } from "./server";

/**
 * Vérifie la présence d'un membre sur le serveur Discord (aperçu de l'import).
 * Lecture seule : aucun rôle n'est modifié. Sans bot configuré ou injoignable → « non vérifié ».
 */
export function createDiscordPresenceCheck(): (discordUserId: string) => Promise<DiscordPresence> {
  const env = getEnv();
  if (!env.DISCORD_BOT_TOKEN || !env.DISCORD_GUILD_ID) return async () => "unverified";
  let unreachable = false;
  return async (discordUserId) => {
    if (unreachable) return "unverified";
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const res = await fetch(`${env.DISCORD_API_BASE_URL}/guilds/${env.DISCORD_GUILD_ID}/members/${discordUserId}`, {
          headers: { authorization: `Bot ${env.DISCORD_BOT_TOKEN}` },
          signal: AbortSignal.timeout(8000),
        });
        if (res.status === 200) return "present";
        if (res.status === 404) return "absent";
        if (res.status === 429) {
          const wait = Number((await res.json().catch(() => ({}))).retry_after ?? 1);
          await new Promise((r) => setTimeout(r, Math.min(wait, 5) * 1000));
          continue;
        }
        return "unverified";
      } catch {
        unreachable = true;
        return "unverified";
      }
    }
    return "unverified";
  };
}
