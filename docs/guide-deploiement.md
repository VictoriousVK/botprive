# Guide de déploiement

Hébergement recommandé : **Railway**, avec 3 services dans un même projet : `web` (site), `worker` (bot + tâches), `Postgres`.
Coût estimé : environ 10 à 15 $/mois (plan Hobby : 5 $ avec 5 $ d'usage inclus, puis facturation à l'usage). Vérifie les prix sur railway.com/pricing.

Alternative à moins de 7 $/mois : un petit VPS avec `docker compose` (voir la fin). Tu y gères toi-même les mises à jour, les sauvegardes et le HTTPS.

## 0. Avant de commencer
- [ ] Dépôt GitHub **privé** recommandé (Settings → General → Danger Zone → Change visibility). Le dépôt `botprive` est actuellement public.
- [ ] Application Discord créée ([guide Discord](guide-discord.md), étapes 1 à 6).
- [ ] Au moins un prestataire configuré en mode test ([guide paiements](guide-paiements.md)).
- [ ] Nom de domaine (ex : `club.ton-domaine.com`).

## 1. Créer le projet Railway
1. <https://railway.com> → connexion avec GitHub → **New Project → Deploy from GitHub repo** → `botprive`.
2. Le premier service créé sera le site : renomme-le `web`. Dans **Settings** :
   - **Config-as-code / Railway config file** : `apps/web/railway.json`
   - Branche : `main` (après fusion de cette branche)
3. **New → GitHub Repo** (même dépôt) pour le second service : nomme-le `worker`, config file `apps/worker/railway.json`.
4. **New → Database → PostgreSQL**.

Le site expose `/api/health` (vérifié par Railway avant chaque mise en service). Le worker garde **une seule instance** : deux bots connectés répondraient deux fois aux commandes.

## 2. Variables d'environnement

Dans le projet : **Variables → Shared Variables**. Ajoute les valeurs communes, puis partage-les avec `web` et `worker` :

| Variable | Valeur |
|---|---|
| `NODE_ENV` | `production` |
| `APP_URL` | `https://club.ton-domaine.com` (sans / final) |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (référence Railway, réseau privé) |
| `SESSION_SECRET` | `openssl rand -base64 48` (même valeur pour les deux services) |
| `ADMIN_DISCORD_IDS` | ton identifiant Discord (accès à `/admin`) |
| `TELEGRAM_INVITE_URL` | ton lien d'invitation Telegram (valeur initiale, ensuite modifiable dans `/admin/telegram`) |
| `PAYMENT_MODE` | `test` tant que le prestataire n'est pas validé et testé, puis `live` |
| `DISCORD_*` | voir [guide Discord](guide-discord.md) |
| `PAYMENT_PROVIDER_*`, `FLW_*`, `PAYDUNYA_*`, `WAVE_*` | voir [guide paiements](guide-paiements.md) |
| `EMAIL_PROVIDER` | `resend` |
| `RESEND_API_KEY`, `EMAIL_FROM` | voir l'étape 4 |

Ne remplis pas `FLW_API_BASE_URL`, `WAVE_API_BASE_URL` ni `PAYDUNYA_API_BASE_URL` : les valeurs par défaut sont les vraies API (sandbox PayDunya en mode test).
Tarifs, horaires, lien Telegram et mode Discord ne sont pas des variables : ils se règlent dans `/admin` ([guide](tableau-de-bord.md)).
Le worker a besoin de toutes les variables. Le site n'a pas besoin de `DISCORD_LOG_CHANNEL_ID` ni de `RESEND_*`, mais il a besoin de `DISCORD_BOT_TOKEN` (ajout au serveur à l'inscription).

## 3. Domaine
1. Service `web` → **Settings → Networking → Custom Domain** → `club.ton-domaine.com`.
2. Chez ton registrar, crée l'enregistrement **CNAME** indiqué par Railway. Le certificat HTTPS est automatique.
3. Mets à jour `APP_URL`, puis redéploie.

