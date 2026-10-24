/**
 * DÉVELOPPEMENT : connexion locale sans Discord.
 *   pnpm dev:login            → lien de connexion administrateur (tableau de bord /admin)
 *   pnpm dev:login --membre   → lien de connexion d'un membre de test (espace membre, paiement simulé)
 * Ouvre ensuite le lien affiché dans ton navigateur. Ne fonctionne pas en production.
 */
import { createSession, loadEnv, required, upsertMember } from "@vk/core";
import { createDb } from "@vk/db";

const env = loadEnv();
if (env.NODE_ENV === "production") {
  console.error("dev:login est réservé au développement local.");
  process.exit(1);
}
const asMember = process.argv.includes("--membre");
const adminId = env.ADMIN_DISCORD_IDS[0];
if (!asMember && !adminId) {
  console.error("Ajoute ton identifiant Discord (ou 100000000000000001 pour la démo) dans ADMIN_DISCORD_IDS du fichier .env.");
  process.exit(1);
}
const { db, close } = createDb(required(env, "DATABASE_URL"), { max: 1 });
try {
  const member = await upsertMember(
    db,
    asMember
      ? { discordUserId: "200000000000000002", username: "membre_test", email: "membre.test@exemple.sn", emailVerified: true }
      : { discordUserId: adminId!, username: "admin_local" },
    new Date(),
  );
  const { token } = await createSession(db, member.id, new Date());
  const next = asMember ? "/espace" : "/admin";
  console.log(`\nOuvre ce lien dans ton navigateur (valable 30 jours) :\n\n  ${env.APP_URL}/api/dev/session?token=${token}&next=${encodeURIComponent(next)}\n`);
} finally {
  await close();
}
