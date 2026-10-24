# V_ICT_ORIOUS Membership

Site vitrine, paiements et automatisation des accès Discord du **V_ICT_ORIOUS Live Club**.

- Inscription avec connexion Discord (OAuth2), paiement en FCFA par Mobile Money ou carte.
- Rôle Discord attribué automatiquement après confirmation **serveur à serveur** du paiement.
- Renouvellement calé sur la date d'activation (le 12 → le 12, fin de mois gérée).
- Rappels J-3 / J-1 / J0 (message privé Discord et email), délai de grâce, retrait du rôle, restauration au paiement suivant.
- Carte bancaire : renouvellement automatique (Flutterwave, avec consentement explicite). Mobile Money : renouvellement par rappel avec lien en 1 clic.
- Commandes admin Discord (`/abonne`, `/ajouter`, `/retirer`, `/expirations`, `/stats`), salon de logs, réconciliation quotidienne, import CSV.

## Où en est le projet

| Élément | État | Preuve |
|---|---|---|
| Base de données, machine à états, calcul des dates | ✅ Fait | Tests automatisés (Postgres réel) |
| File de tâches persistante, reprise après redémarrage | ✅ Fait | Test 6 |
| Webhooks idempotents, signature, re-vérification | ✅ Fait | Test 3, contre un faux serveur Flutterwave/Wave |
| Rôles Discord, panne Discord, réconciliation, exceptions | ✅ Fait | Tests 4, 5 et 8 (faux Discord) |
| Site, tunnel d'inscription, espace membre, pages légales | ✅ Fait | Parcours navigateur réel (Playwright) avec le faux serveur de paiement |
| Images Docker site et worker | ✅ Construites et lancées localement | — |
| Flutterwave / Wave **réels** (sandbox) | ⏳ À tester | Phase 5 : nécessite tes comptes marchands |
| Discord **réel** (bot, OAuth) | ⏳ À tester | Nécessite ton application Discord |
| Déploiement Railway | ⏳ À faire ensemble | [Guide](docs/guide-deploiement.md) |

Rien n'a encore été testé contre les vraies API Flutterwave, Wave ou Discord. Le code suit leurs documentations, mais certains points sont signalés « à confirmer en sandbox » dans le [guide des paiements](docs/guide-paiements.md).

## Architecture

```
apps/web        Next.js : site vitrine, connexion Discord, paiement, espace membre, webhooks (/api/webhooks/*)
apps/worker     Process permanent : bot discord.js (commandes, arrivées), tâches, passages planifiés, réconciliation
packages/core   Logique métier : config du club, dates, machine à états, prestataires de paiement, notifications
packages/db     Schéma Postgres (Drizzle) et migrations SQL versionnées
scripts/        Simulation, import CSV, faux prestataires, envoi de webhooks, création des plans Flutterwave
docs/           Architecture, guides Discord / paiements / déploiement, checklist de mise en production
legacy/         Ancien outil Streamlit « ICT Pure Master » (hors projet)
```

Détails : [docs/architecture.md](docs/architecture.md).

**Tarifs, durées, délai de grâce, rappels et textes du club** : un seul fichier, [`packages/core/src/config/club.ts`](packages/core/src/config/club.ts).
**Secrets et identifiants** : `.env` uniquement (modèle commenté : [`.env.example`](.env.example)).

## Démarrer en local

Prérequis : Node 22, pnpm 10 (`corepack enable`), Docker.

```bash
pnpm install
cp .env.example .env            # puis compléter (voir commentaires)
docker compose up -d db         # Postgres local
pnpm db:migrate                 # crée les tables
pnpm test                       # 60 tests (crée des bases jetables)
pnpm simulate                   # rejoue tout le cycle sans vrai paiement
```

Pour essayer le site sans compte marchand, utilise les faux prestataires (valeurs à mettre dans `.env`, voir la fin de `.env.example`) :

```bash
pnpm mock:providers             # faux Flutterwave + Wave sur http://127.0.0.1:4010
pnpm dev:web                    # http://localhost:3000
pnpm dev:worker                 # bot + tâches (nécessite une application Discord)
```

## Commandes utiles

| Commande | Rôle |
|---|---|
| `pnpm test` | Tests automatisés (TEST_DATABASE_URL, défaut : Postgres local) |
| `pnpm typecheck` | Vérification des types de tout le monorepo |
| `pnpm simulate` | Simulation complète (paiement, rappels, grâce, retrait, restauration, carte récurrente, panne Discord) |
| `pnpm webhook:send …` | Envoie un webhook signé, falsifié (`--forge`) ou rejoué (`--replay`) à l'application locale |
| `pnpm import:members fichier.csv [--apply]` | Import des membres actuels (simulation par défaut) |
| `pnpm discord:register` | Enregistre les commandes admin sur ton serveur |
| `pnpm flw:create-plans [--apply]` | Crée les plans récurrents Flutterwave des 3 formules |
| `pnpm db:generate` | Génère une migration après modification du schéma |

## Guides

1. [Configuration du bot Discord](docs/guide-discord.md)
2. [Configuration des paiements](docs/guide-paiements.md)
3. [Déploiement](docs/guide-deploiement.md)
4. [Checklist de mise en production](docs/checklist-production.md)

## Sécurité, en bref

- L'accès n'est jamais accordé par la page « paiement réussi » : il faut un webhook signé, puis une re-vérification auprès du prestataire (montant, devise, référence).
- Webhooks idempotents : un événement reçu deux fois ne prolonge qu'une fois (contraintes d'unicité en base).
- Sessions : jeton aléatoire en cookie `HttpOnly` / `SameSite=Lax`, seule son empreinte est stockée. Contrôle d'origine sur les formulaires, limitation de débit, en-têtes de sécurité (CSP, HSTS…).
- Aucun secret côté navigateur ni dans les logs. Journal d'audit en base pour chaque action (paiement, rôle, commande admin).
- Dépendances : versions figées, publiées depuis au moins 14 jours (sauf correctifs de sécurité). Audit du 24/10/2026 : aucune vulnérabilité haute ou critique ; 2 avis mineurs sur esbuild, limités aux outils de développement.
