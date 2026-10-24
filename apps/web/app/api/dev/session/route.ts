import { getSessionMember, safeInternalPath, SESSION_DAYS } from "@vk/core";
import { redirectTo } from "@/lib/security";
import { cookieOptions, getDeps, SESSION_COOKIE } from "@/lib/server";

export const dynamic = "force-dynamic";

/**
 * DÉVELOPPEMENT UNIQUEMENT (404 en production) : ouvre une session créée par `pnpm dev:login`,
 * pour tester l'espace membre et le tableau de bord sans application Discord.
 * Le jeton doit correspondre à une session existante en base.
 */
export async function GET(request: Request) {
  const deps = getDeps();
  if (deps.env.NODE_ENV === "production") return new Response("Not found", { status: 404 });
  const url = new URL(request.url);
  const token = url.searchParams.get("token");
  const member = await getSessionMember(deps.db, token, deps.now());
  if (!token || !member) return new Response("Session inconnue ou expirée : relance pnpm dev:login", { status: 400 });
  const response = redirectTo(safeInternalPath(url.searchParams.get("next"), "/admin"));
  const o = cookieOptions(SESSION_DAYS * 86_400);
  response.headers.append("set-cookie", `${SESSION_COOKIE}=${token}; Path=${o.path}; Max-Age=${o.maxAge}; HttpOnly; SameSite=Lax`);
  return response;
}
