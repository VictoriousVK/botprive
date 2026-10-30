# OPR + FVG EA — MetaTrader 5

Expert Advisor MQL5 de la stratégie **ICT OPR + FVG**, implémentée d'après :

- le **cahier des charges** (OPR, premier FVG M15 asiatique, contexte directionnel, journalisation, tests) ;
- les PDF fournis : **« London OPR Strategy »** (règles du Midnight Opening Range) et **« Macro + breaker tout savoir »** (macros, « 1 macro = 1 trade », placement du stop).

Les PDF « 5AM CRT » et « 9 AM CRT » décrivent une autre méthode (Candle Range Theory). Elle repose sur le DOL, la narrative et des divergences SMT entre EUR/USD et GBP/USD, ce qui n'est pas formalisable sur un seul instrument. Elle n'est **pas** implémentée.

## Installation

1. Copier le dossier `OPR_FVG` dans `MQL5/Experts/`. Les 9 fichiers doivent rester ensemble.
2. Compiler `OPR_FVG_EA.mq5` dans MetaEditor (F7).
3. Attacher l'EA à un graphique du Nasdaq (NQ, MNQ, US100…), dans n'importe quel timeframe : l'EA lit toujours les bougies M1.
4. **Dans le testeur de stratégie**, choisir le fuseau du serveur (`InpServerTZ`). Le mode « Auto » ne peut pas être mesuré dans le testeur et l'EA refuse de démarrer. La plupart des brokers sont en « GMT+x en hiver, +1 h pendant le DST US » avec x = 2.
5. Vérifier dans l'onglet Experts les lignes `OPR FVG:`. Elles affichent chaque OPR configuré et sa fenêtre.

| Fichier | Module (cahier des charges §7) |
|---|---|
| `OPR_Config.mqh` | configuration centralisée de toutes les plages horaires |
| `OPR_Time.mqh` | 1. horaires et calendrier : serveur → UTC → heure de la stratégie, DST US et européen, journées de session |
| `OPR_Ranges.mqh` | 2. calcul des OPR (et de la plage asiatique), niveaux figés, déviations standard |
| `OPR_FVG.mqh` | 3. détection des FVG (définition mathématique, statuts, rôles) |
| `OPR_Candles.mqh` | bougies M1 / M5 / M15 clôturées, reconstruites depuis le M1 |
| `OPR_Liquidity.mqh` | pools de liquidité et prises de liquidité |
| `OPR_Engine.mqh` | 4. FVG de référence (Asie, minuit) · 5. contexte directionnel · 6. validation des entrées · modèle book |
| `OPR_Journal.mqh` | 8. journalisation : codes, raisons, libellés |
| `OPR_FVG_EA.mq5` | 7. ordres et risque, paramètres, journal CSV, persistance, dessin, tableau, alertes |

## Logique exacte

Toutes les heures sont celles de la **stratégie** : New York par défaut, comme dans le PDF (« entre 2:50 et 4:10, heure de New York »). Une **journée de session** commence à 18:00 NY (réouverture CME). La plage asiatique 20:00 → 00:00 appartient ainsi à la même journée que le Midnight Opening Range qui suit.

### 1. OPR (cahier §2)

Chaque OPR a sa plage de calcul :

| OPR | Plage | Entrée |
|---|---|---|
| OPR 1, « MOR » | 00:00–00:30 | active |
| OPR 2 | 07:00–07:30 | désactivée |
| OPR 3 | 09:30–10:00 | désactivée |
| OPR 4 | 13:30–14:00 | désactivée |

