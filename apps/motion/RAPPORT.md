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

Machine de rendu : 4 cœurs, sans carte graphique (rendu logiciel de Chromium), Remotion 4.0.534.

### Film principal (`AlphaEdgeFilm`)

| Contrôle | Résultat |
|---|---|
| Rendu | 4 morceaux (`--segments 2900`) à 2,1 à 2,3 images/s, soit environ 1 h 10 de calcul ; assemblage et bande son : 16 s |
| Fichier maître | 1920 × 1080, 30 i/s, 291,4 s (4 min 51), 8 742 images comptées, H.264 + AAC 192 kb/s |
| Version de diffusion | 159 Mo, 4,4 Mb/s, `yuv420p` BT.709 plage vidéo ; tous les contrôles de `npm run qc` au vert |
| Version légère (`npm run share`) | 29,4 Mo, 1080p, 0,8 Mb/s, deux passes ; texte net vérifié sur les plans en mouvement |
| Raccords entre morceaux | images identiques de part et d'autre des coupures (96,7 s, 193,3 s, 290,0 s) |
| Son | crête −2,6 dBFS, niveau moyen −18,1 dBFS, aucun blanc de plus de 1,5 s |
| Planches d'images | 37 images (une toutes les 8 s) relues : pas de texte coupé ni débordant, sous-titres lisibles et jamais superposés, bandeau « Démonstration » et mention « Prix simulés » visibles |

### Version courte (`AlphaEdgePromo`) et format vertical (`AlphaEdgeVertical`)

| Contrôle | Version courte | Format vertical |
|---|---|---|
| Rendu | 1,6 image/s, environ 14 min | 1,7 image/s, environ 14 min |
| Fichier | 1920 × 1080, 44,3 s, 1 329 images, 64,5 Mo | 1080 × 1920, 47,8 s, 1 434 images, 61,3 Mo |
| Copie légère | 25,8 Mo | 25,9 Mo |
| `npm run qc` | tous les contrôles au vert (BT.709, `yuv420p`) | tous les contrôles au vert (BT.709, `yuv420p`) |
| Son | crête −2,8 dBFS, moyenne −17,5 dBFS | crête −2,5 dBFS, moyenne −17,3 dBFS |
| Planches | 15 images relues, aucun défaut | 24 images relues après correction (voir ci-dessous) |

**Défauts trouvés sur le format vertical et corrigés avant livraison** :

- écran « Ses règles, en clair » : la zone visée sur téléphone n'était que l'intitulé du bloc ; le
  zoom maximal coupait les valeurs à droite (« 5 % », « minuit »). La capture vise maintenant le
  bloc entier, comme sur ordinateur ;
- écran d'inscription : le bouton « Continuer » tombait juste sous le bord de l'écran du téléphone,
  le clic se faisait hors champ. La capture est prise en pleine page et le cadrage montre le
  formulaire jusqu'au bouton.

L'éclair lumineux de 0,5 s sur l'apparition du logo (les trois films) est voulu, synchronisé avec
l'impact sonore ; un seul éclair, loin des seuils de photosensibilité (trois par seconde).

**Correction apportée pendant le contrôle** : le premier fichier maître sortait en `yuvj420p`
(couleurs JPEG plein écart, matrice BT.601), mal interprété par certains lecteurs et plateformes.
Les rendus sortent désormais en BT.709 plage vidéo (`colorSpace: "bt709"`) ; le film déjà rendu a
été converti (matrice et plage), sans écart de teinte mesurable sur l'or de la marque.

**Incident de rendu** : le rendu du son du film entier par le navigateur a saturé la mémoire vers
l'image 5 022. Le son est désormais mixé en Node (`scripts/mix.ts`, mêmes niveaux que la
composition) et le film se rend en morceaux reprenables.
