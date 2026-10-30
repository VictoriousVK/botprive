# Order Block (OB)

## Définition ICT

- **Order block haussier** : la **dernière bougie baissière** (clôture sous l'ouverture), ou la
  dernière série de bougies baissières consécutives, **avant un mouvement haussier qui casse la
  structure** avec déplacement.
- **Order block baissier** : la **dernière bougie haussière** (ou série) avant un mouvement
  baissier qui casse la structure avec déplacement.

L'idée : des ordres institutionnels ont été placés dans cette bougie ; quand le prix y revient,
ces ordres « défendent » la zone.

## Conditions pour qu'un OB soit valide

1. Il est suivi d'un **déplacement** (grandes bougies), idéalement en laissant un **FVG**.
2. Le mouvement **casse un swing** (BOS ou MSS).
3. Il se trouve du bon côté de l'équilibre : OB haussier en **discount**, OB baissier en
   **premium**.
4. Il est aligné avec le biais de l'unité de temps supérieure.
5. Mieux encore s'il a pris de la liquidité juste avant (la bougie de l'OB fait souvent la
   mèche qui balaie un creux ou un sommet).

## Repères dans l'OB

- **Ouverture** de la bougie : niveau d'entrée classique (pour un OB haussier, le haut du corps
  de la bougie baissière est son ouverture).
- **Mean threshold** : le **50 % de l'order block** (ICT le mesure en général sur le corps,
  de l'ouverture à la clôture). Pour un OB haussier, le prix ne devrait pas clôturer sous ce
  50 % ; si c'est le cas, l'OB perd de sa force.
- **Extrême** : plus bas (OB haussier) ou plus haut (OB baissier) de la bougie, souvent utilisé
  pour placer le stop juste au-delà.

## Exemple chiffré (fictif)

Or en H1 : dernière bougie baissière ouvre à 2 318 $, clôture à 2 314 $, plus bas 2 312 $. Le
prix monte ensuite à 2 335 $ en trois grandes bougies et casse le sommet à 2 328 $ → OB
haussier 2 314–2 318 $, mean threshold 2 316 $. Scénario : attendre le retour du prix vers
2 318 $, stop sous 2 312 $, objectif la liquidité au-dessus de 2 335 $. (Exemple pédagogique,
pas une recommandation.)

## Autres « blocks » d'ICT

- **Breaker block** et **mitigation block** : order blocks qui ont échoué. Voir la fiche
  breaker et mitigation.
- **Rejection block** : zone formée par les **mèches** d'un sommet ou d'un creux qui a rejeté
  le prix ; on utilise la zone entre le corps et l'extrême de la mèche.
- **Propulsion block** : une bougie qui a réagi à un order block puis propulse le prix ; elle
  devient elle-même un support/résistance.
- **Vacuum block** : un gap laissé par un événement de volatilité (news, ouverture), que le
  prix tend à revenir combler.

## Erreurs fréquentes

- Prendre n'importe quelle bougie de couleur opposée pour un OB : sans déplacement ni cassure
  de structure, ce n'est pas un OB au sens d'ICT.
- Entrer sur un OB déjà « mitigé » (le prix y est déjà revenu une fois) : sa force diminue.
- Ignorer l'unité de temps supérieure : un OB M5 contre un OB H4 tient rarement.
