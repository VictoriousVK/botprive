# PRD : Liberté Financière (v0.4)

> Product Requirements Document. **Ce que** le produit doit faire et **pour qui**. Le **comment**
> est dans [TRD.md](TRD.md), les parcours dans [APP_FLOW.md](APP_FLOW.md), le design dans
> [UI_UX_DESIGN.md](UI_UX_DESIGN.md), les données dans [BACKEND_SCHEMA.md](BACKEND_SCHEMA.md) et
> le plan de travail dans [IMPLEMENTATION.md](IMPLEMENTATION.md).

| | |
|---|---|
| Produit | Liberté Financière (site + espace membre), Alpha Edge SaaS (espace de trading des membres : journal, Coach, Analyste ICT, garde-fou de risque, Mentor) et la console de trading Alpha Edge (opérateurs) |
| Fondateurs | Victor Faye (trading ICT, robots MT5, IA), Khalifa Diop |
| Marché | Traders francophones d'Afrique de l'Ouest et centrale, paiement mobile (Wave) |
| Version | 0.4.0 (octobre 2026) |
| Statut | En production privée ; copytrading et trading réel des membres fermés |

---

## 1. Vision

Donner aux traders francophones africains **une méthode (ICT), des outils (journal, Analyste ICT,
robots MT5, Coach et Mentor IA) et un cadre (académie, communauté, gestion du risque)** sur une seule plateforme, payable avec
Wave, sans promesse de gain et avec des résultats affichés uniquement depuis des sources
vérifiables.

## 2. Problème

1. Les formations de trading en ligne sont chères, en anglais, payables par carte bancaire et
   souvent remplies de promesses de gains invérifiables.
2. Les débutants passent d'un groupe Telegram à l'autre sans méthode ni gestion du risque.
3. Les traders ICT intermédiaires manquent d'un cadre structuré, d'outils d'automatisation
   (EA MT5) et de réponses fiables à leurs questions entre deux lives.
4. Les cofondateurs gèrent aujourd'hui inscriptions, paiements et accès à la main (WhatsApp,
   Discord), ce qui ne passe pas à l'échelle.

## 3. Utilisateurs

| Persona | Qui | Ce qu'il veut | Offre type |
|---|---|---|---|
| **Awa, débutante** | 24 ans, Dakar, smartphone, Wave, découvre le trading | Apprendre sans se faire arnaquer, petits montants | Compte gratuit → Starter |
| **Moussa, trader ICT intermédiaire** | 30 ans, trade l'or et le Nasdaq sur MT5, connaît OB/FVG | Structurer sa méthode, lives, questions-réponses | Formation Victorious Trader, Pro Trader, Groupe Elite |
| **Ibrahima, membre avancé** | Veut automatiser, intéressé par les EA et la data | Robots, Coach et Mentor IA, laboratoire de backtest | Quant Elite, licences EA |
| **Victor / Khalifa, opérateurs** | Fondateurs, peu de temps, pas développeurs | Encaisser, donner les accès, publier des cours, voir ce qui casse | Console + `/admin/` + Sentry |

## 4. Périmètre fonctionnel

Légende : ✅ en production · 🆕 livré en v0.4 · 🔜 prévu · ⛔ volontairement fermé

