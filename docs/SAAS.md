# Alpha Edge SaaS : l'espace de trading des membres

Le SaaS ajoute à la plateforme un espace de trading par membre, à l'adresse `/app/` :

- un journal de trading alimenté par MetaTrader 5 ;
- des statistiques honnêtes ;
- un Coach IA qui propose des leçons que le membre valide ;
- un Analyste de setup ICT dont les chiffres viennent d'un moteur déterministe ;
- un garde-fou de risque (limites de prop firm) et un Mentor sourcé sur les cours ;
- un laboratoire, une usine d'EA, des alertes TradingView et une API en lecture seule.

Tout tourne dans le même programme que le site et la console (`python -m hedgefund.web serve`), ou
en services séparés sous Docker.

> **Règle d'or.** Les moteurs calculent, les agents expliquent. Aucun chiffre affiché par un agent
> ne vient d'un modèle de langage ; aucun ordre ne part du SaaS. Voir `CLAUDE.md`.

---

## 1. Ce que voit le membre

| Page | Fonction | Offre minimale |
|---|---|---|
| `/app/` | Tableau de bord : 30 derniers jours, comportements repérés, leçons, garde-fou, dernières analyses, briefing ; champ libre qui oriente vers le bon service | Gratuit |
| `/app/journal/` | Comptes, import MT5 (rapport HTML ou CSV), saisie manuelle, notes par trade (setup, émotions, erreurs, note), statistiques avec intervalles de confiance | Gratuit (100 trades importés par mois) |
| `/app/revue/` | Coach IA : revue sur 7, 30 ou 90 jours, leçons à accepter, reformuler ou refuser, mémoire hebdomadaire modifiable | Gratuit (5 revues par mois) |
| `/app/analyse/` | Analyste ICT : graphique avec FVG, liquidité, zone d'entrée, invalidation et objectifs ; risk gate ; carte de décision valable 2 h ; briefing et calendrier ; webhooks TradingView | Starter (briefing), Pro Trader (TradingView) |
| `/app/risque/` | État des limites de perte (journalière, maximale), calculateur de taille, profils de prop firm | Gratuit (plan), Pro Trader (profils prop firm) |
| `/app/mentor/` | Questions de cours, réponses tirées des contenus avec leurs sources | Starter |
| `/app/labo/` | Monte Carlo sur vos R, rapport démo / réel, robustesse d'une stratégie (walk-forward, Sharpe déflaté), surveillance des EA | Pro Trader |
| `/app/ea/` | Usine EA : spécification → code MQL5 → revue par règles → compilation → model card → approbation pour la démo | Quant Elite |
| `/app/reglages/` | Plan de trading, profil, EA Journal Sync, mot de passe investisseur, Telegram, jetons d'API, export et effacement des données | Gratuit |

Les droits viennent du catalogue (`config/site.yaml`, champ `entitlements`) ; la correspondance
fonction → droit et les plafonds mensuels sont dans `config/saas.yaml`. Les plafonds limitent le coût
IA ; ce sont des hypothèses de départ à recaler après la bêta.

Côté opérateur, `/admin/` → **SaaS IA** affiche plusieurs blocs :

- l'état des tâches ;
- les exécutions et coûts des 24 dernières heures ;
- l'usage du mois et le manifeste de version ;
- la base de connaissances du Mentor ;
- l'import du calendrier et des actualités, et le déclenchement d'un briefing ;
- l'outil d'annotation du **golden set ICT**, avec la précision et le rappel du moteur.

---

## 2. Architecture

