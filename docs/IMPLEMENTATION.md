# Implementation Plan : faire évoluer Liberté Financière avec Claude Code

> Le plan de travail, phase par phase, avec pour chaque tâche **la demande à copier dans
> Claude Code** et **la définition de « terminé »**. À lire avec [PRD.md](PRD.md) (quoi),
> [TRD.md](TRD.md) (comment), [APP_FLOW.md](APP_FLOW.md), [UI_UX_DESIGN.md](UI_UX_DESIGN.md) et
> [BACKEND_SCHEMA.md](BACKEND_SCHEMA.md).

## 0. Méthode de travail (à suivre à chaque tâche)

1. **Une tâche à la fois**, sur une branche Git : `git checkout -b feat/nom-court`.
2. Ouvrir Claude Code dans le dossier du projet. Il lit `CLAUDE.md` automatiquement.
3. Commencer en **mode plan** (Maj+Tab deux fois) : « Lis docs/IMPLEMENTATION.md, tâche X.
   Propose un plan, ne code pas encore. » Valider ou corriger le plan.
4. Laisser coder, puis exiger les vérifications :
   `pytest -q` · `cd apps/web && npm run lint && npm run publish-site` · captures Playwright
   à 390 px et 1 360 px.
5. Relire le résumé, tester soi-même dans le navigateur (mode simulation), puis commit :
   « Commit avec un message clair en français ».
6. Mettre à jour la ligne de la tâche dans ce fichier (✅ + date).

Règles d'or : ne jamais coller une clé API dans le chat ; toujours sauvegarder `var/` avant
de déployer ; une erreur Sentry nouvelle après un déploiement = revenir à la version
précédente (`git checkout <tag>`), puis corriger.

## 1. Phase 1 : sécurité des inscriptions et supervision ✅ (v0.4, octobre 2026)

| # | Tâche | État |
|---|---|---|
| 1.1 | Confirmation d'e-mail obligatoire, lien 48 h à usage unique, renvoi du lien | ✅ |
| 1.2 | Mot de passe oublié (lien 60 min, ferme les sessions) | ✅ |
| 1.3 | Anti-robots : piège invisible, domaines jetables, limite/IP, Turnstile optionnel, purge 7 j | ✅ |
| 1.4 | Admin : confirmer un e-mail, compteur d'inscriptions en attente | ✅ |
| 1.5 | Sentry serveur + site, données nettoyées | ✅ |
| 1.6 | Questions ICT : 15 fiches ICT dans le Mentor (un seul assistant), `/coach/` → `/app/mentor/`, questions à couvrir dans `/admin/` → SaaS IA | ✅ |
| 1.7 | `.mcp.json` (Playwright, Sentry), script d'installation des skills, `DESIGN.md`, 6 documents | ✅ |
| 1.8 | Intégration dans le projet complet (SaaS, démo, film) : inscription en deux temps avec confirmation, mot de passe oublié, démo sans e-mail | ✅ |
| 1.9 | 316 tests automatiques | ✅ |

**À faire par l'opérateur** : [MISE_EN_ROUTE_V0.4.md](MISE_EN_ROUTE_V0.4.md) (SMTP, Sentry,
clé Anthropic, Turnstile) puis [CLAUDE_CODE_OUTILS.md](CLAUDE_CODE_OUTILS.md).

## 2. Phase 2 : conversion et confiance (priorité suivante)

| # | Tâche | Demande à Claude Code | Terminé quand |
|---|---|---|---|
| 2.1 | E-mail de bienvenue après confirmation | « Ajoute un e-mail de bienvenue envoyé après la confirmation d'adresse (modèle dans hedgefund/members/mailer.py, même style). Contenu : accès gratuit, lien académie, lien offres. Ajoute un test. » | e-mail reçu, test vert |
| 2.2 | Reçu de paiement par e-mail | « Après chaque paiement crédité (_apply), envoie un reçu : offre, durée, montant FCFA, date de fin, référence. Test avec FakeWave. » | reçu reçu pour Wave API et manuel |
| 2.3 | Relance avant expiration | « Ajoute une tâche quotidienne qui envoie un e-mail 3 jours avant la fin d'un abonnement mensuel, une seule fois par échéance (nouvelle table reminders). Tests avec horloge simulée. » | pas de doublon, test vert |
| 2.4 | Accueil : U1 | « Applique U1 de docs/UI_UX_DESIGN.md avec les skills design-taste-frontend et web-design-guidelines. Captures Playwright avant/après. » | validé visuellement mobile + desktop |
| 2.5 | Tarifs : U2 | idem pour U2 | idem |
| 2.6 | Page Contact / support (U7) | « Crée /contact/ : WhatsApp, e-mail, FAQ paiement Wave, délais de validation. Respecte DESIGN.md. Ajoute le lien au pied de page. » | page publiée, liens OK |
| 2.7 | Robots : mention « simulation » (U9) | « Vérifie que chaque résultat de robot affiche sa source ; ajoute une puce Simulation/Papier/MT5. » | aucune courbe sans source |

