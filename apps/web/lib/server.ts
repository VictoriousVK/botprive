import { cookies } from "next/headers";
import {
  consoleLogger,
  createProviderRegistry,
  getSessionMember,
  loadEnv,
  required,
  type AppEnv,
  type CoreDeps,
} from "@vk/core";
import { createDb, type Member } from "@vk/db";

export const SESSION_COOKIE = "vk_session";
export const OAUTH_COOKIE = "vk_oauth";

declare global {
  // Réutilisé entre les rechargements à chaud en développement.
  var __vkDeps: CoreDeps | undefined;
}

/** Dépendances serveur (base, prestataires), créées une seule fois par process. */
export function getDeps(): CoreDeps {
  if (!globalThis.__vkDeps) {
    const env = loadEnv();
    const { db } = createDb(required(env, "DATABASE_URL"), { max: 5 });
    globalThis.__vkDeps = { db, env, now: () => new Date(), logger: consoleLogger, providers: createProviderRegistry(env) };
  }
  return globalThis.__vkDeps;
}

export function getEnv(): AppEnv {
  return getDeps().env;
}

/** Membre connecté (cookie de session), ou null. */
export async function getCurrentMember(): Promise<Member | null> {
  const store = await cookies();
  const deps = getDeps();
  return getSessionMember(deps.db, store.get(SESSION_COOKIE)?.value, deps.now());
}

export function cookieOptions(maxAgeSeconds: number) {
  return {
    httpOnly: true,
    secure: getEnv().NODE_ENV === "production",
    sameSite: "lax" as const,
    path: "/",
    maxAge: maxAgeSeconds,
  };
}
