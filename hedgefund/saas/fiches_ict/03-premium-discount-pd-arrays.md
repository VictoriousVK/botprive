# Premium, discount, équilibre et PD arrays

## Le dealing range

On prend un range de référence : du dernier swing low significatif au dernier swing high (ou
l'inverse). On le divise en deux avec un Fibonacci :

- **Équilibre (EQ)** = 50 % du range.
- **Premium** = la moitié haute (au-dessus de 50 %) : zone où l'on cherche à **vendre**.
- **Discount** = la moitié basse (sous 50 %) : zone où l'on cherche à **acheter**.

Règle ICT : on achète en discount quand le biais est haussier, on vend en premium quand le
biais est baissier. Acheter en premium dans une tendance haussière revient à acheter « cher ».

Exemple : range de l'or de 2 300 à 2 340 $. Équilibre 2 320 $. En biais haussier, un achat
n'est envisagé que sous 2 320 $, idéalement dans un PD array du discount.

## Dans la plateforme

L'Analyste et les robots n'utilisent pas un range tracé à la main : leur range de référence est le
plus haut et le plus bas des **20 derniers jours (IPDA 20 jours)**. Au-dessus de **55 %** du range :
premium ; sous **45 %** : discount ; entre les deux : équilibre. Ce sont les définitions du moteur
(version victor-v0, à valider par Victor) : une carte d'analyse qui dit « discount » se lit avec
cette règle, même si votre propre range donne autre chose.

## PD arrays

**PD array** (Premium/Discount array) désigne toute zone de prix de référence où l'algorithme
peut réagir : order block, FVG, breaker, mitigation block, rejection block, liquidity void,
anciens sommets/creux. ICT les a classés dans une **matrice PD array** (mentorship 2016-2017),
du haut vers le bas :

- Côté **premium** (zones de vente) : ancien sommet ou creux, rejection block, order block
  baissier, fair value gap, liquidity void, breaker baissier, mitigation block baissier.
- Côté **discount** (zones d'achat) : mitigation block haussier, breaker haussier, liquidity
  void, fair value gap, order block haussier, rejection block, ancien creux ou sommet.

L'ordre exact de la matrice varie selon les présentations ; l'idée importante est de chercher
un PD array **cohérent avec le biais** et situé du **bon côté de l'équilibre**.

## Multi-unités de temps

On définit le range et le PD array sur une unité de temps supérieure (Daily, H4, H1), puis on
descend (M15, M5, M1) pour l'entrée. Un FVG M5 en discount sur le M5 mais en premium sur le H4
est un achat à contre-courant.

## Erreurs fréquentes

- Tracer le range sur des swings mineurs : le 50 % n'a alors pas de sens.
- Considérer chaque PD array comme une entrée : il faut un contexte (biais, liquidité prise,
  heure) et une confirmation.
