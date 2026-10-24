import { cookies } from "next/headers";
import type { Member } from "@vk/db";
import { isSameOrigin, redirectTo } from "./security";
import { getCurrentMember, getEnv } from "./server";

/*
 * Accès au tableau de bord : membre connecté (Discord) dont l'ID figure dans ADMIN_DISCORD_IDS.
 * Chaque page ET chaque route admin vérifie elle-même (on ne s'appuie pas sur la mise en page).
 */

export function isAdminId(discordUserId: string): boolean {
  return getEnv().ADMIN_DISCORD_IDS.includes(discordUserId);
}

export async function getAdmin(): Promise<Member | null> {
  const member = await getCurrentMember();
  return member && isAdminId(member.discordUserId) ? member : null;
}

/** Pour les routes POST admin : même origine + admin. Retourne la réponse d'erreur, ou le membre. */
export async function requireAdmin(request: Request): Promise<Member | Response> {
  if (!isSameOrigin(request)) return new Response("Requête refusée (origine)", { status: 403 });
  const admin = await getAdmin();
  if (!admin) return new Response("Accès réservé à l'administration", { status: 403 });
  return admin;
}

const FLASH_COOKIE = "vk_flash";

/**
 * Message affiché une fois sur la page suivante (cookie de 20 s, jamais dans l'URL).
 * Non HttpOnly : il ne contient aucun secret et la page l'efface dès l'affichage (FlashClear).
 */
export function flashRedirect(path: string, type: "ok" | "error", text: string): Response {
  const response = redirectTo(path);
  const value = encodeURIComponent(JSON.stringify({ type, text: text.slice(0, 500) }));
  response.headers.append("set-cookie", `${FLASH_COOKIE}=${value}; Path=/admin; Max-Age=20; SameSite=Lax${getEnv().NODE_ENV === "production" ? "; Secure" : ""}`);
  return response;
}

export async function readFlash(): Promise<{ type: "ok" | "error"; text: string } | null> {
  const raw = (await cookies()).get(FLASH_COOKIE)?.value;
  if (!raw) return null;
  try {
    const parsed = JSON.parse(decodeURIComponent(raw)) as { type: "ok" | "error"; text: string };
    return parsed.type === "ok" || parsed.type === "error" ? parsed : null;
  } catch {
    return null;
  }
}

/** Champs de formulaire : chaîne vide → null. */
export function text(form: FormData, key: string): string | null {
  const v = form.get(key);
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
}

export function int(form: FormData, key: string): number | null {
  const v = text(form, key);
  if (v === null) return null;
  const n = Number(v.replace(/[\s.]/g, ""));
  return Number.isFinite(n) ? Math.round(n) : NaN;
}

export function checked(form: FormData, key: string): boolean {
  return form.get(key) === "on";
}
