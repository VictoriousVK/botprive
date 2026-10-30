# OTE, Fibonacci et projections

## Optimal Trade Entry (OTE)

L'**OTE** est la zone de retracement **62 % à 79 %** d'un mouvement (jambe de déplacement), avec
le niveau **70,5 %** comme « sweet spot ».

- En achat : Fibonacci tracé du **creux au sommet** de la jambe haussière ; on attend le retour
  du prix entre 62 et 79 % de retracement (zone de discount de cette jambe).
- En vente : tracé du sommet au creux de la jambe baissière.
- L'OTE est plus solide s'il coïncide avec un PD array (FVG, OB, breaker) et une killzone.

Exemple : jambe de 2 300 $ à 2 340 $ (40 $). Retracement 62 % = 2 315,20 $ ; 70,5 % =
2 311,80 $ ; 79 % = 2 308,40 $. La zone OTE est 2 308,40–2 315,20 $.

## Niveaux Fibonacci utilisés par ICT

- **0,5** : équilibre (premium/discount).
- **0,62 / 0,705 / 0,79** : OTE.
- **Extensions pour les objectifs** (au-delà de 100 %, souvent notées en négatif sur l'outil
  Fibonacci) : **-0,27**, **-0,62**, **-1** (symétrie) ; ICT ajoute parfois -2 et -2,5 pour des
  mouvements étendus.

## Projections en déviations standard

Dans ses contenus récents, ICT projette la **jambe de manipulation** (le Judas swing, ou un
range de référence comme le CBDR ou le range asiatique) en multiples de sa propre taille
(-1, -2, -2,5, -4…) pour estimer jusqu'où l'expansion peut aller. C'est un outil d'objectif,
pas d'entrée, et ses règles précises ont varié ; à valider en backtest.

## Erreurs fréquentes

- Tracer le Fibonacci sur une jambe sans déplacement ou sur des swings mineurs.
- Entrer à 62 % sans confirmation alors que le prix vise un PD array plus profond.
- Prendre les extensions pour des certitudes : ce sont des zones de prise de bénéfices
  partielle.