```
navigateur ──► FastAPI (hedgefund/web/app.py)
                 ├─ site statique (apps/web exporté dans hedgefund/web/site)
                 ├─ /api/app/*   routes membre   ── Access (offre, droits, plafonds)
                 ├─ /api/admin/* routes opérateur
                 ├─ /api/ingest/* EA Journal Sync, télémétrie (jeton Bearer)
                 ├─ /api/hooks/*  TradingView, Telegram (secret)
                 └─ /api/jobs/*   n8n (X-Jobs-Secret)
                        │
                        ▼
                 hedgefund/saas/  (un module par service, installé par modules.py)
                   journal, stats, ict, risk, coach, analyste, router, mentor, notify,
                   tradingview, research, scheduler, lab, sync, ea_factory, publicapi, overview
                        │
      ┌─────────────────┼──────────────────────────────┐
      ▼                 ▼                              ▼
 moteurs déterministes  graphes LangGraph (G1 à G4)    file de tâches durable (jobs)
 engines/perf.py        nœuds tracés (spans)           SKIP LOCKED sous PostgreSQL,
 engines/ict.py         interrupt() = décision humaine idempotence, priorités, reprise
 engines/risk.py        checkpoints PostgreSQL/SQLite
      │                 │
      └──────► outils typés (tools.py) ◄── modèles Claude (llm.py), sortie JSON stricte
                        │
                        ▼
                 garde-fous (guardrails.py) : entrée, sortie d'outil, sortie finale, ancrage des chiffres
```

- **Base** (`db.py`). SQLAlchemy Core. En production, PostgreSQL 16 avec *row-level security* forcée
  sur chaque table de tenant (`tenant_id = current_setting('app.tenant_id')`). Le code passe toujours
  par `Database.tenant(id)` (objet `Scoped`, qui filtre et renseigne `tenant_id`) : la RLS est une
  seconde barrière. SQLite en local, avec la même isolation par `Scoped`. Chaque membre a un tenant
  personnel `t_m{id}`.
- **Graphes** (`graphs.py`, LangGraph). Les graphes, leurs étapes et leur point de pause :

  | Graphe | Étapes | Pause avant |
  |---|---|---|
  | G1, Analyste | [ICT ‖ statistiques ‖ briefing] → synthèse → risk gate → débat (optionnel) → carte | la prise de connaissance |
  | G2, Usine EA | génération → revue → compilation → évaluation (boucle de 6 tours au plus, arrêt si les mêmes erreurs reviennent) → model card | l'approbation pour la démo |
  | G3, Coach | données → revue → leçons | la validation du membre, puis mémoire |
  | G4, Research | plan → [calendrier ‖ séries de prix ‖ actualités] → validation (nouveau plan si besoin) → briefing | — |

  Chaque nœud est une *span* : ce sont les étapes affichées en direct (SSE `/api/app/runs/{id}/stream`).
- **Modèles** (`llm.py`, `config/models.yaml`). Les modèles sont référencés par clé logique, avec des
  identifiants exacts :

  | Rôle | Modèle |
  |---|---|
  | Routeur | Haiku 4.5 |
  | Coach, Analyste, Mentor, Research, débat | Sonnet 5 |
  | Usine EA, juge | Opus 5 |

  Les sorties sont en JSON strict : le schéma Pydantic est converti en schéma fermé, avec une seule
  tentative de réparation. Budget par exécution : appels, jetons, délai, coût. Sans
  `ANTHROPIC_API_KEY`, chaque agent rend sa sortie déterministe avec un avertissement visible.
- **Garde-fous** (`guardrails.py`) :
  - en entrée : injection et données personnelles ;
  - sur les sorties d'outils : injection ;
  - en sortie finale : promesse de gain, instruction d'ordre, étiquette psychologique → blocage.
  - L'ancrage `ungrounded_numbers` refuse tout nombre absent des preuves.
- **Harnais** (`harness.py`) :
  - budget, reprise des seuls appels en lecture, disjoncteur, détection de non-progrès ;
  - manifeste de version : empreinte des modèles, des prompts, du code des outils et des moteurs ;
  - journal d'audit chaîné par tenant (`python -m hedgefund.saas verify-audit`).

---

## 3. Lancer en local

Le SaaS démarre avec la plateforme (désactivable par `HF_SAAS=0`). Sans configuration, il utilise
SQLite (`var/saas.db`), les prix simulés et aucun modèle.

```bash
python3 -m venv .venv
.venv/bin/pip install -e ".[web,saas,research]"
.venv/bin/python -m hedgefund.web create-user --username victor
HF_FEED=simulation HF_COOKIE_SECURE=0 .venv/bin/python -m hedgefund.web serve
```

