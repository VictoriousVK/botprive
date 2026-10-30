# CLAUDE.md : Liberté Financière

Plateforme de Victor Faye et Khalifa Diop : site Liberté Financière (offres payées avec Wave,
académie vidéo, formation ICT, coach IA, copytrading démo, espace membre, administration) et
console de trading Alpha Edge (robots MT5). L'opérateur **ne code pas** : explique en
français simple, propose un plan avant les gros changements, et vérifie toujours ton travail.

## Lire d'abord

- `docs/PRD.md` : quoi et pour qui · `docs/TRD.md` : architecture, sécurité, variables
- `docs/APP_FLOW.md` : pages et parcours · `docs/UI_UX_DESIGN.md` + `DESIGN.md` : design
- `docs/BACKEND_SCHEMA.md` : tables, droits, routes · `docs/IMPLEMENTATION.md` : plan, tâches
- `apps/web/AGENTS.md` : cette version de Next.js diffère de ce que tu connais ; lis
  `apps/web/node_modules/next/dist/docs/` avant de changer le front.

## Commandes

```bash
pip install -e ".[research,web,dev,monitoring]"      # Python ≥ 3.11
pytest -q                                            # doit rester vert (193+ tests)
HF_FEED=simulation HF_COOKIE_SECURE=0 python -m hedgefund.web serve   # http://127.0.0.1:8000
python -m hedgefund.web create-user --username vic   # opérateur (console + /admin/)
cd apps/web && npm ci && npm run lint                # TypeScript
cd apps/web && npm run publish-site                  # OBLIGATOIRE après tout changement du front
```

En local sans SMTP, les liens de confirmation d'e-mail sont écrits dans la sortie du serveur.

## Règles non négociables

1. **Jamais** de performance, témoignage, partenaire ou statistique inventés ; aucune
   promesse de gain. Tout résultat affiché indique sa source (simulation, papier, MT5).
2. Mode **paper** : ne pas activer l'argent réel ni la copie réelle (`LF_COPYTRADING=live`).
3. Sécurité : ne pas affaiblir CSRF, CSP, cookies, limites de tentatives, confirmation
   d'e-mail, ni le nettoyage Sentry. Les liens d'e-mail n'utilisent jamais l'en-tête Host.
4. Aucun secret dans le dépôt (clés, liens d'invitation privés) : variables d'environnement
   ou `/admin/` → Réglages.
5. Droits : vérifier un **entitlement** (`coach_ia`, `formation_ict`…), jamais le nom d'une
   offre. Un compte non confirmé n'a aucun droit.
6. Toute nouvelle table/colonne : migration idempotente + test depuis une ancienne base
   (BACKEND_SCHEMA §4). Sauvegarder `var/` avant déploiement.
7. Textes visibles en **français**, vouvoiement, messages d'erreur du serveur en français.
8. Le Coach IA répond depuis `hedgefund/coach/knowledge/` : pour corriger une réponse,
   corrige ou ajoute une fiche, ne contourne pas les règles du prompt (pas de signal de
   trading, dire « hors base »).

## Design

Respecte `DESIGN.md` (tokens de `apps/web/src/app/globals.css`, composants existants). Si les
skills sont installées, utilise `design-taste-frontend`, `redesign-existing-projects`,
`web-design-guidelines` et `image-to-code`. Vérifie chaque écran modifié avec Playwright
(MCP) à 390 px et 1 360 px et regarde la console.

## Où sont les choses

- API membres/admin : `hedgefund/members/api.py` ; logique : `hedgefund/members/service.py`
- E-mails : `hedgefund/members/mailer.py` ; anti-robots : `hedgefund/members/antibot.py`
- Coach : `hedgefund/coach/` ; Sentry : `hedgefund/web/observability.py`
- App FastAPI, CSP, console : `hedgefund/web/app.py` ; auth : `hedgefund/web/security.py`
- Offres et prix : `config/site.yaml` ; pages : `apps/web/src/app/<route>/{page,view}.tsx`

## Fin de tâche

Résume en français ce qui a changé et pourquoi, les commandes de vérification lancées et leur
résultat, et ce que l'opérateur doit faire (réglage, redémarrage). Mets à jour
`docs/IMPLEMENTATION.md`.