| Module | Fonction | État |
|---|---|---|
| **Site public** | Accueil, formation ICT, robots, copytrading (vitrine), académie, offres, risques | ✅ |
| **Compte membre** | Inscription, connexion, 2FA (opérateurs), espace membre | ✅ |
| | Confirmation d'e-mail obligatoire avant la première connexion | 🆕 |
| | Mot de passe oublié par e-mail | 🆕 |
| | Protection anti-robots (piège invisible, e-mails jetables refusés, limite par IP, Cloudflare Turnstile optionnel) | 🆕 |
| **Offres et paiement** | Abonnements 1/3/12 mois, formations à vie, cumul des accès | ✅ |
| | Wave Checkout (API) ou transfert Wave manuel validé dans l'admin | ✅ |
| | Orange Money, carte bancaire, PayPal | 🔜 |
| | Relance avant expiration de l'abonnement (e-mail) | 🔜 |
| **Académie** | Cours vidéo multi-parties, chapitres, progression, aperçus gratuits | ✅ |
| **Formation ICT** | Programme Victorious Trader (16 modules), achat Wave | ✅ |
| **Mentor IA** | Questions-réponses sur ICT et la formation : 15 fiches ICT 🆕, définitions du moteur, cours de l'académie ; sources affichées, quota mensuel par offre | ✅ (fiches 🆕) |
| **Robots** | Catalogue public des EA, console de création/backtest/démarrage (opérateurs) | ✅ |
| | Licences EA vendues aux membres | 🔜 (quand les performances seront vérifiées) |
| **Copytrading** | Démo (aucun ordre réel), stop sur drawdown | ✅ |
| | Copie sur compte réel | ⛔ jusqu'à l'avis d'un avocat |
| **Administration** | Paiements à valider, membres, accès, cours, stratégies, prospects, réglages | ✅ |
| | Confirmation manuelle d'un e-mail, compteur d'inscriptions en attente | 🆕 |
| | SaaS IA : questions posées au Mentor, filtre « à couvrir » (hors des contenus, ou jugées partielles par l'IA) | 🆕 |
| **Supervision** | Sentry : erreurs serveur et site, performances, alertes | 🆕 (activé par une clé) |
| **Espace de trading (SaaS, `/app/`)** | Mise en route guidée, tableau de bord, journal (import MT5 HTML/CSV, saisie, notes), statistiques avec marges d'erreur | ✅ |
| | Coach IA (revue 7/30/90 jours, écarts au plan, leçons à valider), Analyste de setup ICT, garde-fou prop firm et calculateur de taille | ✅ |
| | Synchronisation MT5 (EA Journal Sync), alertes TradingView, briefing de pré-session, laboratoire, usine EA, API en lecture seule | ✅ |
| | Import des relevés TopstepX / Tradovate (futures) | 🔜 |
| **Démonstration** | `python -m hedgefund.web demo` : données fictives, bandeau « Démonstration », film de présentation (`apps/motion`) | ✅ |

## 5. Exigences détaillées

Priorités : **P0** indispensable · **P1** important · **P2** confort.

### 5.1 Comptes et anti-bots (P0)

- R1. Une inscription crée un compte **en attente** ; aucune session n'est ouverte et aucun
  droit n'est donné avant le clic sur le lien reçu par e-mail.
- R2. Le lien est à usage unique, valable 48 h ; seul le dernier lien envoyé fonctionne.
- R3. Renvoyer le lien est possible depuis l'écran d'attente et depuis la connexion, sans
  révéler si une adresse a un compte. Limite : 4 e-mails par adresse et par heure.
- R4. Une inscription jamais confirmée peut être refaite avec la même adresse (faute de frappe,
  e-mail perdu) ; elle est supprimée après 7 jours si aucun paiement n'y est attaché.
- R5. Les adresses jetables connues sont refusées ; l'opérateur peut en ajouter
  (`LF_BLOCKED_EMAIL_DOMAINS`).
- R6. Un champ piège invisible bloque les robots de formulaire sans les prévenir.
- R7. Cloudflare Turnstile s'active par configuration, sans changer le code.
- R8. « Mot de passe oublié » : lien à usage unique, 60 minutes, ferme toutes les sessions.
- R9. Les liens des e-mails utilisent l'adresse publique configurée, jamais l'en-tête Host de
  la requête (anti-détournement de lien).
- R10. Les comptes créés avant la v0.4 restent actifs (considérés comme confirmés).

### 5.2 Mentor IA : les questions ICT (P1)

Un seul assistant répond aux questions sur ICT et la formation : le **Mentor** de l'espace de
trading (`/app/mentor/`). L'ancienne page `/coach/` y renvoie.

- R11. Ouvert au droit `academy_member` (Starter, Pro Trader, Quant Elite) ; les autres membres
  voient l'offre.
- R12. Le Mentor répond depuis les **fiches ICT** versionnées dans le dépôt
  (`hedgefund/saas/fiches_ict/`), les définitions du moteur et les cours de l'académie, filtrés
  selon les droits du membre ; il dit quand une question sort des contenus et n'invente ni
  horaire, ni chiffre, ni citation (tout chiffre affiché doit figurer dans un passage cité).
- R13. Chaque réponse affiche les passages utilisés.
- R14. Aucun signal de trading ni conseil personnalisé : une telle demande reçoit un refus
  explicite.
- R15. Quota mensuel par offre (`config/saas.yaml` : Starter 60, Pro Trader 120, Quant Elite 300
  questions) et plafond de coût IA par membre.
- R16. L'opérateur voit les questions (sans nom ni e-mail) et filtre celles « à couvrir » pour
  écrire les fiches manquantes.
- R17. Sans IA (pas de clé, plafond atteint, fournisseur indisponible), le membre reçoit les
  passages les plus proches tels quels, avec un avertissement visible ; rien ne casse.

### 5.3 Supervision (P1)

- R18. Toute erreur serveur non gérée et toute erreur JavaScript du site remontent dans Sentry
  avec la version, l'environnement et la route.
- R19. Aucun mot de passe, cookie, jeton CSRF, corps de requête, jeton d'e-mail ni adresse
  e-mail n'est envoyé à Sentry. Seul l'identifiant numérique du membre peut l'être.
- R20. Sans clé Sentry, la plateforme fonctionne à l'identique.

### 5.4 Règles non négociables (P0, déjà en place)

- Aucune performance, témoignage ou partenaire inventé ; aucune promesse de gain.
- Les résultats affichés viennent du journal de la plateforme avec leur source (simulation,
  papier, MT5).
- La copie sur compte réel reste fermée jusqu'à l'avis d'un avocat.
- Les liens d'invitation privés (Telegram, Discord) ne sont jamais dans le dépôt.

## 6. Indicateurs de succès

| Indicateur | Définition | Cible à 3 mois |
|---|---|---|
| Inscriptions confirmées / semaine | `members.email_verified_at` sur 7 jours | suivi |
| Taux de confirmation | confirmées ÷ inscriptions | > 60 % |
| Comptes robots bloqués | événements `signup_blocked` du journal + domaines refusés | suivi |
| Conversion gratuit → payant | membres avec un accès payant ÷ membres confirmés | > 5 % |
| Revenu encaissé (30 j) | carte « Encaissé (30 j) » de l'admin | suivi |
| Rétention abonnés | abonnés renouvelés ÷ abonnés arrivés à échéance | > 50 % |
| Usage du Mentor | questions/mois, % de membres abonnés actifs | suivi |
| Qualité du Mentor | % de questions « à couvrir » (hors des contenus, ou jugées partielles par l'IA) | < 10 % |
| Fiabilité | nouvelles erreurs Sentry/semaine ; incidents de paiement | baisse continue |

## 7. Hors périmètre (v0.4)

- Application mobile native (le site est responsive).
- Paiement par carte bancaire.
- Copie de trades sur comptes réels des membres.
- Conseil en investissement personnalisé ou signaux automatiques envoyés aux membres.

## 8. Risques et questions ouvertes

| Risque | Mesure |
|---|---|
| Réglementation (copytrading, conseil en investissement) | Copie réelle fermée, avertissements, avis juridique à obtenir |
| Délivrabilité des e-mails (spams) | Fournisseur SMTP sérieux (Brevo/Resend), domaine vérifié (SPF, DKIM, DMARC) |
| Coût de l'IA | Quota mensuel par offre, plafond de coût par membre, modèles fixés dans `config/models.yaml` |
| Réponses du Mentor inexactes | Fiches de référence relues par Victor, passages affichés, chiffres vérifiés, revue des questions à couvrir |
| Dépôt GitHub public | Stratégies réservées hors du dépôt ; passer le dépôt en privé |
| Un seul PC Windows héberge tout | Sauvegarde de `var/`, Sentry Uptime sur `/api/health` |

Questions ouvertes : politique de remboursement ; date d'ouverture d'Orange Money ; relecture
des fiches ICT et des définitions du moteur par Victor.
