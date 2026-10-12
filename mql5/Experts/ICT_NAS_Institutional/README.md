# ICT NAS Institutional v2.30

La v2.30 est la v2.22 complète, fusionnée avec le moteur « OPR + FVG » (`mql5/Experts/OPR_FVG`). Ce moteur est construit d'après ton cahier des charges et les PDF « London OPR Strategy » et « Macro + breaker ».

- **Un seul fichier** : `ICT_NAS_Institutional.mq5`. Copie-le dans `MQL5\Experts\` puis compile-le dans MetaEditor.
- **Fonctions conservées** : tout ce qui existait est gardé :
  - les modèles ;
  - la collecte SQLite (même schéma, donc ict_quant reste compatible) ;
  - le ML ONNX, les news, la SMT, les gaps, la Quarterly Theory ;
  - les partiels, le panneau et le diagnostic.
- **Version d'origine** : la v2.22 reste disponible dans `tests/ref/` pour la comparaison.

## 1. Ce qui change

| # | Changement | Pourquoi | Revenir à la v2.22 |
|---|---|---|---|
| 1 | **Nouveau modèle `LONDON_OPR_PDF`**, fidèle au PDF (voir §2). Il remplace la route London OPR de la v2.22. | La v2.22 exigeait la séquence ICT complète : sweep d'un niveau de la carte, puis MSS/CISD, puis displacement, puis FVG en 3 bougies, et RR ≥ 3. Le PDF n'exige rien de tout cela. Sur les tests, l'ancienne route n'a pris **aucun** trade en 180 jours. | `InpLondonMode = LONDON_LEGACY` (ou `LONDON_BOTH`) |
| 2 | **RR minimal par famille** : ICT 2, CRT 3, London PDF 0 (cible du PDF acceptée). | Le code imposait 3 partout. Ton en-tête RiskManager (« RR min 2 ») et la description du profil Strict (« RR 2 ») disaient 2. La règle CRT « reste à la DOL ≥ 3R » est conservée. | `InpProfile = Personnalisé` avec `InpMinRR = 3` |
| 3 | **Score ICT non bloquant pour le modèle PDF** : il reste calculé et enregistré. | Le score n'est pas une règle du PDF. Un setup PDF avec sweep M1 a souvent un score < 25. | — |
| 4 | **Trades max/jour : seuls les trades exécutés et les ordres encore en attente comptent.** | En v2.22, chaque ordre *envoyé* consommait le quota, même s'il expirait sans être exécuté. 3 ordres limites expirés = journée terminée. | — (c'était un défaut) |
| 5 | **Risque 1 %/trade, stop jour -2 %, objectif +3 %** (v2.22 : 3 % / -3 % / +9 %). | Avec 3 % par trade et -3 % par jour, **une seule perte arrêtait la journée** : 2 trades par jour devenaient impossibles. Les nouvelles valeurs sont celles de ton en-tête RiskManager (« stop journalier -2 %, objectif +3 % »), avec un risque sous ton plafond de 2 %. Un message avertit si le stop jour est inférieur à 2 fois le risque. | `InpRiskPct = 3`, `InpDailyLossPct = 3`, `InpDailyTargetPct = 9` |
| 6 | **2 positions/ordres simultanés**, toujours dans le même sens (v2.22 : 1). | Moins de rejets « position/ordre déjà actif » ; l'achat et la vente simultanés restent interdits. | `InpMaxConcurrent = 1` |
| 7 | **Entrée au marché bornée** (modèle PDF) : si le prix a déjà traversé le niveau de plus de 0,25 R, le setup est déclaré manqué. | Le modèle book prend l'entrée au niveau. Entrer beaucoup plus loin changerait le trade. | `InpLOMaxChaseR` |
| 8 | **« Cible atteinte avant l'entrée » contrôlée à chaque tick** : le niveau d'annulation est propre au signal (la cible du PDF, pas le TP1). | Règle du PDF Macro : « si ta target est prise avant que le marché t'ait donné une entrée, alors pas de trade ». | — |
| 9 | **FPFVG Asie et Midnight du moteur** : 1er FVG M15 de 20:00-00:00 (règle « bougie 2 dans la plage »), jamais remplacé. | Règle du cahier des charges. La v2.22 prenait le 1er FVG M15 de 18:00-00:00. | `InpFPFVGFromEngine = false` |
| 10 | Globales réinitialisées dans `OnInit`. Stop/objectif journalier à 0 = désactivé. | MT5 ne réinitialise pas les globales lors d'un changement de graphique ou de paramètres. | — |

## 2. Le modèle LONDON_OPR_PDF (moteur OPR + FVG)

Le moteur reçoit **uniquement des bougies M1 clôturées**. Toutes les heures sont celles de New York.

1. **MOR** : High et Low des bougies de 00:00-00:30. Les niveaux sont figés à la clôture de 00:29, puis sauvegardés (variables globales `ICTNAS_<magic>_<symbole>_LO0_*`).
2. **Biais à 2:50**, sur la clôture de la bougie de 02:49 :
   - au-dessus du MOR : achat ;
   - en dessous du MOR : vente ;
   - dans le MOR : attente d'une clôture hors du MOR (consolidation, PDF p. 9).
3. **Prise de liquidité dans la fenêtre 02:50-04:10**, du côté opposé au trade. Sont comptés les swings M1, les swings M15 et le high/low de la plage asiatique (« la Macro doit commencer par prendre une liquidité »).
4. **1er FVG M1** dans le sens du biais, après la prise, **formé dans une macro** (02:50-03:10, 03:20-03:40, 03:50-04:10).
5. **Ordre limite** :
   - entrée au bord du FVG ;
   - **SL** 1 tick au-delà du swing (l'extrême depuis la prise) ;
   - **cible** à ±2 STD du MOR (High + 2 × amplitude pour un achat, Low - 2 × amplitude pour une vente).
6. **1 macro = 1 trade.** Pas de trade si la cible est atteinte avant l'entrée. L'ordre est supprimé :
   - à la fin de la fenêtre ;
   - si le FVG est invalidé.

Chaque setup autorisé devient un signal ICT NAS. Il passe par la même chaîne que les autres modèles :

- filtres (news…) ;
- RR du modèle ;
- ML (observation ou filtre) ;
- risque du jour ;
- conflit de positions ;
- ordre ;
- enregistrement SQLite (colonne `model = LONDON_OPR_PDF`).

**Gestion des trades** : par défaut celle du PDF, c'est-à-dire une cible unique, sans BE ni partiel. `InpLondonManage = LM_ICTNAS` applique à la place la gestion ICT NAS : BE à 1R, 50 % au TP1, reste à la cible.

**Journal** : chaque décision du moteur est expliquée dans `Common\Files\ICTNAS\<symbole>_london_opr_journal.csv` :

- OPR finalisé ;
- biais ;
- liquidité prise ;
- FVG candidat ou ignoré, et pourquoi ;
- entrée autorisée ou rejetée ;
- annulation ;
- trade book.

Les décisions importantes s'affichent aussi dans l'onglet Experts, ainsi que dans 3 à 5 lignes du panneau.

**Autres OPR (07:00, 09:30, 13:30)** :

- le moteur calcule leurs niveaux et leur contexte ;
- l'entrée est désactivée faute de règle documentée ;
- tes modèles ICT `OPR_0930`, `OPR_1330`… restent actifs comme en v2.22.

Si tu me donnes une fenêtre et des macros, il suffit de renseigner `InpLOOpr3Window` / `InpLOOpr3Macros` et de mettre `InpLOOpr3Trade = true` : le modèle s'appellera `OPRPDF_0930`.

## 3. Paramètres ajoutés

| Groupe | Paramètre | Défaut | Origine |
|---|---|---|---|
| Modèles ICT | `InpLondonMode` | PDF | choix de l'implémentation |
| Modèles CRT | `InpCRTMinRR` | 3 | ta règle CRT « reste à la DOL ≥ 3R » |
| London PDF : modèle | `InpLondonManage` | PDF (cible unique) | PDF |
| | `InpLondonMinRR` | 0 (aucun) | PDF : pas de RR minimal |
| | `InpLOTpStd` | 2,0 | tes notes : « 2 à 2,5 » |
| | `InpLORequireMacro`, `InpLOOneTradePerMacro` | oui, oui | PDF Macro |
| | `InpLOConsolRequireSweep` | oui | à valider (question 7) |
| | `InpLOStopBufferPts` | 0 = 1 tick | à valider (question 5) |
| | `InpLOMinStopPts`, `InpLOMaxStopPts` | 0 (aucun) | — |
| | `InpLOMaxChaseR` | 0,25 | choix technique |
| | `InpLOEntryTF`, `InpLOEntryLevel`, `InpLOMinFvgPts` | M1, bord, 1 tick | graphiques du PDF ; à valider (question 4) |
| London PDF : plages | `InpLOAsiaRange` | 20:00-00:00 | cahier |
| | `InpLOOpr1Range` / `Window` / `Macros` | 00:00-00:30 / 02:50-04:10 / 3 macros | PDF |
| | `InpLOOpr2..4` | niveaux seulement | aucune règle documentée |
| London PDF : FVG et liquidité | `InpLOAsiaRule` | bougie 2 dans la plage | cahier |
| | `InpFPFVGFromEngine` | oui | cahier |
| | swings M1 / M15 (1 bougie de chaque côté), high/low asiatique | oui | PDF étape 3 ; à valider (question 3) |
| London PDF : journal | `InpLOWarmupDays`, `InpLOJournalCsv`, `InpLOJournalPrint`, `InpLOPersist` | 3, oui, oui, oui | — |

**Valeurs par défaut modifiées** : voir le tableau du §1 (lignes 2, 5 et 6).

## 4. Tests

`tests/run_tests.sh` convertit le MQL5 en C++, le compile avec g++ contre une API MT5 simulée et exécute les tests. Cette API simule :

- les ticks ;
- les unités de temps M1 à MN1 ;
- l'ATR ;
- les ordres limites, le SL et le TP, les clôtures partielles ;
- une **vraie base SQLite**, ce qui vérifie toutes les requêtes de l'EA ;
- les fichiers Common.

Les tests d'ICT NAS jouent 60 jours, tick par tick (4 ticks par bougie M1).

**Contrôles (tous OK)** :

- les modules OPR intégrés sont identiques aux modules testés de `OPR_FVG` (112 vérifications du moteur, dont les 10 tests du cahier) ;
- une autorisation par setup malgré 4 ticks par bougie, jamais deux ordres pour le même setup, y compris après un redémarrage (test 10) ;
- chaque trade London réel correspond à une autorisation du journal, avec :
  - le même sens (test 6) ;
  - la même entrée, arrondie au tick (test 9) ;
- trades London réels = trades du modèle book ;
- entrées London uniquement dans 02:50-04:10 NY ;
- maximum 2 positions, jamais un achat et une vente en même temps ;
- maximum 3 trades exécutés par jour ;
- aucune entrée après le stop journalier ;
- perte par trade ≤ 1 % ;
- toutes les positions ont un SL et un TP ;
- 0 erreur SQL, 0 ordre refusé ;
- variantes testées :
  - observation : aucun ordre ;
  - mode London v2.22 ;
  - configuration invalide refusée avec un message ;
  - mode visuel avec tracés, gestion ICT NAS des trades London, spread.

**Comparatif avant / après** : mêmes données, 3 graines × 60 jours.

| Configuration | trades/jour | dont London PDF | dont SB Momentum | autres modèles |
|---|---|---|---|---|
| v2.22 (origine) | 1,65 | 0 | 1,40 | 0,25 |
| v2.30 avec le risque de la v2.22 | 1,79 | 0,28 | 1,28 | 0,23 |
| v2.30 sans le modèle London PDF | 2,19 | 0 | 1,94 | 0,24 |
| **v2.30** | **2,28** | **0,32** | 1,74 | 0,22 |
| option : SL max 4 ATR (profil personnalisé) | 1,89 | 0,18 | 1,58 | 0,13 |

**Attention, ces chiffres ne mesurent pas la rentabilité.** Les données sont une marche aléatoire avec des phases de tendance : aucune donnée NQ réelle n'est accessible ici. Seul le testeur MT5 sur l'historique de ton broker peut mesurer les résultats réels.

Ce que le tableau montre :

- **Effet des réglages de risque** (lignes 2 et 4 : 1,79 → 2,28) : c'est la principale source de trades supplémentaires. Une perte n'arrête plus la journée et un ordre expiré ne consomme plus le quota.
- **Effet du modèle London PDF** (lignes 3 et 4 : 2,19 → 2,28) : il ajoute peu de trades au total, car le SB Momentum occupait déjà la fenêtre de Londres. Il remplace des entrées momentum par des entrées conformes au PDF.
- **Rejet n° 1 dans les deux versions : « SL trop large »**, sur 56 % des setups ICT complets. C'est le plafond de 2,5 ATR M5 du profil Standard. L'élargir à 4 ATR n'aide pas : des trades de moindre qualité passent et le DD de 8 % est atteint (arrêt définitif). Ce plafond reste donc à 2,5.

**Point important.** Sur ces données, ta v2.22 prend déjà **1,65 trade/jour**. Si chez toi elle n'en prend presque aucun, la cause est probablement extérieure aux règles. Vérifie :

1. **Fuseau du serveur** : `InpServerTZ`. NY+7 correspond à GMT+2/+3 suivant le DST US. S'il est faux, toutes les fenêtres sont décalées.
2. **Mode de ticks du testeur** : utilise « Chaque tick » ou « Chaque tick basé sur les ticks réels ». En « Prix d'ouverture uniquement », les sweeps ne sont pas vus.
3. **Autorisation de trading** : la ligne « Trading autorisé / BLOQUÉ » au démarrage.
4. **Le diagnostic** : `Common\Files\ICTNAS\diagnostic.txt`, écrit chaque jour et à l'arrêt. Il donne l'entonnoir exact (sweeps, setups complets, décisions et raisons). Envoie-le-moi après un backtest pour un réglage précis sur ton broker.

## 5. Divergences et limites connues

**Reprises du rapport OPR + FVG :**

- Entrée sur **breaker / orderblock** (PDF) : non implémentée. Seul le FVG est utilisé (« en priorité »).
- **Cible EQH/EQL M15** prioritaire et **seconde entrée vers -3 STD** : non implémentées.
- **FPFVG de minuit** : le PDF demande « le plus évident » ; l'EA prend le premier FVG M1 ≥ taille minimale. C'est une référence seulement.
- **Méthode CRT 5 h / 9 h du PDF** (DOL, SMT EUR/USD–GBP/USD) : non formalisée. Tes modèles CRT de la v2.22 sont inchangés.

**Propres à la fusion :**

- Le modèle book du moteur ignore les filtres d'ICT NAS : risque du jour, conflit, news. Dans les tests, 58 des 93 trades book (environ 60 %) sont exécutés réellement ; les autres sont surtout bloqués parce qu'un trade SB Momentum occupe déjà la fenêtre de Londres. Les trades exécutés sont, eux, identiques à ceux du book.
- Après un redémarrage de MT5, un ordre London déjà envoyé n'est pas doublé (identifiant déterministe `LP<id>`). Comme en v2.22, la gestion active (BE, partiels) des positions **ouvertes avant le redémarrage** n'est pas reprise. Leur SL et leur TP restent chez le broker.

## 6. Questions pour finaliser

1. Peux-tu m'envoyer le `diagnostic.txt` d'un backtest v2.22 sur ton broker ? Indique aussi :
   - le symbole ;
   - le décalage GMT du serveur ;
   - le mode de ticks.
2. Valides-tu les nouveaux réglages de risque (1 % / -2 % / +3 %, 2 positions) ? Ou veux-tu garder 3 % par trade ?
3. Liquidités du modèle PDF : swings M1/M15 + high/low asiatique (actuel). Faut-il ajouter les EQH/EQL ? La prise peut-elle précéder 2:50 ?
4. FVG d'entrée : M1 au bord (actuel) ou au CE ? Faut-il une taille minimale en points ?
5. SL du modèle PDF : 1 tick au-delà du swing (actuel), ou un buffer en points comme tes autres modèles (4 points) ?
6. Cible : 2,0 STD (actuel) ou 2,5 ? Faut-il une 2e entrée vers -3 STD (exemple 2 du PDF) ?
7. Consolidation à 2:50 : faut-il une prise de liquidité après la clôture hors du MOR (actuel) ?
8. OPR 09:30 / 13:30 : faut-il appliquer le même modèle PDF ? Si oui, avec quelles fenêtres et quelles macros ? C'est le levier le plus direct vers 2 trades « PDF » par jour.
9. Breaker / unicorn du PDF Macro : faut-il les ajouter comme entrées ?
