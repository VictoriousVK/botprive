# Alpha Edge — rapport de production des films

## 1. Audit du produit (avant tout tournage)

Le produit a été inspecté et **lancé** en mode démonstration (`python -m hedgefund.web demo`).
Chaque écran du film provient de ce lancement : `npm run capture` le refait automatiquement.

**Pile technique** : API et serveur FastAPI (Python), site et espace de trading en Next.js 16
(export statique servi par la plateforme), console de trading en HTML/JS, SaaS
`hedgefund/saas` (SQLAlchemy, LangGraph, SDK Anthropic), paiements Wave, MetaTrader 5 côté Windows.

**Identité** : noir profond, accents bleu et or, emblème Liberté Financière, nom de plateforme
« Alpha Edge » (console), polices Montserrat, Inter, JetBrains Mono. Le film reprend les polices et
l'emblème (teinté or, réglable dans `src/content/brand.ts`) et adopte la palette noir, or, blanc.

### Fonctions entièrement opérationnelles (vérifiées en démonstration)

| Espace | Fonction | Dans le film |
|---|---|---|
| Site | Accueil, formation ICT, robots, académie, copytrading, offres, risques | oui (accueil, offres, académie, formation ICT) |
| Compte | Inscription en deux temps, connexion, espace membre, paiements | oui |
| Mise en route | Profil, prop firm (règles par taille), plan de risque, premier compte | oui |
| Tableau de bord | Performance 30 jours, comportements, leçons, garde-fou, killzones | oui |
| Journal | Import MT5 (HTML, CSV), saisie, notes par trade, statistiques avec marges d'erreur | oui |
| Coach | Revue 7/30/90 jours, écarts mesurés, leçons à accepter / reformuler / refuser | oui |
| Analyse ICT | Graphique, niveaux, carte de décision, risk gate, briefing, alertes TradingView | oui |
| Risque | État des limites, objectifs d'évaluation, calculateur (contrats futures), profils | oui |
| Laboratoire | Monte Carlo, démo / réel, robustesse (walk-forward, Sharpe déflaté), suivi des EA | oui |
| Réglages | Plan, profil, notifications Telegram, EA Journal Sync, API lecture seule, données | oui |
| Administration | Paiements Wave (validation), membres, académie, SaaS IA, réglages, alertes | oui |
| Console Alpha Edge | Tableau de bord, bots, stratégies, backtest, modes, verrous du réel, limites | oui |

### Fonctions partielles (un élément externe manque en démonstration)

| Fonction | Ce qui manque | Comment le film le traite |
|---|---|---|
| Textes du Coach, du Mentor, de l'Analyste rédigés par l'IA | une clé Anthropic | les écrans montrent la version « rédigée par les règles » (mêmes chiffres) ; la narration ne prétend pas le contraire |
| Mentor | les vidéos de la formation (pas encore en ligne) et la clé IA | le film cadre la question et les sources, pas le texte brut des passages |
| Usine EA | une clé IA (génération) et MetaEditor sous Windows (compilation) | interface montrée ; la narration précise les deux prérequis |
| Prix et ordres réels | MetaTrader 5 sous Windows | tout est sur prix simulés, signalé à l'écran (« Prix simulés · démonstration ») |
| Profils prop firm | relecture humaine des règlements | mention « À vérifier » visible et commentée |
| Groupes privés Telegram / Discord | liens d'invitation (réglés dans l'admin) | montrés depuis l'écran de réglage de l'administration |

### Fonctions prévues, absentes du film principal

- Import des relevés TopstepX / Tradovate (futures) : à construire, un export d'exemple est attendu.
- Copytrading réel (encadrement juridique), Orange Money, carte bancaire, PayPal (« bientôt »).
- Paiement Wave automatique (Wave Business) : le code existe, non activé.
- Générateur de vidéos de trading : n'existe pas dans le produit, donc absent du film.

## 2. Ce que le film montre, et ce qu'il ne dit jamais

- **Données** : comptes, trades, paiements et prix sont fictifs ; le bandeau « Démonstration » du
  produit est visible sur chaque écran, et la narration le dit dès le tableau de bord.
- **Résultats** : aucun résultat de trading n'est présenté comme réel. Le seul backtest montré
  (console) affiche lui-même « Données simulées. Ce résultat teste la mécanique, pas la
  rentabilité. » ; la narration le répète.
- **Promesses** : aucune promesse de gain ; la signature mentionne le risque de perte en capital.
- **Illustrations** : l'explication ICT (liquidité, prise de liquidité, cassure de structure, fair
  value gap) est un dessin pédagogique, étiqueté « Illustration pédagogique », distinct de l'écran
  réel de l'Analyste qui suit.
- **Alerte Telegram** : le texte reproduit exactement le format envoyé par la plateforme
  (`hedgefund/members/alerts.py`), avec des valeurs de démonstration ; aucun logo de marque tierce.
- **Ordres** : le film rappelle que le SaaS est en lecture seule et que le réel reste derrière
  trois verrous dans la console.

## 3. Limites connues

- **Voix off** : aucune voix n'est enregistrée (pas de service de synthèse configuré). Le texte est
  porté par des sous-titres incrustés ; le script minuté (`VOIX-OFF.fr.md`) et les SRT sont prêts,
  et une voix déposée dans `public/audio/` est intégrée automatiquement (musique baissée dessous).
- **Musique** : synthétisée par code (aucun droit à acquérir), sobre ; un compositeur peut la
  remplacer fichier pour fichier.
- **Mentor sans IA** : renvoie des passages bruts, peu lisibles à l'écran ; à revoir dans le produit
  (mise en forme du repli sans modèle), hors du périmètre de ce travail.
- **4K** : prévue (`--4k`), non rendue ici (temps de calcul sur une machine sans carte graphique).
- **Avertissement Remotion** « The source image cannot be decoded » : affiché pour les très grandes
  captures pleine page ; sans effet, l'image est chargée et rendue (vérifié sur les images de contrôle).

## 4. Contrôle qualité

Voir la section suivante, complétée après les rendus.
