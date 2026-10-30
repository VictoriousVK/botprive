# Règles du dépôt (Claude Code et contributeurs)

Ce dépôt contient la plateforme de trading Alpha Edge (console, bots MT5), le site Liberté
Financière (membres, paiements Wave, académie) et le SaaS (`hedgefund/saas/` : journal,
analyse ICT, garde-fou de risque, agents IA dont le Mentor). Plateforme de Victor Faye et Khalifa
Diop. L'opérateur **ne code pas** : explique en français simple, propose un plan avant les gros
changements, et vérifie toujours ton travail.

## Lire d'abord

- `docs/PRD.md` : quoi et pour qui · `docs/TRD.md` : architecture, sécurité, variables
- `docs/APP_FLOW.md` : pages et parcours · `docs/UI_UX_DESIGN.md` + `DESIGN.md` : design
- `docs/BACKEND_SCHEMA.md` : tables, droits, routes · `docs/IMPLEMENTATION.md` : plan, tâches
- `docs/SAAS.md` (espace de trading), `docs/PLATFORM.md`, `docs/SITE.md`, `docs/DEMARRAGE.md`,
  `docs/DEMO.md`
- `apps/web/AGENTS.md` : cette version de Next.js diffère de ce que tu connais ; lis
  `apps/web/node_modules/next/dist/docs/` avant de changer le front.

## Non négociable

- **Aucun calcul numérique métier ne sort d'un LLM.** Les moteurs déterministes (`hedgefund/saas/engines/`,
  `hedgefund/strategy/library/ict_core.py`, `hedgefund/risk/`) calculent ; les agents expliquent. Tests d'abord
  pour les moteurs.
- **Tout chiffre affiché par un agent vient d'un outil** : la vérification `ungrounded_numbers` bloque
  le reste (métrique catastrophique de la scorecard).
- **Aucun ordre sans approbation humaine.** Le SaaS est en lecture seule sur les comptes des clients. Les
  ordres restent dans la console, derrière les 3 verrous, avec le numéro magique **770077** uniquement.
  Mode **paper** : ne pas activer l'argent réel ni la copie réelle (`LF_COPYTRADING=live`).
- **Aucun compte administrateur par défaut.** Les comptes se créent en ligne de commande.
- **Le dépôt est public** : jamais de secret, de mot de passe, de clé d'API, ni de lien d'invitation
  privé (Telegram `t.me/+…`, Discord `discord.gg/…`) dans le code, la configuration, les tests ou les
  commits. Les liens se règlent dans `/admin/` → Réglages ou par variables d'environnement.
- **Aucune performance inventée**, aucun témoignage, aucun partenaire, aucune promesse de gain, dans le
  code comme dans les textes du site. Tout résultat affiché indique sa source (simulation, papier, MT5).
- Sécurité : ne pas affaiblir CSRF, CSP, cookies, limites de tentatives, confirmation d'e-mail, ni le
  nettoyage Sentry. Les liens d'e-mail n'utilisent jamais l'en-tête Host.
- Droits : vérifier un **entitlement** (`academy_member`, `formation_ict`…), jamais le nom d'une offre.
  Un compte non confirmé n'a aucun droit.
- Isolation des clients : toute table de tenant passe par `Database.tenant()` / `Scoped` ; jamais de
  requête brute sans filtre `tenant_id`. Sous PostgreSQL, la RLS est une seconde barrière, pas la seule.
- Les identifiants broker et secrets ne sont jamais visibles d'un modèle, d'une trace ou d'un log.
- Toute nouvelle table/colonne de la plateforme : migration idempotente + test depuis une ancienne
  base (`docs/BACKEND_SCHEMA.md` §4). Sauvegarder `var/` avant un déploiement.

## Agents

- Chaque agent a un schéma d'entrée et de sortie (`hedgefund/saas/schemas.py`), un prompt versionné
  (`hedgefund/saas/prompts/*.md`), des évaluations, et entre dans le manifeste de version **avant** le merge.
- Modèles référencés par clé logique via `config/models.yaml` (IDs exacts) ; jamais d'alias flottant.
- Un agent sans LLM disponible renvoie sa sortie déterministe avec un caveat visible, jamais un texte inventé.
- Toute action d'écriture vers un broker ou un tiers passe par une file d'approbation avec clé d'idempotence.
- Les questions ICT passent par le **Mentor** (un seul assistant). Pour corriger ou enrichir ses réponses,
  corrige ou ajoute une fiche dans `hedgefund/saas/fiches_ict/` (voir son README), en accord avec les
  définitions du moteur (skill `ict-definitions`) ; ne contourne pas ses garde-fous (pas de conseil
  personnalisé, dire « hors des contenus »).

## Commandes

```bash
pip install -e ".[research,web,saas,dev,monitoring]"   # Python ≥ 3.11
python -m pytest -q                                    # doit rester vert ; scorecard : python -m hedgefund.saas eval
HF_FEED=simulation HF_COOKIE_SECURE=0 python -m hedgefund.web serve   # http://127.0.0.1:8000
python -m hedgefund.web demo                           # démonstration sur données fictives (docs/DEMO.md)
python -m hedgefund.web create-user --username vic     # opérateur (console + /admin/)
ruff check hedgefund tests scripts --select F,E9,B --ignore B905,B008
python scripts/check_secrets.py
cd apps/web && npm ci && npm run lint                  # TypeScript
cd apps/web && npm run publish-site                    # OBLIGATOIRE après tout changement du front
```

En local sans SMTP, les liens de confirmation d'e-mail sont écrits dans la sortie du serveur. Pas
d'appel réseau dans les tests unitaires (clients factices : `ScriptedClient`, `tests/fake_mt5.py`).
PostgreSQL de test (RLS) : `HF_TEST_PG_URL=postgresql+psycopg://user:pass@localhost/db`, rôle **non
superutilisateur** (un superutilisateur ignore la RLS).

## Design

Respecte `DESIGN.md` (tokens de `apps/web/src/app/globals.css`, composants existants). Textes visibles
en **français**, vouvoiement, messages d'erreur du serveur en français. Si les skills sont installées
(`scripts/install-claude-tools.ps1`), utilise `design-taste-frontend`, `redesign-existing-projects`,
`web-design-guidelines` et `image-to-code`. Vérifie chaque écran modifié avec Playwright à 390 px et
1 360 px et regarde la console.

## Où sont les choses

- API membres/admin : `hedgefund/members/api.py` ; logique : `hedgefund/members/service.py`
- E-mails : `hedgefund/members/mailer.py` ; anti-robots : `hedgefund/members/antibot.py`
- Espace de trading : `hedgefund/saas/` (Mentor : `mentor.py`, `knowledge.py`, `fiches_ict/`)
- Sentry : `hedgefund/web/observability.py` ; app FastAPI, CSP, console : `hedgefund/web/app.py`
- Offres et prix : `config/site.yaml` ; fonctions et quotas : `config/saas.yaml` ; modèles : `config/models.yaml`
- Pages : `apps/web/src/app/<route>/{page,view}.tsx` (`/app/` = espace de trading)
- Film de présentation : `apps/motion/` (isolé du produit)

## Fin de tâche

Petites PR, un sujet par PR, messages de commit explicites. Demander confirmation avant toute opération
destructive (suppression de données, réécriture d'historique). Résume en français ce qui a changé et
pourquoi, les commandes de vérification lancées et leur résultat, et ce que l'opérateur doit faire
(réglage, redémarrage). Mets à jour `docs/IMPLEMENTATION.md`.
