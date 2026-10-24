// Crée un fichier .env de démonstration locale (faux prestataires, aucun paiement réel).
//   pnpm setup:demo            (ne remplace jamais un .env existant)
//   pnpm setup:demo --force    (remplace le .env existant)
import { existsSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const target = path.join(root, ".env");
if (existsSync(target) && !process.argv.includes("--force")) {
  console.log(".env existe déjà : rien n'a été modifié (utilise --force pour le remplacer).");
  process.exit(0);
}

const content = `# .env de DÉMONSTRATION LOCALE (créé par pnpm setup:demo) — aucun paiement réel possible.
# Pour la production, pars de .env.example. Ne partage jamais ce fichier.
NODE_ENV=development
APP_URL=http://localhost:3000
DATABASE_URL=postgres://postgres:postgres@localhost:5432/victorious
SESSION_SECRET=${randomBytes(48).toString("base64url")}

# Tableau de bord : identifiant fictif pour la démo (pnpm dev:login). Remplace-le par ton vrai ID Discord ensuite.
ADMIN_DISCORD_IDS=100000000000000001

# Lien Telegram initial : colle ici ton lien d'invitation (ensuite modifiable dans /admin/telegram).
TELEGRAM_INVITE_URL=

# Paiements simulés par le faux serveur (pnpm mock:providers)
PAYMENT_MODE=test
PAYMENT_PROVIDER_CARD=flutterwave
PAYMENT_PROVIDER_MOBILE_MONEY=paydunya
FLW_SECRET_KEY=FLWSECK_TEST-mock
FLW_WEBHOOK_HASH=flw-webhook-hash-dev
FLW_API_BASE_URL=http://127.0.0.1:4010
PAYDUNYA_MASTER_KEY=pd-master-test
PAYDUNYA_PRIVATE_KEY=test_private_mock
PAYDUNYA_TOKEN=pd-token-test
PAYDUNYA_API_BASE_URL=http://127.0.0.1:4010/sandbox-api/v1
WAVE_API_KEY=wave_sn_test_mock
WAVE_WEBHOOK_SECRET=wave_sn_WHS_dev
WAVE_API_BASE_URL=http://127.0.0.1:4010

# Emails affichés dans le terminal au lieu d'être envoyés
EMAIL_PROVIDER=console

# Discord (facultatif en démo : nécessaire pour la vraie connexion et le bot, voir docs/guide-discord.md)
DISCORD_CLIENT_ID=
DISCORD_CLIENT_SECRET=
DISCORD_BOT_TOKEN=
DISCORD_GUILD_ID=
DISCORD_MEMBER_ROLE_ID=
DISCORD_ADMIN_ROLE_ID=
DISCORD_LOG_CHANNEL_ID=
DISCORD_EXEMPT_USER_IDS=
DISCORD_EXEMPT_ROLE_IDS=
`;
writeFileSync(target, content);
console.log(".env de démonstration créé. Étapes suivantes : docker compose up -d db, puis pnpm db:migrate.");
