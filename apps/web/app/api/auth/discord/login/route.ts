import { randomToken, signingSecret, signState } from "@vk/core";
import { authorizeUrl } from "@/lib/discord-oauth";
import { rateLimit, tooManyRequests } from "@/lib/rate-limit";
import { clientIp } from "@/lib/security";
import { cookieOptions, getEnv, OAUTH_COOKIE } from "@/lib/server";

export const dynamic = "force-dynamic";

/** Démarre la connexion Discord. ?next=/chemin interne où revenir ensuite. */
export async function GET(request: Request) {
  if (!rateLimit(`login:${clientIp(request)}`, 20, 60_000)) return tooManyRequests();
  const env = getEnv();
  const next = new URL(request.url).searchParams.get("next") ?? "/espace";
  const nonce = randomToken(16);
  const state = signState(signingSecret(env), nonce, next);
  const response = new Response(null, { status: 302, headers: { location: authorizeUrl(env, state) } });
  const opts = cookieOptions(600);
  response.headers.append(
    "set-cookie",
    `${OAUTH_COOKIE}=${nonce}; Path=${opts.path}; Max-Age=${opts.maxAge}; HttpOnly; SameSite=Lax${opts.secure ? "; Secure" : ""}`,
  );
  return response;
}
