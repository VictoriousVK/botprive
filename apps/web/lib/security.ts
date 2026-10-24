import { getEnv } from "./server";

/**
 * Protection CSRF des formulaires : la requête doit venir de notre propre site.
 * (Les cookies sont en SameSite=Lax ; ce contrôle ajoute une seconde barrière.)
 */
export function isSameOrigin(request: Request): boolean {
  const expected = new URL(getEnv().APP_URL).origin;
  const origin = request.headers.get("origin");
  if (origin) return origin === expected;
  const referer = request.headers.get("referer");
  if (referer) {
    try {
      return new URL(referer).origin === expected;
    } catch {
      return false;
    }
  }
  return request.headers.get("sec-fetch-site") === "same-origin";
}

/** Adresse IP du client (derrière le proxy de l'hébergeur). */
export function clientIp(request: Request): string {
  return request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || request.headers.get("x-real-ip") || "inconnue";
}

export function redirectTo(path: string, status = 303): Response {
  return new Response(null, { status, headers: { location: new URL(path, getEnv().APP_URL).toString() } });
}
