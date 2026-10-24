import type { AppEnv } from "./config/env";
import { isPlanId, type PlanId } from "./config/club";
import { hmacSha256Base64Url, randomToken, safeEqual, sha256Hex } from "./crypto";
import { addDays } from "./dates";

/** Secret de signature (sessions, liens de renouvellement). Obligatoire en production. */
export function signingSecret(env: AppEnv): string {
  if (env.SESSION_SECRET) return env.SESSION_SECRET;
  if (env.NODE_ENV === "production") throw new Error("SESSION_SECRET manquant");
  return "dev-only-insecure-secret-change-me-in-env";
}

interface RenewalPayload {
  m: string;
  p: PlanId;
  e: number;
}

/** Lien de renouvellement pré-rempli (membre + formule), signé et limité dans le temps. */
export function createRenewalToken(secret: string, memberId: string, planId: PlanId, now: Date, validityDays: number): string {
  const payload: RenewalPayload = { m: memberId, p: planId, e: Math.floor(addDays(now, validityDays).getTime() / 1000) };
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `${encoded}.${hmacSha256Base64Url(secret, `renew:${encoded}`)}`;
}

export function verifyRenewalToken(secret: string, token: string, now: Date): { memberId: string; planId: PlanId } | null {
  const [encoded, signature] = token.split(".");
  if (!encoded || !signature) return null;
  if (!safeEqual(signature, hmacSha256Base64Url(secret, `renew:${encoded}`))) return null;
  try {
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8")) as RenewalPayload;
    if (typeof payload.m !== "string" || !isPlanId(payload.p) || typeof payload.e !== "number") return null;
    if (payload.e * 1000 < now.getTime()) return null;
    return { memberId: payload.m, planId: payload.p };
  } catch {
    return null;
  }
}

/** Jeton de session : la valeur brute va dans le cookie, seule son empreinte est stockée. */
export function newSessionToken(): { token: string; id: string } {
  const token = randomToken(32);
  return { token, id: sha256Hex(token) };
}

export function sessionIdFromToken(token: string): string {
  return sha256Hex(token);
}

/**
 * Chemin interne sûr pour une redirection : refuse toute URL externe, y compris « //site » et « /\site »
 * (le navigateur lit la barre oblique inverse comme « / »). Renvoie `fallback` sinon.
 */
export function safeInternalPath(value: unknown, fallback: string): string {
  if (typeof value !== "string" || !value.startsWith("/")) return fallback;
  const base = "http://interne.invalid";
  try {
    const url = new URL(value, base);
    return url.origin === base ? `${url.pathname}${url.search}${url.hash}` : fallback;
  } catch {
    return fallback;
  }
}

/** Valeur « state » OAuth signée (anti-CSRF), avec la page de retour. */
export function signState(secret: string, nonce: string, next: string): string {
  const encoded = Buffer.from(JSON.stringify({ n: nonce, r: next })).toString("base64url");
  return `${encoded}.${hmacSha256Base64Url(secret, `state:${encoded}`)}`;
}

export function verifyState(secret: string, state: string, expectedNonce: string): { next: string } | null {
  const [encoded, signature] = state.split(".");
  if (!encoded || !signature || !safeEqual(signature, hmacSha256Base64Url(secret, `state:${encoded}`))) return null;
  try {
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8")) as { n: string; r: string };
    if (!safeEqual(payload.n, expectedNonce)) return null;
    // Redirection interne uniquement (pas d'URL externe : évite les redirections ouvertes).
    return { next: safeInternalPath(payload.r, "/espace") };
  } catch {
    return null;
  }
}
