import { cookies } from "next/headers";
import { deleteSession } from "@vk/core";
import { isSameOrigin, redirectTo } from "@/lib/security";
import { getDeps, SESSION_COOKIE } from "@/lib/server";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  if (!isSameOrigin(request)) return redirectTo("/?erreur=csrf");
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  if (token) await deleteSession(getDeps().db, token);
  store.delete(SESSION_COOKIE);
  return redirectTo("/");
}
