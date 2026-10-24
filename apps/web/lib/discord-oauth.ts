import { ExternalServiceError, requestJson, required, type AppEnv } from "@vk/core";

/*
 * Connexion Discord OAuth2 (scopes minimum) :
 *  - identify : identifiant et pseudo du compte Discord réel ;
 *  - email : reçus et rappels ;
 *  - guilds.join : ajout automatique au serveur si le membre n'y est pas encore.
 * Le jeton d'accès Discord n'est jamais stocké.
 */

export const OAUTH_SCOPES = ["identify", "email", "guilds.join"];

export function redirectUri(env: AppEnv): string {
  return `${env.APP_URL.replace(/\/$/, "")}/api/auth/discord/callback`;
}

export function authorizeUrl(env: AppEnv, state: string): string {
  const params = new URLSearchParams({
    client_id: required(env, "DISCORD_CLIENT_ID"),
    response_type: "code",
    redirect_uri: redirectUri(env),
    scope: OAUTH_SCOPES.join(" "),
    state,
  });
  return `https://discord.com/oauth2/authorize?${params.toString()}`;
}

export interface DiscordUser {
  id: string;
  username: string;
  global_name?: string | null;
  email?: string | null;
  verified?: boolean;
}

export async function exchangeCode(env: AppEnv, code: string): Promise<string> {
  const body = new URLSearchParams({
    client_id: required(env, "DISCORD_CLIENT_ID"),
    client_secret: required(env, "DISCORD_CLIENT_SECRET"),
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri(env),
  });
  let response: Response;
  try {
    response = await fetch(`${env.DISCORD_API_BASE_URL}/oauth2/token`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body,
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    throw new ExternalServiceError("Discord OAuth", String(error), true);
  }
  if (!response.ok) throw new ExternalServiceError("Discord OAuth", `échange du code : HTTP ${response.status}`, false, response.status);
  const data = (await response.json()) as { access_token?: string };
  if (!data.access_token) throw new ExternalServiceError("Discord OAuth", "jeton absent", false);
  return data.access_token;
}

export async function fetchUser(env: AppEnv, accessToken: string): Promise<DiscordUser> {
  const { data } = await requestJson<DiscordUser>("Discord OAuth", `${env.DISCORD_API_BASE_URL}/users/@me`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  return data;
}

/** Ajoute l'utilisateur au serveur (sans rôle). 201 = ajouté, 204 = déjà membre. */
export async function joinGuild(env: AppEnv, userId: string, accessToken: string): Promise<"joined" | "already"> {
  const { status } = await requestJson(
    "Discord",
    `${env.DISCORD_API_BASE_URL}/guilds/${required(env, "DISCORD_GUILD_ID")}/members/${userId}`,
    {
      method: "PUT",
      headers: { authorization: `Bot ${required(env, "DISCORD_BOT_TOKEN")}` },
      body: { access_token: accessToken },
    },
  );
  return status === 201 ? "joined" : "already";
}
