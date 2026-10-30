# Biais journalier, Power of 3 (AMD), profils hebdomadaires, IPDA

## Le biais journalier (daily bias)

Avant de chercher une entrée, ICT demande : **le prix va-t-il plutôt vers le haut ou vers le bas
aujourd'hui ?** Méthode courante :

1. Repérer le **draw on liquidity** sur le Daily/H4 : sommet ou creux non pris (PDH/PDL,
   sommet de la semaine), FVG Daily non comblé.
2. Regarder où le prix se situe dans le range (premium ou discount) et comment il a réagi la
   veille (rejet, clôture au-delà d'un niveau, déplacement).
3. Exemple : la veille a clôturé fort au-dessus d'un FVG Daily, le PDH reste intact au-dessus
   → biais haussier, cible le PDH ; on cherche des achats en discount de la journée.

Si le biais n'est pas clair, ICT conseille de **ne pas trader** ce jour-là.

## Power of 3 / AMD

Chaque bougie (journalière, hebdomadaire, ou une session) se décompose en trois temps :

1. **Accumulation** : range calme autour de l'ouverture (souvent la session asiatique pour la
   journée).
2. **Manipulation** : faux mouvement dans le sens opposé au vrai mouvement, qui prend de la
   liquidité (le **Judas swing**). Une journée haussière fait souvent son **plus bas** pendant
   cette phase, sous l'ouverture.
3. **Distribution** : l'expansion dans la vraie direction, vers le draw on liquidity.

Lecture pratique d'une journée haussière : ouverture → descente sous l'ouverture (prise de
SSL, souvent à Londres ou au début de NY) → montée qui clôture près du plus haut. On cherche
donc à acheter **sous l'ouverture** (discount du jour) après la manipulation.

## Profils hebdomadaires

ICT a décrit des profils typiques de construction de la bougie hebdomadaire, par exemple :

- **Classic Tuesday low/high of the week** : le plus bas (semaine haussière) ou le plus haut
  (semaine baissière) se forme le mardi, souvent pendant Londres.
- **Wednesday low/high** : la semaine fait son extrême le mercredi.
- **Consolidation Thursday reversal**, **Seek and Destroy** (semaine sans direction claire,
  souvent à éviter).

Ce sont des **tendances statistiques**, pas des règles. Les robots de la plateforme donnent un
léger avantage aux mardis, mercredis et jeudis, et sont plus prudents le vendredi.

## IPDA data ranges et quarterly shifts

- ICT propose de regarder **les 20, 40 et 60 derniers jours de trading** (IPDA data ranges)
  sur le Daily : leurs sommets et creux sont les niveaux de liquidité que l'algorithme vise
  en priorité.
- **Quarterly shift** : environ tous les 3 à 4 mois, le marché change souvent de direction
  majeure ; ICT relie cela aux 60 jours de lookback.

## Erreurs fréquentes

- Chercher une entrée M1 sans biais : on se fait prendre par la manipulation.
- Acheter la manipulation trop tôt : attendre la prise de liquidité **et** le déplacement.
- Appliquer un profil hebdomadaire comme une certitude.
