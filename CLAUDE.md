# Règles du dépôt (Claude Code et contributeurs)

Ce dépôt contient la plateforme de trading Alpha Edge (console, bots MT5), le site Liberté
Financière (membres, paiements Wave, académie) et le SaaS (`hedgefund/saas/` : journal,
analyse ICT, garde-fou de risque, agents IA). Documentation : `docs/SAAS.md`, `docs/PLATFORM.md`,
`docs/SITE.md`, `docs/DEMARRAGE.md`.

## Non négociable

- **Aucun calcul numérique métier ne sort d'un LLM.** Les moteurs déterministes (`hedgefund/saas/engines/`,
  `hedgefund/strategy/library/ict_core.py`, `hedgefund/risk/`) calculent ; les agents expliquent. Tests d'abord
  pour les moteurs.
- **Tout chiffre affiché par un agent vient d'un outil** : la vérification `ungrounded_numbers` bloque
  le reste (métrique catastrophique de la scorecard).
- **Aucun ordre sans approbation humaine.** Le SaaS est en lecture seule sur les comptes des clients. Les
  ordres restent dans la console, derrière les 3 verrous, avec le numéro magique **770077** uniquement.
- **Aucun compte administrateur par défaut.** Les comptes se créent en ligne de commande.
- **Le dépôt est public** : jamais de secret, de mot de passe, de clé d'API, ni de lien d'invitation
  privé (Telegram `t.me/+…`, Discord `discord.gg/…`) dans le code, la configuration, les tests ou les
  commits. Les liens se règlent dans `/admin/` → Réglages ou par variables d'environnement.
- **Aucune performance inventée**, aucun témoignage, aucune promesse de gain, dans le code comme dans les
  textes du site.
- Isolation des clients : toute table de tenant passe par `Database.tenant()` / `Scoped` ; jamais de
  requête brute sans filtre `tenant_id`. Sous PostgreSQL, la RLS est une seconde barrière, pas la seule.
- Les identifiants broker et secrets ne sont jamais visibles d'un modèle, d'une trace ou d'un log.

## Agents

- Chaque agent a un schéma d'entrée et de sortie (`hedgefund/saas/schemas.py`), un prompt versionné
  (`hedgefund/saas/prompts/*.md`), des évaluations, et entre dans le manifeste de version **avant** le merge.
- Modèles référencés par clé logique via `config/models.yaml` (IDs exacts) ; jamais d'alias flottant.
- Un agent sans LLM disponible renvoie sa sortie déterministe avec un caveat visible, jamais un texte inventé.
- Toute action d'écriture vers un broker ou un tiers passe par une file d'approbation avec clé d'idempotence.

## Pratique

- Tests : `python -m pytest -q` ; la scorecard : `python -m hedgefund.saas eval`. Pas d'appel réseau dans
  les tests unitaires (clients factices : `ScriptedClient`, `tests/fake_mt5.py`).
- PostgreSQL de test (RLS) : `HF_TEST_PG_URL=postgresql+psycopg://user:pass@localhost/db` ; rôle **non
  superutilisateur** (un superutilisateur ignore la RLS).
- Lint : `ruff check hedgefund tests --select F,E9,B --ignore B905,B008`.
- Petites PR, un sujet par PR, messages de commit explicites. Demander confirmation avant toute opération
  destructive (suppression de données, réécriture d'historique).
