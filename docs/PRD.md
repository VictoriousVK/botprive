# PRD : Liberté Financière (v0.4)

> Product Requirements Document. **Ce que** le produit doit faire et **pour qui**. Le **comment**
> est dans [TRD.md](TRD.md), les parcours dans [APP_FLOW.md](APP_FLOW.md), le design dans
> [UI_UX_DESIGN.md](UI_UX_DESIGN.md), les données dans [BACKEND_SCHEMA.md](BACKEND_SCHEMA.md) et
> le plan de travail dans [IMPLEMENTATION.md](IMPLEMENTATION.md).

| | |
|---|---|
| Produit | Liberté Financière (site + espace membre) et Alpha Edge (console de trading) |
| Fondateurs | Victor Faye (trading ICT, robots MT5, IA), Khalifa Diop |
| Marché | Traders francophones d'Afrique de l'Ouest et centrale, paiement mobile (Wave) |
| Version | 0.4.0 (octobre 2026) |
| Statut | En production privée ; copytrading et trading réel des membres fermés |

---

## 1. Vision

Donner aux traders francophones africains **une méthode (ICT), des outils (robots MT5, coach IA)
et un cadre (académie, communauté, gestion du risque)** sur une seule plateforme, payable avec
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
| **Ibrahima, membre avancé** | Veut automatiser, intéressé par les EA et la data | Robots, coach IA, laboratoire de backtest | Quant Elite, licences EA |
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
| **Coach IA ICT** | Questions-réponses sur ICT depuis une base de référence, sources affichées, quota/jour | 🆕 |
| **Robots** | Catalogue public des EA, console de création/backtest/démarrage (opérateurs) | ✅ |
| | Licences EA vendues aux membres | 🔜 (quand les performances seront vérifiées) |
| **Copytrading** | Démo (aucun ordre réel), stop sur drawdown | ✅ |
| | Copie sur compte réel | ⛔ jusqu'à l'avis d'un avocat |
| **Administration** | Paiements à valider, membres, accès, cours, stratégies, prospects, réglages | ✅ |
| | Confirmation manuelle d'un e-mail, compteur d'inscriptions en attente | 🆕 |
| | Onglet Coach IA : questions posées et questions « hors base » | 🆕 |
| **Supervision** | Sentry : erreurs serveur et site, performances, alertes | 🆕 (activé par une clé) |
| **Membres avancés** | Dashboard de performance, journal de trading, connexion MT5, calendrier économique | 🔜 |

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

### 5.2 Coach IA (P1)

- R11. Réservé au droit `coach_ia` (offre Quant Elite) ; les autres membres voient l'offre.
- R12. Le coach répond depuis une base de fiches ICT versionnée dans le dépôt ; il dit quand
  une question sort de la base et n'invente ni horaire, ni chiffre, ni citation.
- R13. Chaque réponse affiche les fiches utilisées.
- R14. Aucun signal de trading ni conseil personnalisé ; rappel visible sous la zone de saisie.
- R15. Quota par membre et par jour (30 par défaut, configurable) pour maîtriser le coût.
- R16. L'opérateur voit les questions et filtre celles « hors base » pour enrichir la base.
- R17. Si le fournisseur IA est indisponible, le membre reçoit un message clair, rien ne casse.

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
| Usage du coach | questions/jour, % de membres Quant Elite actifs | suivi |
| Qualité du coach | % de questions « hors base » | < 10 % |
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
| Coût de l'IA | Quota par membre, base mise en cache, modèle configurable |
| Réponses du coach inexactes | Base de référence, sources affichées, revue des questions hors base |
| Dépôt GitHub public | Stratégies réservées hors du dépôt ; passer le dépôt en privé |
| Un seul PC Windows héberge tout | Sauvegarde de `var/`, Sentry Uptime sur `/api/health` |

Questions ouvertes : prix et périmètre exacts de l'accès au coach (Pro Trader aussi ?) ;
politique de remboursement ; date d'ouverture d'Orange Money.
