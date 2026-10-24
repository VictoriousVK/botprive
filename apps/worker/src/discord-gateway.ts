import { DiscordAPIError, HTTPError, REST, RESTJSONErrorCodes, Routes } from "discord.js";
import type { APIChannel, APIGuildMember } from "discord.js";
import { ExternalServiceError, type DiscordGateway, type GuildMemberInfo } from "@vk/core";

/*
 * Accès Discord par l'API REST (gestion des limites de débit incluse dans @discordjs/rest).
 * Erreurs réseau, 429 et 5xx → transitoires (la tâche sera réessayée).
 */

function wrap(error: unknown, action: string): never {
  if (error instanceof DiscordAPIError) {
    const transient = error.status === 429 || error.status >= 500;
    throw new ExternalServiceError("Discord", `${action} : ${error.message} (code ${error.code})`, transient, error.status);
  }
  if (error instanceof HTTPError) {
    throw new ExternalServiceError("Discord", `${action} : HTTP ${error.status}`, error.status >= 500 || error.status === 429, error.status);
  }
  throw new ExternalServiceError("Discord", `${action} : ${error instanceof Error ? error.message : String(error)}`, true);
}

const toInfo = (m: APIGuildMember): GuildMemberInfo => ({
  userId: m.user!.id,
  roles: m.roles,
  username: m.user?.username,
  isBot: m.user?.bot ?? false,
});

export class RestDiscordGateway implements DiscordGateway {
  constructor(
    private readonly rest: REST,
    private readonly guildId: string,
    private readonly logChannelId: string | undefined,
  ) {}

  async getMember(userId: string): Promise<GuildMemberInfo | null> {
    try {
      return toInfo((await this.rest.get(Routes.guildMember(this.guildId, userId))) as APIGuildMember);
    } catch (error) {
      if (error instanceof DiscordAPIError && (error.code === RESTJSONErrorCodes.UnknownMember || error.code === RESTJSONErrorCodes.UnknownUser)) {
        return null;
      }
      wrap(error, "lecture du membre");
    }
  }

  /** Liste complète des membres (pagination par 1000). Nécessite l'intent « Server Members ». */
  async listMembers(): Promise<GuildMemberInfo[]> {
    const all: GuildMemberInfo[] = [];
    let after = "0";
    try {
      for (;;) {
        const page = (await this.rest.get(Routes.guildMembers(this.guildId), {
          query: new URLSearchParams({ limit: "1000", after }),
        })) as APIGuildMember[];
        all.push(...page.map(toInfo));
        if (page.length < 1000) break;
        after = page[page.length - 1]!.user!.id;
      }
    } catch (error) {
      wrap(error, "liste des membres");
    }
    return all;
  }

  async addRole(userId: string, roleId: string, reason: string): Promise<void> {
    try {
      await this.rest.put(Routes.guildMemberRole(this.guildId, userId, roleId), { reason });
    } catch (error) {
      wrap(error, "attribution du rôle");
    }
  }

  async removeRole(userId: string, roleId: string, reason: string): Promise<void> {
    try {
      await this.rest.delete(Routes.guildMemberRole(this.guildId, userId, roleId), { reason });
    } catch (error) {
      if (error instanceof DiscordAPIError && error.code === RESTJSONErrorCodes.UnknownMember) return;
      wrap(error, "retrait du rôle");
    }
  }

  async kick(userId: string, reason: string): Promise<void> {
    try {
      await this.rest.delete(Routes.guildMember(this.guildId, userId), { reason });
    } catch (error) {
      if (error instanceof DiscordAPIError && error.code === RESTJSONErrorCodes.UnknownMember) return;
      wrap(error, "expulsion");
    }
  }

  async sendDm(userId: string, content: string): Promise<"sent" | "blocked"> {
    try {
      const channel = (await this.rest.post(Routes.userChannels(), { body: { recipient_id: userId } })) as APIChannel;
      await this.rest.post(Routes.channelMessages(channel.id), {
        body: { content: content.slice(0, 2000), allowed_mentions: { parse: [] } },
      });
      return "sent";
    } catch (error) {
      if (error instanceof DiscordAPIError && error.code === RESTJSONErrorCodes.CannotSendMessagesToThisUser) return "blocked";
      wrap(error, "message privé");
    }
  }

  async postLog(content: string): Promise<void> {
    if (!this.logChannelId) return;
    try {
      // Mentions affichées mais jamais notifiées (allowed_mentions vide).
      await this.rest.post(Routes.channelMessages(this.logChannelId), {
        body: { content: content.slice(0, 2000), allowed_mentions: { parse: [] } },
      });
    } catch (error) {
      wrap(error, "salon de logs");
    }
  }
}
