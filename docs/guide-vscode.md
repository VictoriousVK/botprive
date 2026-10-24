# Lancer le projet sur ton ordinateur avec VS Code

Ce guide te permet de faire tourner **en local** le site, l'espace membre et le tableau de bord, avec des **paiements simulés** : aucun argent réel, aucune application Discord nécessaire, aucun membre réel touché.

Durée : environ 30 minutes la première fois (installations comprises), puis 1 minute les fois suivantes.

## 1. Installer les outils (une seule fois)

| Outil | Où le trouver | Vérification dans un terminal |
|---|---|---|
| **VS Code** | code.visualstudio.com | — |
| **Git** | git-scm.com (sous Windows, garde les options par défaut) | `git --version` |
| **Node.js 22 LTS** | nodejs.org, version « LTS » 22.x | `node -v` → `v22.12` ou plus |
| **Docker Desktop** | docker.com/products/docker-desktop (sous Windows, il installe WSL 2 si besoin, puis redémarre) | `docker --version` |

Docker sert uniquement à faire tourner la base de données PostgreSQL. Si Docker ne s'installe pas sur ton PC, voir « Sans Docker » plus bas.

## 2. Récupérer le projet

**Option A, avec Git (recommandée : tu récupères ensuite les mises à jour avec `git pull`)**

```bash
git clone -b claude/admiring-newton-wpe590 https://github.com/VictoriousVK/botprive.git
```

**Option B, sans Git** : télécharge le ZIP de la branche sur GitHub (bouton **Code → Download ZIP** sur la branche `claude/admiring-newton-wpe590`), puis décompresse-le.

Dans VS Code : **Fichier → Ouvrir le dossier…** et choisis le dossier `botprive`. Accepte l'installation des **extensions recommandées** (tests et Docker) si VS Code la propose.

Ouvre un terminal dans VS Code : **Terminal → Nouveau terminal** (raccourci `Ctrl` + `ù` sur clavier français).

## 3. Installer les dépendances

```bash
corepack enable
pnpm install
```

- Sous Windows, `corepack enable` peut demander un terminal **administrateur**. Sinon, remplace-le par `npm install -g pnpm@10.28.0`.
- Un avertissement « Ignored build scripts » de pnpm est normal.

## 4. Préparer la démo (une seule fois)

Lance Docker Desktop et attends qu'il indique « Engine running », puis :

```bash
pnpm setup:demo            # crée le fichier .env de démonstration (secret de session aléatoire)
docker compose up -d db    # démarre PostgreSQL
pnpm db:migrate            # crée les tables
```

Le fichier `.env` reste sur ton ordinateur : il est exclu de Git et ne doit jamais être partagé. Tes vraies clés (Discord, Flutterwave, PayDunya…) iront plus tard dans ce fichier, **jamais dans un chat**.

## 5. Lancer le site

**Avec VS Code** : `Ctrl` + `Maj` + `P` → **Tasks: Run Task** → **▶ Lancer la démo (faux paiements + site)**. Deux terminaux s'ouvrent : les faux prestataires de paiement et le site.

**Ou à la main**, dans deux terminaux :

```bash
pnpm mock:providers   # faux Flutterwave / PayDunya / Wave sur http://127.0.0.1:4010
pnpm dev:web          # le site
```

Ouvre **http://localhost:3000**. Au tout premier chargement, la compilation prend quelques secondes et la page peut se recharger plusieurs fois : attends qu'elle se stabilise.

Les fois suivantes : démarre Docker Desktop, puis lance seulement l'étape 5 (`docker compose up -d db` si la base ne redémarre pas toute seule).

## 6. Se connecter sans application Discord

En démo, le bouton « Se connecter avec Discord » affiche « La connexion Discord n'est pas encore configurée » : c'est normal. Utilise ces liens de connexion locale, dans un **troisième terminal** :

```bash
pnpm dev:login            # lien vers le tableau de bord /admin
pnpm dev:login --membre   # lien vers l'espace membre d'un membre de test
```

`Ctrl` + clic sur le lien affiché. Ouvre le lien « membre » dans une **fenêtre de navigation privée** : sinon il remplace ta session administrateur.

Ces liens ne fonctionnent qu'en local (ils sont désactivés en production).

## 7. Essayer un paiement simulé

