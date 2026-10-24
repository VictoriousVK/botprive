import { cookies } from "next/headers";
import { audit, createSession, enqueue, SESSION_DAYS, signingSecret, upsertMember, verifyState } from "@vk/core";
import { exchangeCode, fetchUser, joinGuild } from "@/lib/discord-oauth";
import { rateLimit, tooManyRequests } from "@/lib/rate-limit";
import { clientIp, redirectTo } from "@/lib/security";
import { cookieOptions, getDeps, OAUTH_COOKIE, SESSION_COOKIE } from "@/lib/server";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (!rateLimit(`callback:${clientIp(request)}`, 20, 60_000)) return tooManyRequests();
  const deps = getDeps();
  const url = new URL(request.url);
  if (url.searchParams.get("error")) return redirectTo("/inscription?erreur=oauth_denied");

  const store = await cookies();
  const nonce = store.get(OAUTH_COOKIE)?.value;
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const verified = nonce && state ? verifyState(signingSecret(deps.env), state, nonce) : null;
  if (!code || !verified) return redirectTo("/inscription?erreur=oauth_failed");

  try {
    const accessToken = await exchangeCode(deps.env, code);
    const user = await fetchUser(deps.env, accessToken);
    const member = await upsertMember(
      deps.db,
      {
        discordUserId: user.id,
        username: user.global_name || user.username,
        email: user.email ?? null,
        emailVerified: user.verified ?? false,
      },
      deps.now(),
    );

    // Ajout au serveur public s'il n'y est pas encore (le rôle viendra avec le paiement confirmé).
    try {
      const joined = await joinGuild(deps.env, user.id, accessToken);
      if (joined === "joined") await enqueue(deps.db, "sync_access_discord", { discordUserId: user.id });
    } catch (error) {
      deps.logger.warn(`Ajout au serveur impossible pour ${user.id} : ${error instanceof Error ? error.message : String(error)}`);
    }

    const session = await createSession(deps.db, member.id, deps.now());
    await audit(deps.db, { actorType: "member", actorId: user.id, action: "auth.login", memberId: member.id }, deps.now());
    store.set(SESSION_COOKIE, session.token, cookieOptions(SESSION_DAYS * 86_400));
    store.delete(OAUTH_COOKIE);
    return redirectTo(verified.next);
  } catch (error) {
    deps.logger.error(`Connexion Discord : ${error instanceof Error ? error.message : String(error)}`);
    return redirectTo("/inscription?erreur=oauth_failed");
  }
}
