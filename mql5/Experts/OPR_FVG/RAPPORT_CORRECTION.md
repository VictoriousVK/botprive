# Rapport de correction — stratégie ICT OPR + FVG

Réponse point par point aux livrables du cahier des charges (§10).

## 1. Erreurs de l'ancienne implémentation

L'EA précédent (`mql5/Experts/LRL_Map/`) appliquait la stratégie **« LRL Map [Herman] »** décrite dans la première demande. Il était fidèle à cette description, mais **aucune de ses règles ne correspond à la stratégie OPR + FVG** :

| Élément | Ancien EA (LRL Map) | Stratégie OPR + FVG |
|---|---|---|
| OPR | aucun | 4 plages (00:00, 07:00, 09:30, 13:30), High/Low figés |
| Direction | ligne LRL (≥ 3 swings alignés) | position du prix par rapport à l'OPR à 2:50 |
| Plage asiatique / premier FVG M15 | absent | référence obligatoire |
| Zone d'entrée | FVG **inversé** (iFVG) du plus haut timeframe 2/3/5 min | FVG M1 **après une prise de liquidité**, dans une macro |
| Horaires | fenêtre 00:00–16:00 NY | fenêtre 2:50–4:10 NY, macros |
| Stop / cible | swing de jambe / 1R | au-delà du swing / −2 STD de l'OPR |

**Pourquoi l'ancien EA ne prenait presque pas de trades.** Il fallait cumuler les conditions suivantes :

- une ligne de 3 swings alignés à 0,15 ATR près, jamais traversée ;
- un iFVG du plus haut timeframe dans ce sens ;
- un premier retest ;
- un stop d'au moins 15 points ;
- la LRL au-delà de la cible ;
- une seule position à la fois.

Sur le NQ réel, cette chaîne est rarement complète.

## 2. Fichiers créés ou modifiés

**Créés : `mql5/Experts/OPR_FVG/`** (nouvel EA, un module par responsabilité, cf. cahier §7)

| Fichier | Raison |
|---|---|
| `OPR_Config.mqh` | toutes les plages horaires centralisées (cahier §6) |
| `OPR_Time.mqh` | fuseau de la stratégie, fuseau du serveur, DST US et européen, plages à cheval sur minuit, journées de session |
| `OPR_Ranges.mqh` | OPR indépendants, figés à la fin de leur plage, statuts incomplet / sans données |
| `OPR_Candles.mqh` | bougies M1 / M5 / M15 clôturées uniquement |
| `OPR_FVG.mqh` | définition mathématique unique du FVG, statuts, rôles (Asie, minuit, entrée) |
| `OPR_Liquidity.mqh` | pools de liquidité et prises (règle du PDF : « la Macro doit commencer par prendre une liquidité ») |
| `OPR_Journal.mqh` | événements codés et libellés explicatifs |
| `OPR_Engine.mqh` | FVG de référence, contexte, validation des entrées, modèle book |
| `OPR_FVG_EA.mq5` | paramètres, ordres et risque, journal CSV, persistance des OPR, dessin, tableau, alertes |
| `README.md`, `RAPPORT_CORRECTION.md` | documentation |

**Tests :**

- créés : `tests/opr_engine_tests.cpp`, `tests/opr_ea_tests.cpp`, `tests/compare_before_after.cpp` ;
- modifiés : `tests/run_tests.sh` (nouvelles suites) ;
- `tests/shim/mql5_api.h` complété : variables globales, fichiers, flèches ;
- `tests/mq2cpp.py` : le lint ignore désormais le contenu des chaînes.

**Non modifié :** l'EA LRL Map. Il est conservé tel quel (« ne supprime aucune fonctionnalité existante ») ; il peut être retiré sur demande.

## 3. Logique finale

Voir `README.md`, section « Logique exacte ». En résumé :

- **OPR** : figés à la fin de leur plage ; **premier FVG M15 asiatique** et **FPFVG M1 de minuit** enregistrés comme références ; **contexte** au-dessus / sous / dans chaque OPR journalisé.
- **Modèle d'entrée** (OPR 00:00 seulement), dans l'ordre :
  1. biais à 2:50 ;
  2. prise de liquidité dans la fenêtre ;
  3. premier FVG M1 dans le sens du biais, formé dans une macro ;
  4. ordre limite au bord du FVG, stop au-delà du swing, cible ±2 STD.

  « 1 macro = 1 trade ». Pas de trade si la cible est atteinte avant l'entrée. L'ordre est supprimé en fin de fenêtre.
