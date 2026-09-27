# Workflows n8n

n8n **déclenche**, le backend **décide** (ADR-008) : chaque workflow est un planning suivi d'un seul
appel HTTP vers `/api/jobs/*`, avec le secret `X-Jobs-Secret` et une clé d'idempotence. Aucune règle
métier ici.

| Fichier | Quand | Appel |
|---|---|---|
| `briefing-londres.json` | 01:30 New York, lundi-vendredi | `POST /api/jobs/briefing` (london) |
| `briefing-new-york.json` | 06:30 New York, lundi-vendredi | `POST /api/jobs/briefing` (new_york) |
| `revue-hebdomadaire.json` | dimanche 18:00 New York | `POST /api/jobs/weekly-reviews` |
| `garde-fou.json` | toutes les 15 minutes en semaine | `POST /api/jobs/guard-check` |
| `sources.json` | toutes les 2 heures | `POST /api/jobs/sources-refresh` |
| `renouvellements.json` | 09:00 Dakar | `POST /api/jobs/renewals` |

Import : n8n → Workflows → Import from file. Variables d'environnement de n8n : `ALPHA_EDGE_URL`
(ex. `http://api:8000` dans Docker Compose) et `HF_JOBS_SECRET` (le même que celui de la plateforme).
Les workflows sont importés désactivés : activez-les après un premier test manuel.