## 3. Phase 3 : valeur pour les membres

| # | Tâche | Demande | Terminé quand |
|---|---|---|---|
| 3.1 | Section « Continuer » dans l'espace membre (U3) | « Dans /compte/, ajoute en haut : dernier cours en cours (course_progress), accès au Mentor, prochain live (texte dans site.yaml). » | visible et utile sur mobile |
| 3.2 | Progression par cours (U5) | « Ajoute une barre de progression par cours dans /academie/ et un badge Terminé. » | progression juste |
| 3.3 | Journal de trading membre | ✅ déjà livré dans l'espace de trading (`/app/journal/` : import MT5 HTML/CSV, saisie, notes, statistiques, export) | — |
| 3.4 | Calendrier économique | En partie livré : l'équipe importe le calendrier (`/admin/` → SaaS IA) et le briefing de pré-session l'utilise. Reste : « Propose une source automatique fiable des annonces US/EUR, heures NY et GMT, à valider avec moi. » | source validée par Victor |
| 3.5 | Mentor : fiches supplémentaires | « Lis /admin/ → SaaS IA → Questions posées au Mentor (à couvrir). Écris les fiches manquantes dans hedgefund/saas/fiches_ict/, une par sujet, format README, puis réindexe. » | % à couvrir < 10 % |
| 3.6 | Import TopstepX / Tradovate | « Ajoute l'import des relevés TopstepX et Tradovate au journal, à partir de l'export d'exemple que je te donne. » | trades futures importés avec leur contrat |

## 4. Phase 4 : paiements et croissance

| # | Tâche | Notes |
|---|---|---|
| 4.1 | Orange Money | via un agrégateur (CinetPay, PayDunya…) : à choisir selon frais et API ; même modèle que Wave (relire le paiement côté serveur avant crédit) |
| 4.2 | Codes promo | table `coupons`, appliqués au prix XOF, journalisés |
| 4.3 | Parrainage | lien de parrainage, mois offert, anti-abus (e-mail confirmé obligatoire) |
| 4.4 | Licences EA | quand les performances MT5 sont vérifiées (règle du PRD) |

## 5. Phase 5 : fiabilité

| # | Tâche | Notes |
|---|---|---|
| 5.1 | Sauvegarde automatique de `var/` | tâche planifiée Windows, copie datée hors du PC (cloud) |
| 5.2 | Retirer ou sécuriser `app.py` (Streamlit) | mot de passe par défaut et SHA-256 non salé |
| 5.3 | Passer le dépôt GitHub en privé | protège stratégies et fiches ICT |
| 5.4 | Durée de conservation des questions au Mentor (registre d'audit chaîné) | conformité données |
| 5.5 | Sentry Crons pour le moteur de bots | alerte si la boucle s'arrête |

## 6. Définition de « terminé » (toutes tâches)

- [ ] `pytest -q` vert, nouveaux tests pour le nouveau comportement.
- [ ] `npm run lint` vert ; `npm run publish-site` lancé si le front a changé.
- [ ] Captures Playwright 390 px et 1 360 px sans erreur console.
- [ ] Textes en français simple, conformes à DESIGN.md et à APP_FLOW §9 (états vides/erreurs).
- [ ] Aucune donnée sensible dans les journaux ni dans Sentry.
- [ ] Docs mises à jour (BACKEND_SCHEMA si tables/routes, PRD si périmètre).
- [ ] Commit sur une branche, puis fusion.

## 7. Déployer une nouvelle version (PC Windows)

```powershell
# 1. Sauvegarde
Copy-Item -Recurse var "..\sauvegarde-var-$(Get-Date -Format yyyyMMdd-HHmm)"
# 2. Mise à jour du code
git pull
.\.venv\Scripts\python.exe -m pip install -e ".[web,saas,mt5,research,monitoring]"
# 3. Tests
.\.venv\Scripts\python.exe -m pytest -q
# 4. Redémarrage
.\deploy\windows\start.ps1
```

Puis : ouvrir le site, faire le parcours de la checklist de
[MISE_EN_ROUTE_V0.4.md §6](MISE_EN_ROUTE_V0.4.md#6-vérification-finale), surveiller Sentry
pendant 24 h.

**Retour arrière** : arrêter, `git checkout <version précédente>`, restaurer la sauvegarde de
`var/` si le schéma a changé, redémarrer.