- **Autres OPR** : niveaux et contexte seulement, l'entrée est désactivée faute de règle.

## 4. Paramètres

Voir le tableau du `README.md` (valeur par défaut et origine de chaque paramètre : cahier, PDF ou choix technique à valider).

## 5. Résultats des tests et du backtest

`tests/run_tests.sh` passe intégralement. Le code MQL5 y est converti en C++ et compilé avec g++ contre une API MT5 simulée.

**Moteur OPR : 112 vérifications, 0 échec.**

| Test obligatoire | Vérification |
|---|---|
| 1. OPR = bougies de la plage | High 102 / Low 98 exacts malgré un plus haut (103) et un plus bas (97) juste après la plage ; sur données aléatoires, comparaison à un recalcul indépendant chaque jour |
| 2. niveaux figés | inchangés après la fin de la plage, un seul événement de finalisation |
| 3. indépendance | l'OPR 07:00 (92 / 89) ne modifie pas le MOR |
| 4. premier FVG asiatique | celui de 20:00 (gap sur la bougie de 20:00), jamais remplacé par celui de 21:30 ; règle alternative testée |
| 5. pas de détection prématurée | rien avant la clôture de la 3e bougie M15 (20:29), détecté à 20:30 |
| 6. pas d'achat sur condition de vente | scénario miroir (achat) et invariants aléatoires : sens de l'entrée = biais du jour |
| 7. prix dans l'OPR | consolidation journalisée, aucune entrée avant une clôture hors OPR |
| 8. fuseaux | NY / Londres / Paris / UTC / serveur, DST US et européen (dont l'écart de 6 h du 8 au 29 mars), journée de session, plage asiatique à cheval sur minuit |
| 9. backtest = journal | chaque exécution est précédée de son autorisation avec les mêmes niveaux ; dans l'EA, chaque ordre réel correspond à une ligne « entrée autorisée » du **journal CSV** |
| 10. pas de doublon | 4 ticks par bougie : une seule autorisation et un seul ordre par setup |

Autres vérifications :

- **scénarios du PDF** : gain à −2 STD (+3,14R) ; cible atteinte avant l'entrée → annulé ; FVG sans prise de liquidité → « confirmation manquante » ; FVG hors macro → ignoré ; stop sur la bougie d'entrée → −1R ;
- **robustesse** : OPR incomplet → aucune entrée ; restauration après redémarrage ; déterminisme.

**EA OPR complet, 5 variantes :**

- tous les contrôles passent ;
- 38 trades réels = 38 trades du modèle book ;
- 0 ordre refusé, 0 doublon, entrées uniquement entre 02:50 et 04:10 ;
- refus explicites testés : fuseau « Auto » dans le testeur, OPR tradé sans fenêtre ;
- redémarrage en cours de route sans doublon.

**Backtest avant / après** (mêmes données synthétiques, modèle book, environ 223 journées par graine) :

| Graine | Avant : LRL Map | Après : OPR + FVG |
|---|---|---|
| 61 | 12,2 trades/jour, net −647R | 0,41 trade/jour, net +14R |
| 62 | 12,4 trades/jour, net −428R | 0,43 trade/jour, net +63R |
| 63 | 11,7 trades/jour, net −345R | 0,39 trade/jour, net +18R |

Comment lire ce tableau :

- **Ces chiffres ne mesurent pas la rentabilité.** Les données sont synthétiques (aucune donnée NQ ni MT5 n'est accessible ici). Le générateur produit des phases de tendance, ce qui avantage tout modèle de continuation. Sur ces données, l'ancien EA prend même beaucoup de trades, alors que tu observes l'inverse sur le NQ réel : elles ne reproduisent pas la structure du marché.
- La fréquence réelle doit être mesurée dans le **testeur de stratégie MT5** sur l'historique de ton broker.
- **Par construction**, le modèle London OPR prend **au plus 3 trades par jour** (3 macros) et s'arrête une fois la cible atteinte. Sur données synthétiques, il en prend environ 0,4 par jour.
- **L'objectif de 2 trades par jour ne peut pas être atteint avec la seule fenêtre de Londres.** Il faudrait des règles pour les OPR 09:30 et 13:30 (questions 9 et 10).

## 6. Divergences non résolues

1. **Fenêtre de trading.** Le cahier présente 02:50–03:10 comme une fenêtre d'observation ; le PDF fixe la fenêtre de trading à 2:50–4:10, avec les macros 2:50–3:10, 3:20–3:40 et 3:50–4:10. L'EA suit le PDF ; 02:50–03:10 est seulement journalisé.
2. **Breaker et orderblock.** Le PDF autorise l'entrée sur un FVG, un breaker ou un orderblock. Seul le FVG (« en priorité ») est implémenté.
3. **Cible EQH/EQL M15 prioritaire** (PDF) : non implémentée. La cible est la déviation standard.
4. **Seconde entrée à cible plus lointaine** (−3 STD, exemple 2 du PDF) : non implémentée. Une fois la cible atteinte, plus de trade ce jour-là.
5. **FPFVG M1 de minuit.** Le PDF le décrit comme « le plus évident / qui casse une structure » ; l'EA prend le premier FVG M1 ≥ taille minimale. C'est une référence affichée seulement.
6. **FPFVG asiatique déjà retravaillé.** Le PDF dit d'en préférer un autre dans ce cas ; le cahier interdit de le remplacer. L'EA suit le cahier.
7. **OPR 07:00, 09:30, 13:30** : aucune règle d'entrée documentée, entrée désactivée.
8. **Méthode CRT 5 h / 9 h** (DOL, SMT EUR/USD–GBP/USD) : non formalisable sur un seul instrument, non implémentée.
9. **Entrée et cible sur la même bougie M1.** Le modèle book annule le setup (choix conservateur), alors que l'exécution réelle, qui contrôle chaque tick, peut être exécutée. Ce cas est rare.

## 7. Questions à valider

1. **Fuseau.** Le PDF confirme l'heure de New York pour le MOR et la fenêtre 2:50–4:10. Est-ce aussi le cas des OPR 07:00, 09:30 et 13:30 et de la plage asiatique 20:00–00:00 ?
2. **Fenêtre.** Garder 2:50–4:10 (PDF) comme fenêtre de trading, avec ses trois macros ? Ou trader uniquement 02:50–03:10 (tes notes) ?
3. **Liquidité.** Quelles liquidités comptent ? Actuellement : swings M1 et M15 (1 bougie de chaque côté) et High/Low asiatique. Faut-il ajouter les hauts/bas équivalents ? La prise doit-elle avoir lieu dans la fenêtre (actuel) ou peut-elle précéder 2:50 ?
4. **FVG d'entrée.** M1 (graphiques du PDF) ou M15 ? Entrée au bord du FVG (actuel) ou au CE ? Taille minimale ?
5. **Stop.** « Sous le swing » + 1 tick (actuel) te convient-il ?
6. **Cible.** 2,0 STD (actuel) ou 2,5 ? Faut-il viser d'abord les EQH/EQL M15 quand il y en a ? Faut-il autoriser une seconde entrée vers −3 STD ?
7. **Prix dans l'OPR à 2:50.** Après la clôture hors de l'OPR, faut-il aussi une prise de liquidité (actuel), ou entrer directement sur le déséquilibre ?
8. **FVG asiatique / FVG de minuit.** Doivent-ils jouer un rôle dans l'entrée (réaction exigée sur ces niveaux, priorité, cible) ? Ou restent-ils des repères visuels (actuel) ?
9. **OPR 07:00, 09:30, 13:30.** Quelles fenêtres, quelles macros et quelles règles d'entrée ? Le même modèle que Londres ? C'est indispensable pour viser 2 trades par jour.
10. **Breaker / orderblock.** Faut-il implémenter les entrées du PDF Macro : unicorn = FVG dans un breaker, SL au-delà du breaker ; scénario idéal = clôture au-delà du breaker puis entrée au toucher ?
11. **« SIDV ».** Confirmes-tu qu'il s'agit de la déviation standard (STD) de l'amplitude de l'OPR ?
12. **Journée de session.** Le début à 18:00 NY (réouverture CME) te convient-il ?