Ouvrez http://127.0.0.1:8000, créez un compte membre, puis allez sur http://127.0.0.1:8000/app/.

Pour essayer l'espace de trading :

1. **Journal** → **Comptes et import** : créez un compte avec son solde de départ.
2. Importez le rapport HTML de MT5 : onglet Historique → clic droit → Rapport → HTML.
3. **Coach** → **Lancer la revue**.
4. Pour tester les offres payantes, accordez-en une au compte de test dans `/admin/` → **Membres**.

Avec un modèle :

```bash
export ANTHROPIC_API_KEY=...      # jamais dans le dépôt
export HF_SECRET_KEY=$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
```

`HF_SECRET_KEY` chiffre les mots de passe investisseur : gardez-la, sans elle ils sont illisibles.

### Commandes

| Commande | Rôle |
|---|---|
| `python -m hedgefund.saas init-db` | Crée les tables (et la RLS sous PostgreSQL) |
| `python -m hedgefund.saas worker --threads 4` | Exécute les tâches (graphes, briefings, revues) hors du serveur web |
| `python -m hedgefund.saas eval` | Scorecard de livraison (voir §7) |
| `python -m hedgefund.saas manifest` | Manifeste de version (modèles, empreintes des prompts, du code) |
| `python -m hedgefund.saas verify-audit --tenant t_m1` | Vérifie la chaîne d'audit d'un membre |
| `python -m hedgefund.saas bridge --every-min 15` | Pont MT5 en lecture seule (Windows, §5) |
| `python -m hedgefund.saas compile-server --metaeditor ... --experts ...` | Service de compilation MQL5 (Windows, §5) |
| `python -m hedgefund.saas mcp journal --tenant t_m1 --user 1` | Serveur MCP en lecture seule sur les données d'un membre (serveurs `journal`, `ict-engine`, `knowledge`, `risk`, `market-data`) |
| `python -m hedgefund.saas purge-jobs --days 30` | Purge des tâches terminées |

### Variables d'environnement

