# V_ICT_ORIOUS Membership

Site vitrine, paiements, tableau de bord et automatisation des accès Discord du **V_ICT_ORIOUS Live Club**.

- Inscription avec connexion Discord (OAuth2), paiement en FCFA par Mobile Money ou carte (Flutterwave, PayDunya, Wave Business).
- Rôle Discord attribué après confirmation **serveur à serveur** du paiement ; renouvellement calé sur la date d'activation.
- Carte : prélèvement automatique (Flutterwave, avec consentement explicite). Mobile Money : renouvellement assisté (rappels J-3, J-1, J0 avec lien en 1 clic).
- **Tableau de bord `/admin`** : tarifs, validation des tarifs, horaires des lives, lien Telegram (public ou réservé aux membres), mode Discord, membres, paiements, import CSV, journal.
- Bot Discord : commandes admin, salon de logs, rappels, délai de grâce, retrait puis restauration du rôle, réconciliation quotidienne.

## Garde-fous actifs par défaut

| Garde-fou | Effet |
|---|---|
| `PAYMENT_MODE=test` | Aucun encaissement réel possible : des clés ou adresses réelles sont écartées automatiquement, et un bandeau « mode test » s'affiche sur le site |
| Aucun prix prédéfini | Les montants FCFA se saisissent dans `/admin/tarifs`. Une formule sans prix n'est pas achetable ; en mode réel, les tarifs doivent être **validés** |
| Discord en **observation** | Aucun rôle modifié et aucun message envoyé à tes membres réels : les actions sont simulées et journalisées. Passage en réel depuis `/admin/discord` (confirmation « ACTIVER »). Des comptes de test peuvent recevoir les actions réelles |

## Où en est le projet

| Élément | État | Preuve |
|---|---|---|
| Base, machine à états, dates, file de tâches | ✅ | Tests automatisés (Postgres réel) |
| Webhooks idempotents, signatures, re-vérification | ✅ | Tests contre un faux serveur Flutterwave / Wave / PayDunya |
| Rôles, panne Discord, réconciliation, mode observation | ✅ | Tests (faux Discord) |
| Site, espace membre, tableau de bord, import CSV | ✅ | Parcours navigateur réel (Playwright) |
| Connexion Discord (OAuth2) | ✅ | Testée contre un faux serveur Discord |
| Images Docker site et worker | ✅ | Construites et lancées localement |
| Flutterwave / PayDunya **en sandbox réelle** | ⏳ | Nécessite tes comptes en mode test ([comparatif](docs/comparatif-prestataires.md)) |
| **Prélèvement automatique réel** | ⏳ **Non opérationnel** tant que Flutterwave n'est pas validé et testé (dont le FCFA pour les plans) | — |
| Discord réel, déploiement | ⏳ | [Guide Discord](docs/guide-discord.md), [déploiement](docs/guide-deploiement.md) |

Ce qu'il reste à fournir avant la production : [docs/informations-a-fournir.md](docs/informations-a-fournir.md).

## Architecture

```
apps/web        Next.js : site, connexion Discord, paiement, espace membre, tableau de bord /admin, webhooks
apps/worker     Process permanent : bot discord.js, tâches, passages planifiés, réconciliation
packages/core   Logique métier : formules, réglages, dates, machine à états, prestataires, notifications
packages/db     Schéma Postgres (Drizzle) et migrations SQL versionnées
scripts/        Simulation, import CSV, faux prestataires, envoi de webhooks, plans Flutterwave, sauvegarde
assets/affiches Tes affiches (affichées automatiquement sur l'accueil)
docs/           Guides
legacy/         Ancien outil Streamlit « ICT Pure Master » (hors projet)
```

Détails : [docs/architecture.md](docs/architecture.md).

## Démarrer en local

Pas à pas (Windows compris), avec les tâches VS Code prêtes à l'emploi : **[docs/guide-vscode.md](docs/guide-vscode.md)**.

Prérequis : Node 22, pnpm 10 (`corepack enable` ; sous Windows `npm install -g pnpm@10.28.0`), PostgreSQL 16 (installé directement ou via Docker).

```bash
pnpm install
pnpm setup:demo                 # .env de démonstration (faux paiements) ; pour la production, partir de .env.example
docker compose up -d db         # Postgres local (inutile si PostgreSQL est installé directement)
pnpm db:migrate                 # crée les tables
pnpm test                       # 81 tests (bases jetables)
pnpm simulate                   # rejoue tout le cycle sans vrai paiement
pnpm mock:providers             # faux Flutterwave / Wave / PayDunya sur http://127.0.0.1:4010
pnpm dev:web                    # http://localhost:3000 (tableau de bord : /admin)
pnpm dev:login [--membre]       # lien de connexion locale sans Discord (admin, ou membre de test)
pnpm dev:worker                 # bot + tâches (nécessite une application Discord)
```

## Commandes utiles

| Commande | Rôle |
|---|---|
| `pnpm test` / `pnpm typecheck` | Tests automatisés / vérification des types |
| `pnpm simulate` | Simulation complète du cycle d'abonnement |
| `pnpm webhook:send …` | Webhook signé, falsifié (`--forge`) ou rejoué (`--replay`) vers l'application locale |
| `pnpm import:members fichier.csv [--apply]` | Import des membres actuels (aperçu par défaut) |
| `pnpm discord:register` | Enregistre les commandes admin sur ton serveur |
| `pnpm flw:create-plans [--apply]` | Crée les plans Flutterwave aux prix du tableau de bord |
| `pnpm db:generate` | Génère une migration après modification du schéma |

## Guides

| Sujet | Guide |
|---|---|
| Lancer le projet sur VS Code | [guide-vscode.md](docs/guide-vscode.md) |
| RCCM et NINEA | [guide-administratif.md](docs/guide-administratif.md) |
| Flutterwave ou PayDunya | [comparatif-prestataires.md](docs/comparatif-prestataires.md) |
| Configuration des paiements | [guide-paiements.md](docs/guide-paiements.md) |
| Bot Discord | [guide-discord.md](docs/guide-discord.md) |
| Tableau de bord | [tableau-de-bord.md](docs/tableau-de-bord.md) |
| Import des membres | [guide-import-membres.md](docs/guide-import-membres.md) |
| Nom de domaine | [guide-domaine.md](docs/guide-domaine.md) |
| Déploiement | [guide-deploiement.md](docs/guide-deploiement.md) |
| Mise en production | [checklist-production.md](docs/checklist-production.md) |

## Sécurité, en bref
- L'accès n'est jamais accordé par la page « paiement réussi » : il faut une notification authentifiée, puis une re-vérification auprès du prestataire (montant, devise, référence).
- Notifications idempotentes : un événement reçu deux fois ne prolonge qu'une fois.
- Sessions en cookie `HttpOnly` / `SameSite=Lax` (empreinte seule en base), contrôle d'origine, limitation de débit, en-têtes de sécurité (CSP, HSTS…).
- Tableau de bord limité aux identifiants Discord de `ADMIN_DISCORD_IDS`, chaque route vérifiée. Toute modification est journalisée.
- Dépendances figées ; audit du 24/10/2026 : aucune vulnérabilité haute ou critique.
