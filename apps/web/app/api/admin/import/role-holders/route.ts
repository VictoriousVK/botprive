import { getAdmin } from "@/lib/admin";
import { getEnv } from "@/lib/server";

export const dynamic = "force-dynamic";

interface ApiMember {
  user?: { id: string; username?: string; global_name?: string | null; bot?: boolean };
  nick?: string | null;
  roles: string[];
}

function csvCell(value: string): string {
  return /[",;\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
}

/**
 * Exporte les membres du serveur qui ont déjà le rôle abonné, au format du CSV d'import
 * (formule et date de fin à compléter). Lecture seule : rien n'est modifié sur Discord.
 * Nécessite l'intent « Server Members » activé pour le bot.
 */
export async function GET() {
  const admin = await getAdmin();
  if (!admin) return new Response("Accès réservé à l'administration", { status: 403 });
  const env = getEnv();
  if (!env.DISCORD_BOT_TOKEN || !env.DISCORD_GUILD_ID || !env.DISCORD_MEMBER_ROLE_ID) {
    return new Response("Bot Discord non configuré (DISCORD_BOT_TOKEN, DISCORD_GUILD_ID, DISCORD_MEMBER_ROLE_ID)", { status: 400 });
  }
  const holders: ApiMember[] = [];
  let after = "0";
  try {
    for (let page = 0; page < 50; page++) {
      const res = await fetch(`${env.DISCORD_API_BASE_URL}/guilds/${env.DISCORD_GUILD_ID}/members?limit=1000&after=${after}`, {
        headers: { authorization: `Bot ${env.DISCORD_BOT_TOKEN}` },
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) return new Response(`Discord a répondu HTTP ${res.status} (intent « Server Members » activé ?)`, { status: 502 });
      const batch = (await res.json()) as ApiMember[];
      holders.push(...batch.filter((m) => m.user && !m.user.bot && m.roles.includes(env.DISCORD_MEMBER_ROLE_ID!)));
      if (batch.length < 1000) break;
      after = batch[batch.length - 1]!.user!.id;
    }
  } catch {
    return new Response("Discord injoignable pour le moment", { status: 502 });
  }
  const lines = ["discord_user_id,nom,email,téléphone,formule,date_de_fin"];
  for (const m of holders) lines.push([m.user!.id, m.nick ?? m.user!.global_name ?? m.user!.username ?? "", "", "", "", ""].map(csvCell).join(","));
  return new Response(`﻿${lines.join("\n")}\n`, {
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": 'attachment; filename="membres-actuels-a-completer.csv"',
      "cache-control": "no-store",
    },
  });
}
