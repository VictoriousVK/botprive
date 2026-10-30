# Gestion du risque, journal et psychologie

## Risque par trade

- Risquer un **pourcentage fixe et petit** du capital par trade. ICT recommande de rester
  modeste (il parle souvent de 1 % ou moins) et de **réduire le risque après une perte** (par
  exemple le diviser par deux) jusqu'à ce que les gains reviennent.
- Calcul de la taille de position : taille = montant risqué ÷ (distance du stop × valeur du
  point).
  Exemple : compte de 1 000 $, risque 1 % = 10 $. Or, stop à 5 $ de distance. Sur un lot
  standard d'or (100 onces), 1 $ de variation = 100 $ ; donc 0,01 lot = 1 $ par dollar de
  variation, soit 5 $ pour 5 $ de stop. Pour risquer 10 $ : **0,02 lot**. (Vérifier la taille
  de contrat de son broker : elle varie.)
- Fixer une **perte maximale journalière** (par exemple 2 trades perdants ou 2 % : on arrête
  pour la journée) et respecter les règles des **prop firms** (perte journalière et
  drawdown maximal).

## Ratio et sorties

- Viser des objectifs logiques (liquidité opposée), pas un ratio arbitraire. Un trade dont la
  cible donne moins de 1:2 est souvent à éviter.
- **Prises partielles** sur les niveaux intermédiaires (FVG, sommet de session), le reste vers
  la cible principale.
- Monter le stop au point d'entrée trop tôt fait souvent sortir avant le mouvement ; certains
  attendent une nouvelle cassure de structure en leur faveur.

## Journal et backtest

- Noter chaque trade : date, heure NY, actif, biais, liquidité prise, PD array, entrée, stop,
  cible, résultat en R, capture d'écran avant et après, émotion.
- Calculer le taux de réussite, le gain moyen en R, la perte moyenne, l'espérance.
- **Backtester** un modèle sur au moins plusieurs dizaines d'occurrences avant de le trader en
  réel, puis le valider en **démo**.

## Psychologie

- Le problème principal n'est pas la méthode mais la discipline : **sur-trading**, revenge
  trading, déplacer son stop, augmenter la taille après une perte.
- Règle simple : pas de setup complet = pas de trade. Il est normal de ne pas trader certains
  jours.
- Le trading comporte un risque élevé de perte. Ne tradez jamais l'argent dont vous avez
  besoin pour vivre.