| Variable | Rôle |
|---|---|
| `HF_SAAS` | `0` désactive le SaaS |
| `HF_SAAS_DB` | URL de base (`postgresql+psycopg://…` en production ; défaut `sqlite:///var/saas.db`) |
| `HF_SAAS_WORKERS` | Fils de travail dans le serveur web (`0` si un worker séparé tourne) |
| `ANTHROPIC_API_KEY` | Clé des modèles ; absente = sorties déterministes. `HF_LLM=off` force ce mode |
| `HF_SECRET_KEY` | Clé Fernet des mots de passe investisseur |
| `HF_PUBLIC_URL` | URL publique (adresses affichées pour l'EA et TradingView) |
| `HF_JOBS_SECRET` | Secret des appels n8n vers `/api/jobs/*` |
| `HF_TELEGRAM_BOT_TOKEN`, `HF_TELEGRAM_BOT_NAME`, `HF_TELEGRAM_WEBHOOK_SECRET` | Notifications Telegram (facultatif) |
| `HF_MQL_COMPILER_URL`, `HF_MQL_COMPILER_TOKEN` | Service de compilation MQL5 sur le VPS Windows (facultatif) |
| `HF_CALENDAR_URL`, `HF_NEWS_FEEDS` | Sources du calendrier et des actualités (licences à vérifier) |
| `HF_FEED` | `simulation` ou `mt5` : prix utilisés par l'Analyste et le labo |

---

## 4. Déploiement (Docker Compose)

`docker-compose.yml` lance `postgres` (PostgreSQL 16), `api` (site, console, SaaS), `worker`,
`n8n` et `caddy` (HTTPS automatique). Il n'y a pas de Redis : la file de tâches est dans PostgreSQL.

```bash
cp deploy/docker/env.example .env      # puis remplissez-le ; .env n'est jamais commité
docker compose up -d
docker compose exec api python -m hedgefund.web create-user --username victor
docker compose exec api python -m hedgefund.saas eval --suite fast
```

`deploy/docker/init-db.sh` crée le rôle applicatif **non superutilisateur** `alphaedge` (NOBYPASSRLS) : un
superutilisateur ignore la RLS. Importez ensuite les workflows de `workflows/n8n/` (§6).

Le serveur Linux n'a pas MT5 : l'Analyste y travaille sur les prix simulés, et l'interface l'indique.
Pour des prix réels, faites tourner la plateforme sur le VPS Windows avec `HF_FEED=mt5`, ou alimentez
un flux de prix dédié.

---

## 5. MetaTrader 5 : trois façons d'alimenter le journal

Aucune ne peut passer d'ordre.

1. **Fichier** (toutes les offres). Importez le rapport HTML de MT5 ou un CSV. Les heures du serveur
   sont converties en UTC : UTC+2 en hiver, +3 en été, calendrier américain par défaut, réglable par
   compte.
2. **EA Journal Sync** (Pro Trader). Installation :
   - Dans **Réglages** → **Synchronisation MT5**, générez un jeton : il n'est affiché qu'une fois et
     remplace le précédent.
   - Dans MT5, autorisez WebRequest pour l'adresse de la plateforme.
   - Placez `mql5/JournalSync.mq5` sur un graphique, avec l'URL et le jeton.

   L'EA envoie les transactions, le solde, l'équité et le décalage horaire réel du serveur. Le
   garde-fou utilise alors l'équité en direct.
3. **Pont Windows** (`python -m hedgefund.saas bridge`). Il lit les comptes des membres qui ont confié
   leur mot de passe **investisseur**. Ce mot de passe est chiffré par `HF_SECRET_KEY` et le pont ne
   l'utilise qu'en lecture. Il ne peut appeler que des fonctions de lecture (liste blanche
   `ReadOnlyMT5`).

Pour la télémétrie des EA, incluez `mql5/AlphaEdgeTelemetry.mqh` : l'état, le spread et la dernière
erreur apparaissent dans **Labo** → **Surveillance des EA**.

**Compilation MQL5 (usine EA).** Sur le VPS Windows, lancez :

```
python -m hedgefund.saas compile-server --metaeditor "C:\Program Files\MetaTrader 5\metaeditor64.exe" --experts "%APPDATA%\MetaQuotes\Terminal\<id>\MQL5\Experts\AlphaEdge"
```

Ce service ne sait que compiler. Exposez-le au serveur par un tunnel privé, avec
`HF_MQL_COMPILER_URL` et `HF_MQL_COMPILER_TOKEN`. Sans lui, la revue par règles s'applique et la
compilation est marquée « non vérifiée ».

---

## 6. Tâches planifiées (n8n)

n8n déclenche, le backend décide. Chaque workflow de `workflows/n8n/` est un planning suivi d'un
appel `POST /api/jobs/*` avec l'en-tête `X-Jobs-Secret` :

- briefings avant Londres et New York ;
- revue hebdomadaire ;
- contrôle du garde-fou toutes les 15 minutes ;
- rafraîchissement des sources ;
- rappels de renouvellement.

Voir `workflows/n8n/README.md`.

---

## 7. Évaluer avant de livrer

```bash
python -m pytest -q                         # tests (aucun appel réseau : ScriptedClient, fake_mt5)
python -m hedgefund.saas eval               # scorecard : LIVRABLE ou BLOQUÉ
ruff check hedgefund tests --select F,E9,B --ignore B905,B008
python scripts/check_secrets.py
```

La scorecard (`hedgefund/saas/evals.py`, `evals/redteam.yaml`) bloque la livraison si une métrique
**catastrophique** échoue :

- un chemin d'ordre existe dans le SaaS ;
- des données fuient entre tenants ;
- un chiffre non ancré dans les preuves est affiché ;
- une attaque de l'équipe rouge passe (conseil personnalisé, promesse, injection, étiquette
  psychologique) ;
- le moteur ICT « voit » une bougie non clôturée.