## 4. Emails (Resend)
1. <https://resend.com> → **Domains → Add Domain** → `ton-domaine.com`.
2. Ajoute chez ton registrar les enregistrements DNS demandés (SPF, DKIM), puis attends le statut *Verified*.
3. **API Keys** → clé « Sending access » → `RESEND_API_KEY`.
4. `EMAIL_FROM=V_ICT_ORIOUS Live Club <club@ton-domaine.com>`, `EMAIL_PROVIDER=resend`.

Le plan gratuit permet 3 000 emails par mois et **100 par jour**. Si beaucoup de membres ont la même échéance (après l'import CSV, par exemple), surveille cette limite ; un email refusé est réessayé plus tard.

## 5. Premier déploiement
1. Déploie **d'abord le worker** : il applique les migrations au démarrage (verrou Postgres, sans risque si les deux services démarrent ensemble).
2. Logs du worker attendus : `Migrations à jour`, `Bot connecté en tant que …`, `Worker démarré`. Message `🟢 Worker démarré` dans `#logs-club`.
3. Déploie `web`, puis ouvre `https://club.ton-domaine.com/api/health` → `{"ok":true}`.
4. Enregistre les commandes : `pnpm discord:register` en local avec les variables Discord de production, ou `node dist/register-commands.js` dans le shell du worker.

## 6. URLs à déclarer chez les services

| Où | URL |
|---|---|
| Discord → OAuth2 → Redirects | `https://club.ton-domaine.com/api/auth/discord/callback` |
| Flutterwave → Settings → Webhooks | `https://club.ton-domaine.com/api/webhooks/flutterwave` |
| Wave Business → Webhooks | `https://club.ton-domaine.com/api/webhooks/wave` |
| PayDunya | rien à déclarer : l'URL `https://club.ton-domaine.com/api/webhooks/paydunya` est envoyée avec chaque facture |

Les URLs de retour après paiement sont générées automatiquement : `https://club.ton-domaine.com/paiement/retour?ref=…`.

## 7. Import des membres actuels
Depuis le tableau de bord : `/admin/import` ([guide](guide-import-membres.md)). Ou depuis ton ordinateur, avec l'URL **publique** de la base (Railway → Postgres → Connect → *Public Network*) :
```bash
DATABASE_URL="postgres://…public…" pnpm import:members membres.csv           # simulation
DATABASE_URL="postgres://…public…" pnpm import:members membres.csv --apply   # import réel
```
Format : voir `scripts/fixtures/membres-exemple.csv`. Les rôles suivent ensuite le mode Discord du tableau de bord (observation par défaut : aucun rôle modifié).

## 8. Sauvegardes
- Railway : vérifie l'onglet **Backups** du service Postgres et active les sauvegardes automatiques si ton plan le permet.
- En plus, une copie hors de Railway, chaque semaine par exemple :
  ```bash
  DATABASE_URL="postgres://…public…" ./scripts/backup-db.sh    # crée backups/victorious-AAAAMMJJ-HHMM.sql.gz
  ```
- Restauration : `gunzip -c fichier.sql.gz | psql "$DATABASE_URL"`. Teste-la une fois, sur une base vide.

## 9. Mises à jour
Chaque fusion sur `main` redéploie automatiquement les services concernés. Après une modification du schéma : `pnpm db:generate`, puis commit du fichier SQL de `packages/db/drizzle/`. Le worker l'applique au démarrage.

## Alternative : VPS avec Docker Compose
Sur un VPS Ubuntu, avec Docker installé :
```bash
git clone … && cd botprive && cp .env.example .env   # compléter, NODE_ENV=production
docker compose --profile app up -d --build           # Postgres + site (port 3000) + worker
```
Ajoute devant un reverse proxy HTTPS (Caddy : `club.ton-domaine.com { reverse_proxy localhost:3000 }`), ferme le port 5432 au public, et programme `scripts/backup-db.sh` dans cron.