- **High** = maximum des High et **Low** = minimum des Low des bougies M1 dont l'ouverture est dans la plage.
- Le niveau devient **finalisé** à la clôture de la dernière bougie de la plage, puis **ne change plus jamais**.
- Statuts : en attente, en calcul (jamais utilisé), finalisé, *incomplet* (le moteur n'a pas vu la plage depuis son début), *sans données*.
- Chaque OPR a son propre état : aucun mélange.
- Les OPR finalisés sont sauvegardés (variables globales du terminal). Au redémarrage, ils sont recalculés depuis l'historique et comparés à la sauvegarde. Ils ne sont restaurés depuis la sauvegarde que si l'historique est insuffisant.

**Déviations standard** (PDF, annexe 1), avec amplitude = High − Low :

- achat : High + k × amplitude ;
- vente : Low − k × amplitude.

### 2. Premier FVG M15 asiatique (cahier §3)

Définition, sur trois bougies M15 **clôturées** c1, c2, c3 :

- **FVG haussier** si Low(c3) > High(c1) : zone [High(c1), Low(c3)] ;
- **FVG baissier** si High(c3) < Low(c1) : zone [High(c3), Low(c1)].

Le FVG n'existe qu'à la clôture de c3 : jamais de détection prématurée. La définition est la même en historique et en direct.

Le **premier** FVG dont la bougie du gap (c2) est dans 20:00–00:00 est enregistré. Le PDF précise qu'il « peut apparaître sur le corps de la bougie de 20:00 ». L'EA enregistre son sens, ses bornes, son heure et son statut. Il ne le remplace **jamais**. C'est une **référence** (affichage, journal), pas un déclencheur.

Statuts des FVG (règles documentées, à valider) :

- *mitigé* : une bougie du même timeframe est revenue dans la zone ;
- *invalidé* : une bougie a clôturé au-delà du bord opposé ;
- *expiré* : fin de journée de session.

Le **FPFVG M1 de minuit** (PDF, étape 2) est aussi enregistré comme référence : premier FVG M1 dont c2 est après 00:00.

### 3. Contexte directionnel (cahier §4)

Pour chaque OPR finalisé, à chaque bougie M1 clôturée, le prix est classé :

- **au-dessus** de l'OPR High ;
- **sous** l'OPR Low ;
- **à l'intérieur**.

Chaque changement est journalisé. Le contexte seul ne déclenche **jamais** d'ordre.

### 4. Modèle d'entrée « London OPR » (OPR 1 uniquement)

| Étape | Règle | Source |
|---|---|---|
| a. Biais | Lu à l'ouverture de la fenêtre (2:50), sur la clôture de la bougie 02:49. Prix sous l'OPR Low → **vente** ; au-dessus de l'OPR High → **achat** ; **dans l'OPR** → aucune direction, attente d'une **clôture M1 hors de l'OPR**. Le biais reste ensuite fixe pour la journée. | PDF p.7 et p.9 |
| b. Prise de liquidité | Dans la fenêtre 2:50–4:10, une liquidité du côté opposé doit d'abord être prise : un swing high M1 ou M15, ou le High asiatique, pour une vente ; l'inverse pour un achat. Un FVG apparu avant est rejeté (« confirmation manquante »). | PDF p.7 : « la Macro doit commencer par prendre une liquidité » |
| c. FVG d'entrée | Premier FVG M1 dans le sens du biais, commencé à partir de la bougie de prise de liquidité, formé **dans une macro** : 02:50–03:10, 03:20–03:40 ou 03:50–04:10. | PDF p.8 (« rentrer en priorité sur le FVG ») ; PDF Macro (horaires, « 1 macro = 1 trade ») |
| d. Ordre | Ordre **limite au bord du FVG** (« quand le prix revient dans le FVG »). Stop **au-delà du swing** : extrême depuis la prise de liquidité, + 1 tick. Cible **−2 STD** (vente) ou **+2 STD** (achat) du MOR. | PDF Macro : « tu rentres sur la FVG, SL sous le swing » ; PDF p.8 : « première cible : −2 STD » ; notes : « 2–2,5 SIDV » |
| e. Annulations | **Cible atteinte avant l'entrée → pas de trade** (vérifié à chaque tick). FVG invalidé → nouvelle prise de liquidité nécessaire. Fin de fenêtre → ordre supprimé. Une seule position à la fois. | PDF Macro |

Les OPR 2, 3 et 4 n'ont **aucune règle d'entrée documentée**. Leurs niveaux et leur contexte sont calculés et journalisés, mais l'entrée est **désactivée**. L'EA refuse d'activer une entrée sans fenêtre de trading.

### 5. Exécution et risque

- Volume calculé pour risquer `InpRiskPct` % du solde (via `OrderCalcProfit`), plafonné par la marge libre et `InpMaxLots`.
- Les niveaux sont arrondis au tick dans le sens qui garde le déclenchement réel identique au modèle book.
- Après un redémarrage, l'EA reprend son ordre en attente et ne retrade jamais un setup déjà exécuté.

### 6. Journal (cahier §7)

Chaque décision est écrite :

- dans l'onglet Experts, préfixée de l'heure NY ;
- dans `MQL5\Files\OPR_FVG_journal_<symbole>.csv`, avec les colonnes : heure serveur, heure stratégie, code, OPR, sens, raison, identifiant, prix, message.

Exemples :

- « MOR 00:00 : OPR finalisé, High … / Low … »
- « premier FVG M15 asiatique identifié »
- « prix sous l'OPR Low »
- « liquidité prise (swing M1 …) »
- « FVG candidat »
- « FVG ignoré, confirmation manquante : aucune prise de liquidité »
- « entrée autorisée VENTE, toutes les conditions sont remplies : entrée … stop … cible … »
- « setup annulé, cible atteinte avant l'entrée : pas de trade »

## Paramètres

| Paramètre | Défaut | Origine |
|---|---|---|
| `InpStratTZ` | New York | PDF London OPR |
| `InpServerTZ` / `InpServerGMT` | Auto / 2 | broker (à choisir dans le testeur) |
| `InpDayStart` | 18:00 | choix technique (réouverture CME) |
| `InpAsiaRange` | 20:00-00:00 | cahier + PDF |
| `InpLondonRange` | 00:00-06:00 | cahier (information) |
| `InpObsWindow` | 02:50-03:10 | cahier (information uniquement) |
| `InpOpr1Range` / `Trade` / `Window` / `Macros` | 00:00-00:30 / oui / 02:50-04:10 / 02:50-03:10, 03:20-03:40, 03:50-04:10 | cahier + PDF |
| `InpOpr2..4Range` | 07:00-07:30, 09:30-10:00, 13:30-14:00 | cahier |
| `InpOpr2..4Trade` | non | aucune règle documentée |
| `InpAsiaRule` | bougie du gap (c2) dans la plage | PDF p.5 |
| `InpAsiaMinGapTicks` / `InpMidnightMinGapTicks` | 1 / 1 | à valider |
| `InpEntryTF` / `InpEntryLevel` / `InpMinFvgTicks` | M1 / bord du FVG / 1 | PDF (graphiques M1, « revient dans le FVG ») |
| `InpLiqM1` / `InpLiqM15` / `InpLiqAsia` (pivots 1) | oui / oui / oui | PDF p.7, à valider |
| `InpRequireMacro` / `InpOneTradePerMacro` | oui / oui | PDF Macro |
| `InpConsolRequireSweep` | oui | à valider |
| `InpStopBufferTicks` | 1 | « sous le swing » |
| `InpTpStd` | 2.0 | PDF (−2 STD) et notes (2–2,5) |
| `InpGraceMin` | 0 | — |
| `InpMinStop` / `InpMaxStop` | 0 / 0 (aucun) | — |
| `InpMaxOpenTrades` / `InpMaxTradesDay` | 1 / 0 | — |
| `InpRiskPct` | 0,5 % | gestion du risque |

Les autres paramètres (affichage, alertes, journal, persistance, couleurs) n'influencent pas les décisions.

## Tests

```bash
tests/run_tests.sh
```

Le code MQL5 est converti en C++ (`tests/mq2cpp.py`) puis compilé avec g++ contre une API MT5 simulée (`tests/shim/`). Le convertisseur contrôle aussi les règles propres à MQL5.

- **`opr_engine_tests.cpp`** (112 vérifications) : les 10 tests obligatoires du cahier, des scénarios construits à la main à partir des exemples du PDF, et des invariants sur 3 × 250 000 bougies aléatoires. Les OPR et le FVG asiatique y sont comparés à un recalcul indépendant.
- **`opr_ea_tests.cpp`** : l'EA complet, tick par tick (4 ticks par bougie), en 5 variantes de paramètres. Il vérifie que chaque ordre réel correspond à une ligne « entrée autorisée » du journal CSV et qu'aucun setup n'envoie deux ordres. Il vérifie aussi que les trades réels sont identiques aux trades du modèle book.
- **`compare_before_after.cpp`** : ancien moteur (LRL Map) contre nouveau moteur sur les mêmes données synthétiques.

Ce harnais ne remplace pas une compilation dans MetaEditor : envoyez toute erreur de compilation pour correction.

## Avertissement

Le code fonctionne et respecte les règles documentées, mais cela ne dit rien de sa rentabilité. Les statistiques du tableau sont un modèle *book* (entrée au niveau, résolution conservatrice), pas un backtest broker. Testez dans le testeur de stratégie MT5, puis en compte démo.