La CI exécute tout cela sur PostgreSQL 16 avec un rôle non superutilisateur, pour tester la RLS
réelle.

**Golden set ICT.** Dans `/admin/` → **SaaS IA**, un analyste annote des graphiques réels :

- swings, FVG, prises de liquidité, MSS ;
- jeu `dev` pour régler le moteur, jeu `holdout` pour la validation finale.

La précision et le rappel s'affichent par définition versionnée (`victor-v0`). Le jeu synthétique
vérifie le moteur à chaque test ; il ne remplace pas des annotations réelles.

Fiches des agents : `docs/model_cards/`.

---

## 8. Sécurité et données

- **Lecture seule vers les brokers.** Aucun module du SaaS n'importe de fonction d'ordre (vérifié par
  la scorecard). Les ordres restent dans la console, derrière ses 3 verrous, avec le numéro magique
  770077.
- **Décisions humaines.** Les étapes qui engagent le membre attendent une action explicite et laissent
  une trace d'audit : leçons, carte de setup, EA en démo.
- **Secrets.** Les jetons (EA, API, TradingView) sont stockés hachés et affichés une seule fois. Le
  mot de passe investisseur est chiffré. Aucun identifiant n'entre dans un prompt, une trace ou un
  journal.
- **Droits du membre.** Il peut exporter ses données en JSON et les effacer (`EFFACER MES DONNEES`).
  L'effacement conserve le journal d'audit, qui ne contient que des requêtes expurgées.
- **Pas de promesse.** Aucune performance, aucun témoignage, aucune promesse de gain : les garde-fous
  bloquent ces formulations et les textes du site n'en contiennent pas.
- **Copytrading réel.** Il est retiré des offres (ADR-011, réversible) : le copytrading réel et les
  signaux sont des activités réglementées ; le copytrading reste en démo.

---

## 9. Limites connues

- **Profils de prop firm.** Tous marqués « à vérifier » (`verified_at: null` dans
  `config/prop_firms.yaml`) : ils doivent être confrontés au règlement officiel en vigueur avant qu'on
  s'y fie.
- **Checkpoints LangGraph.** Ils sont hors RLS (tables du checkpointer), indexés par identifiant
  d'exécution aléatoire. L'accès passe toujours par `agent_runs`, qui est sous RLS.
- **Prix simulés sous Linux.** Les analyses sont alors des démonstrations, signalées comme telles.
- **Calendrier et actualités.** Imports manuels ou sources à licencier ; un briefing sans source
  indique « données insuffisantes ».
- **Débat contradictoire (G1).** Il existe mais est désactivé (`analysis.debate: false`) tant que son
  effet n'est pas mesuré.
- **Non testé dans ce dépôt.** Appels réels aux modèles (tests sur client scripté), compilation
  MetaEditor, terminal MT5 réel, déploiement Docker complet.

## 10. Carte des fichiers

| Chemin | Contenu |
|---|---|
| `hedgefund/saas/` | services, graphes, outils, garde-fous, harnais, file de tâches, API |
| `hedgefund/saas/engines/` | moteurs déterministes : performance, ICT, risque |
| `hedgefund/saas/prompts/` | prompts versionnés (empreinte dans le manifeste) |
| `config/saas.yaml`, `config/models.yaml`, `config/prop_firms.yaml` | offres et plafonds, modèles, profils de prop firm |
| `apps/web/src/app/app/` | pages de l'espace de trading ; composants dans `apps/web/src/components/app-*.tsx` |
| `apps/web/src/app/admin/saas.tsx` | section opérateur |
| `mql5/JournalSync.mq5`, `mql5/AlphaEdgeTelemetry.mqh` | EA de synchronisation et module de télémétrie (lecture seule) |
| `tradingview/alpha_edge_ict.pine` | indicateur d'alertes TradingView |
| `workflows/n8n/` | plannings |
| `evals/`, `tests/test_saas_*.py` | équipe rouge, tests |
| `.claude/skills/` | fiches de référence (définitions ICT, conventions MQL5, protocole de backtest, prop firms) |