1. Tableau de bord → **Tarifs** : saisis un prix **fictif** en FCFA pour une formule (par exemple 25000 pour le trimestriel), puis **Enregistrer les formules**. Ce prix reste dans ta base locale ; il ne fixe pas tes tarifs définitifs.
2. Fenêtre privée (membre) → **http://localhost:3000/inscription** → choisis la formule → **Mobile Money** → **Payer**.
3. La fausse page de paiement s'ouvre → **Payer**.
4. Retour sur le site : « Paiement confirmé ». L'abonnement apparaît dans **Tableau de bord → Membres**.

Le rôle Discord n'est pas attribué en démo : le bot (worker) n'est pas lancé et Discord reste en mode **observation**.

## 8. Tests automatisés et simulation

La base Docker doit être démarrée.

```bash
pnpm test        # 81 tests (bases temporaires créées puis supprimées)
pnpm simulate    # rejoue tout le cycle d'un abonnement : paiement, rappels, grâce, expiration, retour
```

Dans VS Code, l'onglet **Testing** (fiole) lance aussi les tests un par un, grâce à l'extension Vitest.

## 9. Déboguer

Onglet **Exécuter et déboguer** (`Ctrl` + `Maj` + `D`) : configurations « Site (Next.js, débogage) », « Worker (bot Discord, débogage) » et « Simulation (débogage) ». Les points d'arrêt posés dans le code TypeScript fonctionnent.

## 10. Le bot Discord (facultatif)

Il faut une application Discord ([guide-discord.md](guide-discord.md)). Renseigne ses identifiants dans le fichier `.env` (`DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, `DISCORD_MEMBER_ROLE_ID`…), ajoute ton identifiant Discord dans `ADMIN_DISCORD_IDS`, puis :

```bash
pnpm discord:register   # enregistre les commandes admin sur ton serveur
pnpm dev:worker         # bot + tâches
```

Discord reste en **observation** : aucun rôle n'est modifié et aucun message n'est envoyé à tes membres réels. Seuls les comptes de test déclarés dans `/admin/discord` reçoivent les actions réelles.

## 11. Arrêter

`Ctrl` + `C` dans chaque terminal, puis `docker compose stop` pour arrêter la base. Tes données locales sont conservées.

## Dépannage

| Problème | Solution |
|---|---|
| `pnpm` n'est pas reconnu | Ferme et rouvre le terminal. Sinon : `npm install -g pnpm@10.28.0` |
| PowerShell : « l'exécution de scripts est désactivée sur ce système » | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, ou choisis **Command Prompt** dans la liste des terminaux de VS Code (flèche à côté du `+`) |
| `docker` : « error during connect » ou « Cannot connect to the Docker daemon » | Lance Docker Desktop et attends « Engine running » |
| `port is already allocated` sur 5432 | Un PostgreSQL est déjà installé sur ton PC : arrête-le, ou utilise-le directement (voir « Sans Docker ») |
| `pnpm db:migrate` : `ECONNREFUSED` | La base n'est pas démarrée : `docker compose up -d db` |
| Le port 3000 est déjà utilisé | Ferme l'autre application qui l'utilise (ou un ancien `pnpm dev:web` resté ouvert) |
| « Session inconnue ou expirée » | Relance `pnpm dev:login` (les sessions sont effacées si tu recrées la base) |
| La page se recharge en boucle au premier lancement | Attends la fin de la compilation ; si cela continue plus d'une minute, arrête le site (`Ctrl` + `C`) et relance `pnpm dev:web` |
| `.env existe déjà` | Normal : `pnpm setup:demo` ne remplace jamais ton fichier. `pnpm setup:demo --force` pour repartir de zéro |

### Sans Docker

Installe **PostgreSQL 16** (postgresql.org → Download, installateur EDB sous Windows). Pendant l'installation, choisis le mot de passe `postgres` pour l'utilisateur `postgres` et garde le port 5432. Crée ensuite la base `victorious` (avec pgAdmin, installé en même temps, ou `createdb -U postgres victorious`), puis lance `pnpm db:migrate`. Si tu choisis un autre mot de passe, modifie `DATABASE_URL` dans le fichier `.env`. Les tests, eux, ne lisent pas le `.env` : avant `pnpm test` ou `pnpm simulate`, indique l'adresse dans le terminal, par exemple sous PowerShell `$env:TEST_DATABASE_URL="postgres://postgres:TON_MOT_DE_PASSE@localhost:5432/postgres"`.

## Et ensuite ?

Mettre le site en ligne : [guide-deploiement.md](guide-deploiement.md). Railway se connecte à ton dépôt GitHub et redéploie automatiquement à chaque `git push`.
