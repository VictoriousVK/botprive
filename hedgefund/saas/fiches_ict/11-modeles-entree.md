# Modèles d'entrée ICT : modèle 2022, Silver Bullet, OTE, Market Maker

Tous suivent la même logique : **biais → liquidité prise → déplacement → entrée dans un PD
array → stop au-delà de l'invalidation → objectif sur la liquidité opposée**.

## Modèle du mentorship 2022

1. **Biais et cible** sur l'unité de temps supérieure (H1/H4/Daily) : quel est le draw on
   liquidity ?
2. **Attendre une killzone** (Londres ou NY AM).
3. **Prise de liquidité** contre le biais : pour un achat, le prix passe sous un creux
   (SSL : creux de session, PDL, equal lows).
4. **Déplacement + MSS** : le prix repart fort, casse le dernier swing high court terme et
   laisse un **FVG**.
5. **Entrée** au retour du prix dans le FVG (bord supérieur ou CE).
6. **Stop** sous le creux qui a pris la liquidité.
7. **Objectif** : la liquidité opposée (sommet de session, PDH, equal highs), avec prises
   partielles possibles.

ICT a présenté ce modèle sur l'indice (ES/NQ) en M1–M5, mais il s'applique à l'or et au
forex avec les mêmes règles.

## Silver Bullet

- Fenêtres : **03:00–04:00**, **10:00–11:00**, **14:00–15:00** heure de New York (voir la fiche
  temps pour l'heure GMT).
- Dans la fenêtre, repérer le **premier FVG** formé par un déplacement **vers** le draw on
  liquidity (souvent après une prise de liquidité juste avant ou au début de la fenêtre).
- Entrée sur le retour dans ce FVG, stop au-delà du swing qui a créé le déplacement, objectif
  la liquidité visée.
- ICT insiste pour qu'il reste **assez de distance** jusqu'à la cible pour que le ratio
  risque/rendement ait du sens ; sinon, pas de trade.
- Les robots de la plateforme (ICT Ultimate Pro) appliquent le Silver Bullet en M5.

## Entrée OTE

Après un déplacement qui casse la structure, attendre un retracement dans la zone **62–79 %**
de la jambe (sweet spot 70,5 %), idéalement là où se trouve un FVG ou un OB. Stop au-delà du
départ de la jambe.

## Market Maker Buy Model / Sell Model (MMBM / MMSM)

Modèle de plus grande échelle, décrit en 2016-2017 :

- **MMSM** (vente) : consolidation de départ → montée en paliers (« buy program »), chaque
  palier laissant des niveaux et de la liquidité → arrivée sur un PD array de l'unité de temps
  supérieure en premium → **smart money reversal** (prise de BSL, MSS) → redescente qui
  revisite les paliers de la montée (« sell program ») vers la consolidation de départ.
- **MMBM** (achat) : symétrique.
- Les entrées se font sur le côté droit du modèle, au retour sur les PD arrays laissés par le
  côté gauche.

## Turtle soup

Entrée contre une cassure ratée d'un ancien sommet/creux : le prix prend la liquidité puis
réintègre le range ; entrée sur le retour, stop au-delà de la mèche, objectif l'autre côté du
range.

## Check-list avant d'entrer (synthèse)

- Biais HTF clair et draw on liquidity identifié ?
- Je suis du bon côté de l'équilibre (discount pour acheter, premium pour vendre) ?
- Liquidité prise **avant** mon entrée ?
- Déplacement + MSS + FVG ?
- Heure : killzone / Silver Bullet / macro ? Pas de news majeure dans les minutes qui viennent ?
- Stop logique, risque fixe (voir fiche risque), ratio au moins 1:2 vers une cible réaliste ?

Si une réponse est non, ICT recommande de passer son tour.
