# Breaker block, mitigation block et modèle Unicorn

Ces trois notions décrivent un **order block qui a échoué** et qui change de rôle.

## Breaker block

Un breaker se forme **après une prise de liquidité**.

- **Breaker haussier** : le prix fait un swing high, puis descend **sous le creux précédent**
  (prise de SSL), puis remonte avec force et **casse au-dessus du swing high**. La dernière
  bougie haussière (order block baissier) avant la chute vers le nouveau creux a échoué : quand
  le prix revient dessus par le haut, elle sert de **support**. C'est le breaker haussier.
- **Breaker baissier** : symétrique. Le prix fait un swing low, monte **au-dessus du sommet
  précédent** (prise de BSL), puis chute et **casse sous le swing low**. La dernière bougie
  baissière (order block haussier) avant la montée vers le nouveau sommet sert ensuite de
  **résistance**.

Résumé : breaker haussier = OB baissier raté après une prise de SSL ; breaker baissier = OB
haussier raté après une prise de BSL. Le signal est plus fort si la cassure se fait avec
déplacement et FVG.

## Mitigation block

Même logique, mais **sans prise de liquidité** : le prix n'arrive pas à dépasser l'extrême
précédent (un **failure swing**).

- **Mitigation block baissier** : le prix fait un sommet, un creux, puis un **sommet plus bas**
  (il échoue à reprendre le sommet), puis casse sous le creux. L'order block haussier qui avait
  lancé la montée vers ce sommet plus bas a échoué : il devient une **résistance**.
- **Mitigation block haussier** : symétrique (creux plus haut, puis cassure au-dessus du
  sommet) ; il devient un **support**.

Breaker = échec **avec** prise de liquidité ; mitigation block = échec **sans** prise de
liquidité.

## Modèle Unicorn

Setup popularisé par ICT dans ses contenus récents : un **breaker** qui **chevauche un FVG**
formé dans le même mouvement de déplacement. La zone de chevauchement breaker + FVG sert
d'entrée, stop au-delà du breaker, objectif la liquidité opposée.

## Erreurs fréquentes

- Appeler « breaker » un OB raté sans prise de liquidité : c'est un mitigation block.
- Prendre le breaker à l'envers : il faut regarder **quelle bougie** a lancé le mouvement vers
  l'extrême qui a pris (ou raté) la liquidité.
- Utiliser un breaker contre la tendance de l'unité de temps supérieure sans autre
  confirmation.
