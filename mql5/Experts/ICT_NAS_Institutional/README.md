# ICT NAS Institutional v2.51

La v2.51 applique l'audit « la v2.50 s'est éloignée d'ICT en cherchant à prendre des trades ». **Chaque ajout est derrière un input** pour être comparé en backtest. Les entrées, les SL, le risque et les limites journalières ne changent pas.

## Bugs corrigés

| # | Bug | Correction | Paramètre |
|---|---|---|---|
| 1 | Le suivi virtuel ignorait la 1re minute de chaque signal (la bougie en cours lors de la création était rejetée) : `r_multiple`, l'apprentissage modèle × session et le ML étaient biaisés | `Step()` accepte la bougie qui contient l'heure du signal | — |
| 2 | Le facteur « FVG valide » valait toujours 1 (10 points gratuits) : le score ne filtrait presque rien | Remplacé par **le biais journalier** (`daily_bias`) | `InpDailyBiasMode` |
| 3 | Un même sweep pouvait donner `SILVER_BULLET`, `SB_V6`, `LONDON_OPR_PDF` et `CRT_0250` : risque doublé sur une seule idée | **Un seul trade par sweep** (même sens, 15 min), tous moteurs confondus. Refus : `REJECTED_CONFLICT (meme sweep deja trade)` | `InpOneTradePerSweep = true` |
| 4 | Au lot minimum, le partiel est impossible en réel mais la simulation comptait 50 % au TP1 | La répartition des sorties est calculée sur le lot réel (arrondi au pas), en réel et en simulation, pour les signaux pris **et** non pris. Colonne `partial_ok` | — |
| 5 | Filtre news inactif dans le testeur sans `news_usd.csv` | En réel/démo, l'EA **exporte le calendrier MT5** (USD, impact fort, 5 ans) vers `Common\Files\ICTNAS\news_usd.csv`, lu ensuite par le testeur. Sans ce fichier, alerte dans le journal et dans `diagnostic.txt` | `InpNewsExportCSV = true`, `InpNewsExportYears = 5` |

**Changement d'heure :** l'Europe est passée à l'heure d'hiver le 25 octobre, les États-Unis le font le 1er novembre. Avec `InpServerTZ = TZ_NY_PLUS_7` et un broker qui suit le DST US, rien à faire. Sinon, vérifie la ligne `Fuseau serveur verifie` au démarrage en réel.

## Retour à ICT

| Ajout | Détail | Paramètre (défaut) |
|---|---|---|
| **Biais journalier** | Bougie du jour de trading précédent (18:00 → 17:00 NY, calculée en H1, donc indépendante du fuseau du serveur) : clôture au-dessus du haut de l'avant-veille → haussier ; sous le bas → baissier ; purge du haut puis clôture dedans → baissier ; purge du bas puis clôture dedans → haussier ; inside day → aucun biais | `InpDailyBiasMode = DBIAS_SCORE` (OFF / SCORE / FILTRE) |
| Règle NY AM (mode FILTRE) | 07:00-12:00 NY, en biais haussier : achat **sous le Midnight Open**, après la prise d'une SSL depuis minuit (Judas). Vente : l'inverse | `InpJudasRule = true` |
| Inside day | En FILTRE, un jour sans biais n'est pas bloqué, sauf si tu le demandes | `InpDailyBiasNoneBlocks = false` |
| **MSS significatif** | Le swing cassé doit être à au moins x ATR M5 de l'extrême du sweep : un fractal M1 à 2 points n'est plus un MSS | `InpMSSMinRangeATR = 0.3` (0 = comme la v2.50) |
| CISD seul | `false` = la cassure d'un swing est exigée | `InpAllowCISDOnly = true` |
| **Silver Bullet** | Le FVG doit se **former** dans la fenêtre (bougie 3), et l'entrée rester possible avant sa fin | — |
| **Source de la cible** | Colonne `tp_source` : `DOL` (liquidité, STD du MOR, IRL...), `CAP` (DOL plafonnée à 5 R), `FALLBACK` (cible inventée) | — |
| ICT strict | `false` = pas de DOL, pas de trade (aussi pour les modèles v6.20) | `InpAllowFallbackTarget = true` |
| Macros | Génériques (xx:50-xx:10, xx:20-xx:40) ou publiées par ICT : 02:33-03:00, 04:03-04:30, 08:50-09:10, 09:50-10:10, 10:50-11:10, 11:50-12:10, 13:10-13:40, 15:15-15:45 | `InpMacroTable = MACRO_GENERIC` |

**Base SQLite :** trois colonnes sont ajoutées à `signals` (`daily_bias`, `tp_source`, `partial_ok`). Une base existante est migrée automatiquement au démarrage. Dans `ict_quant`, le facteur `fvg_valid` devient `daily_bias` : un fichier `ict_weights.json` ou un modèle ONNX entraîné avec l'ancien nom doit être régénéré (sinon : poids par défaut, et le ML voit 0 pour ce facteur).

**Non traité ici :** les modèles CRT restent des étiquettes horaires. La vraie Candle Range Theory (range d'une bougie H1/H4/D1, purge de son extrême, clôture dedans, cible l'extrême opposé) est un nouveau modèle à part entière. Le TP1 reste à 2 R au lieu de la première liquidité opposée.

## Banc de test (données synthétiques, 3 graines × 60 jours)

| Configuration | Trades / jour | R total (R / trade) | Gagnants / perdants |
|---|---|---|---|
| v2.50 | 2,55 | 266 R (0,58) | 238 / 221 |
| **v2.51 (défaut : biais en score)** | 2,44 | 257 R (0,59) | 228 / 211 |
| v2.51 + biais en FILTRE (Judas NY AM) | 2,00 | 220 R (0,61) | 199 / 161 |
| v2.51 ICT strict (filtre, sans cible de secours, MSS exigé) | 2,00 | 211 R (0,59) | 196 / 164 |
| v2.51 sans les modèles v6.20 | 1,87 | 233 R (0,69) | 177 / 160 |

- **Écart entre le R réel et le R simulé d'un même trade** : 0,18 R → 0,11 R (graine 71) et 0,10 R → 0,06 R (graine 72). C'est l'effet du bug n°1 : tes données d'apprentissage sont plus justes.
- **Les données synthétiques sont une marche aléatoire : un biais journalier n'y a aucune valeur.** Le tableau montre seulement combien de trades chaque option enlève, pas si elle est rentable. Seul ton historique réel répondra.

## Mesurer avant d'ajouter

1. Lance l'EA une fois en démo ou en réel : il exporte `news_usd.csv` (journal : `News : N dates USD … exportees`).
2. Backtest long (12 mois si possible), M1, « chaque tick basé sur les ticks réels », `InpProfile = Agressif` pour tout capturer.
3. Ouvre `Common\Files\ICTNAS\ict_nas.sqlite` et lance `analyse_v251.sql` :
   - espérance par modèle × session ;
   - avec ou contre le biais journalier ;
   - cibles `DOL` / `CAP` / `FALLBACK` ;
   - sorties au BE ;
   - trades sans partiel possible.
4. Garde les 2 ou 3 couples modèle × session à espérance positive, coupe le reste avec leurs interrupteurs.
5. Refais le test avec `InpDailyBiasMode = DBIAS_FILTER` sur la même période : garde le filtre s'il améliore l'espérance.
6. Valide sur une autre période que celle qui a servi à choisir.

Pour le break-even à 1 R, le MFE s'arrête à la sortie : compare plutôt deux backtests, `InpBEAtR = 1` contre `InpBEAtR = 0`.

---

# Historique : v2.50

La v2.50 répond à « il n'est pas vraiment rentable, fais qu'il prenne des trades et trouve des entrées adaptées à mes stratégies ». **Tes entrées, tes SL, tes RR et ton risque ne changent pas.** Trois choses changent :

| # | Changement | Paramètre (défaut) | Revenir à la v2.40 |
|---|---|---|---|
| 1 | **Objectif journalier +3 % atteint** : plus aucune nouvelle entrée et les ordres en attente sont supprimés, mais **les positions ouvertes vont à leur SL ou à leur cible** (DOL, 2 STD du MOR). Le stop journalier -2 % ferme toujours tout, même après l'objectif. | `InpCloseOnDailyTarget = false` | `true` |
| 2 | **Testeur seulement** : le DD total de 8 % est signalé avec sa date (journal et `diagnostic.txt`), et le backtest continue. **En réel, l'arrêt définitif est inchangé.** | `InpDDHaltInTester = false` | `true` |
| 3 | **Apprentissage par modèle × session** (règle de ta v6.20) : l'EA mesure le résultat de chaque setup conforme aux règles de son modèle, pris ou non, et l'écrit dans `diagnostic.txt`, section 9. Le blocage automatique des combinaisons perdantes est une option. | `InpAdaptGate = false`, `InpAdaptMinSamples = 25` | rien à faire (désactivé par défaut) |

Le reste est identique à la v2.40 :

- schéma SQLite (seule la valeur `ea_version` devient « 2.50 ») ;
- entrées, règles de SL, RR minimaux, score et ML ;
- risque de 1 %, stop journalier de -2 %, objectif de +3 % (plus d'entrée une fois atteint) ;
- 3 trades par jour, 2 positions, flat à 15:50.

Aucune fonctionnalité n'est supprimée.

## 1. Pourquoi

### 1.1 L'objectif journalier coupait les gagnants

Le plan de chaque trade, c'est ta stratégie : BE à 1 R, 50 % au TP1 (2 R), le reste à la DOL (jusqu'à 5 R), ou une cible unique à 2 STD du MOR pour le London PDF.

L'objectif journalier se mesure sur l'**équité**, donc flottant compris. En v2.40, dès que l'équité du jour atteignait +3 %, `CheckDayGuards()` fermait tout, y compris la moitié restante qui visait la DOL et le second trade ouvert. À 1 % de risque, +3 % = 3 R : un seul trade London PDF ou un trade ICT à +4 R suffisait à déclencher la fermeture.

Ta v6.20 n'a pas d'objectif de gain journalier. Ton RiskGuard ne ferme les positions que sur la perte. La v2.50 garde ta règle « objectif +3 % » au sens « on arrête de prendre des trades », sans couper les trades en cours.

### 1.2 Le DD total arrêtait le backtest

Au premier -8 % sous le solde de départ, la v2.40 ne prenait plus aucun trade jusqu'à la fin du test. Sur le banc, avec le seuil forcé à 1 % pour provoquer le cas, voici les trades sur 3 × 60 jours :

| Version | Trades |
|---|---|
| v2.40 | **171** (0,95 par jour) : l'EA s'arrête en cours de test |
| v2.50 | **459** (2,55 par jour) : le DD est signalé, le test continue |

C'est le symptôme « il ne prend presque pas de trades » sur un long backtest. En réel, c'est ta règle prop firm, et elle est conservée.

### 1.3 Quelles entrées marchent chez toi

Les R par modèle du simulateur viennent de données synthétiques : ils ne permettent pas de choisir tes entrées. La v2.50 mesure donc chaque **modèle × session** sur ton historique, avec la règle `ADAPT_SIZE_AND_GATE` de ta v6.20 (n ≥ 25 et E[R] + 1 erreur standard < 0 = perte démontrée).

Ce qui est compté :

- **compte** : le résultat virtuel de chaque setup dont le plan passe les règles du modèle (filtres, RR, score, ML), qu'il ait été pris ou refusé ensuite pour le risque du jour, le quota ou un conflit ;
- **ne compte pas** : les plans rejetés pour « SL trop large », un RR insuffisant ou un filtre horaire, puisqu'ils n'auraient jamais été tradés.

`diagnostic.txt` affiche en section 9 une ligne par combinaison ayant au moins 25 setups, par exemple `MACRO_BREAKER|NY AM KZ : n=71 E[R]=-0.09 +/- 0.11`. La mention `-> ESPERANCE NEGATIVE DEMONTREE` apparaît quand la règle s'applique.

Avec `InpAdaptGate = true`, ces combinaisons sont refusées (`REJECTED_FILTER`, raison `adaptatif : …`). Leurs setups restent simulés, donc une combinaison se débloque si son espérance remonte. Le défaut est `false`, comme dans ta v6.20 : sur des données aléatoires, le blocage ne peut réagir qu'au bruit.

## 2. Résultats sur le banc de test (données synthétiques)

Mêmes données, 3 graines × 60 jours, avec les mêmes contrôles que la v2.40 (tous OK) :

| Configuration | Trades / jour | R total (R / trade) | Gagnants / perdants | Perte max / trade |
|---|---|---|---|---|
| v2.40 | 2,55 | 164 R (0,36) | 243 / 216 | 1,02 % |
| **v2.50** | **2,55** (mêmes trades) | **266 R (0,58)** | 238 / 221 | 1,02 % |
| v2.50 + `InpAdaptGate = true` | 2,54 | 261 R (0,57) | 236 / 221 | 1,02 % |
| v2.50 sans les modèles v6.20 | 2,28 | 291 R (0,71) | 217 / 194 | 1,00 % |
| v2.50, petit compte (10 000, lot min 0,1) | 2,54 | 309 R (0,67) | 248 / 209 | 1,50 % |
| v2.40, DD total forcé à 1 % | **0,95** | 48 R (0,28) | 87 / 84 | 1,01 % |
| v2.50, DD total forcé à 1 % | **2,55** | 266 R (0,58) | 238 / 221 | 1,02 % |
| option RiskGuard : SL ramené au plafond | 2,57 | 445 R (0,96) | 277 / 185 | 1,02 % |

Ce que montre le tableau :

- **Mêmes entrées, sorties différentes.** La v2.50 prend exactement les 459 trades de la v2.40. Le total passe de 164 R à 266 R uniquement parce que les gagnants ne sont plus fermés à +3 % d'équité.
- **Le DD total ne vide plus le backtest** : 171 trades en v2.40 contre 459 en v2.50 quand le seuil est atteint tôt.
- **Le blocage par l'apprentissage n'apporte rien sur ces données** (261 R contre 266 R). C'est attendu sur une marche aléatoire : il n'a de valeur que si tes modèles ont un avantage durable par session sur le vrai NAS100. C'est pourquoi il est désactivé par défaut.
- **Sur ces données, les modèles v6.20 diminuent le total en R** (291 R sans eux contre 266 R avec). Ils prennent des places dans la limite de 3 trades par jour. Vérifie-le sur ton historique avec `InpV6EnableSB` / `InpV6EnableMB` et la requête de l'étape 2 ci-dessous.
- **L'option « SL ramené au plafond » donne le meilleur total ici**, mais elle place le SL à l'intérieur de la zone du sweep, contrairement à ta règle. Ne l'adopte que si ton historique réel le confirme.

**Ce sont des données synthétiques : elles montrent l'effet du mécanisme, pas la rentabilité sur le NAS100.** Seul ton testeur MT5 dira si le marché va plus souvent jusqu'à tes DOL qu'il ne revient en arrière après +3 %.

## 3. Vérifier dans le testeur MT5

### Étape 0 : mesurer le changement 1 sur un backtest v2.40 déjà fait

Ouvre `Common\Files\ICTNAS\ict_nas.sqlite` avec ict_quant ou DB Browser for SQLite (onglet « Exécuter le SQL ») :

```sql
-- R réel (trades) contre R du plan (simulation virtuelle, sans fermeture à l'objectif journalier)
SELECT s.model, COUNT(*) AS n,
       ROUND(SUM(t.r_multiple),1) AS R_reel,
       ROUND(SUM(s.r_multiple),1) AS R_plan
FROM trades t JOIN signals s ON s.signal_uid = t.signal_uid
WHERE s.decision = 'TAKEN'
GROUP BY s.model ORDER BY R_plan DESC;
```

- Si `R_plan` est nettement au-dessus de `R_reel`, la fermeture à l'objectif t'a coûté la différence.
- Sinon, sur ton historique le marché revenait en arrière après +3 %. Garde alors `InpCloseOnDailyTarget = true`.

### Étape 1 : test A/B, même période, mêmes réglages

- **Testeur** : ton NAS100 / US100, graphique M1, « Chaque tick basé sur les ticks réels ». Période d'au moins 6 mois, si possible 12, avec le même dépôt pour tous les tests.
- **Test A, v2.50** : réglages par défaut.
- **Test B, comportement v2.40** : `InpCloseOnDailyTarget = true` et `InpDDHaltInTester = true`.
- **Après chaque test**, copie `Common\Files\ICTNAS\ict_nas.sqlite` et `diagnostic.txt` sous un autre nom. La base est vidée au test suivant.

Compare dans l'onglet Backtest :

- nombre de trades ;
- profit net ;
- facteur de profit ;
- espérance ;
- drawdown maximal.

Dans le Journal du test A, cherche :

- `Objectif journalier atteint` : les jours où les gagnants ont continué ;
- `DD total … atteint le` : la date à laquelle un compte prop se serait arrêté.

### Étape 2 : quelles entrées marchent sur ton marché

Lis la section 9 de `diagnostic.txt` du test A. Pour le détail, lance sur la base du test A :

```sql
-- Plans conformes aux règles du modèle, pris ou non
SELECT model, session, COUNT(*) AS n, ROUND(AVG(r_multiple),2) AS R_moyen,
       ROUND(SUM(r_multiple),1) AS R_total, SUM(decision='TAKEN') AS pris
FROM signals
WHERE filled = 1 AND outcome IN ('WIN','LOSS','BE')
  AND decision NOT IN ('REJECTED_SCORE','REJECTED_ML')
  AND NOT (decision = 'REJECTED_FILTER' AND reject_reason NOT LIKE 'adaptatif%')
  AND NOT (decision = 'REJECTED_RISK' AND (reject_reason LIKE 'SL trop large%'
           OR reject_reason LIKE 'RR %' OR reject_reason LIKE 'pas de cible%'))
GROUP BY model, session HAVING COUNT(*) >= 25
ORDER BY R_moyen;
```

Ensuite, deux voies possibles :

- **Voie manuelle** : coupe un modèle qui perd sur toutes ses sessions avec son interrupteur :

  | Modèle | Interrupteur |
  |---|---|
  | `SHADOW` | `InpUseShadow` |
  | `SILVER_BULLET` | `InpUseSB` |
  | `KILLZONE` | `InpUseKillzoneModel` |
  | `SB_MOMENTUM` | `InpUseMomentum` |
  | `CRT_*` | `InpUseCRT45` / `InpUseCRTOPR` / `InpUseCRT0830` / `InpUseCRT0250` / `InpUseCRTPM` |
  | `OPR_*` | `InpUseOPR0130` / `0700` / `0930` / `1330` |
  | `ERL_IRL` | `InpUseERL` |
  | `LONDON_OPR_PDF` | `InpLOOpr1Trade` |
  | `SB_V6` | `InpV6EnableSB` |
  | `MACRO_BREAKER` | `InpV6EnableMB` |

- **Voie automatique** : refais le test A avec `InpAdaptGate = true`.

**Ne valide jamais un choix sur la période qui a servi à le faire.** Choisis sur les 6 premiers mois, puis vérifie sur les 6 suivants.

### Étape 3 (option) : encore plus de trades

Deux règles de ta v6.20 changent tes règles ICT NAS, elles ne sont donc pas activées par défaut :

- `InpMaxTradesDay = 8`, au lieu de 3 ;
- `InpDailyTargetPct = 0`, car la v6.20 n'a pas d'objectif de gain.

Teste-les dans un test D, contre le test A.

## 4. Limites (v2.50)

- **Compilation** : le code est vérifié par traduction en C++ et par le banc de test, pas dans MetaEditor. Si MetaEditor signale une erreur, envoie-la-moi telle quelle.
- **Après l'objectif, la journée peut finir sous +3 %** si les positions conservées reviennent à leur BE ou à leur SL. C'est le prix à payer pour les laisser aller à leur cible. Le stop -2 % reste le plancher.
- **`InpDDHaltInTester = false` montre des trades qu'un compte prop n'aurait plus pris** après la date du DD. Le journal et le diagnostic donnent cette date, et `true` reproduit le compte réel.
- **L'apprentissage vit en mémoire.** En réel, un redémarrage de l'EA le remet à zéro. Dans le testeur, chaque passe repart de zéro, comme la base SQLite.
- **Fin de test** : une position encore ouverte à la fin des données n'a pas de ligne dans `trades`. Le banc de test le prend en compte.
- **Origine** : la v2.50 vient du tournoi `/arena` lancé à ta demande. Il a été interrompu par la limite d'usage et une seule solution a été terminée, donc sans match ni jugement. Je l'ai appliquée puis vérifiée avec le banc de test complet.

---

# Historique : v2.40 (union des EA)

La v2.40 réunit **tes EA ICT dans un seul EA**, avec une seule chaîne de décision, de risque et de données :

- **ICT NAS v2.22** : le cœur, avec tous ses modèles, son contexte, son score, le ML, SQLite et la gestion des trades ;
- **OPR + FVG** : le modèle London OPR du PDF, déjà fusionné en v2.30 ;
- **ICT Ultimate Pro v6.20** : le Silver Bullet « 1er FVG » et le Macro Breaker / Unicorn ;
- **ICT_RiskGuard** : les garde-fous de risque.

Elle corrige aussi les causes du « un seul trade dans mes tests ».

- **Un seul fichier** : `ICT_NAS_Institutional.mq5`. Copie-le dans `MQL5\Experts\` puis compile-le dans MetaEditor.
- **Rien n'est supprimé.** Chaque nouveauté peut être désactivée par un paramètre. Le schéma SQLite est inchangé, donc ict_quant reste compatible.
- **Versions précédentes** : la v2.22 et la v2.30 restent dans `tests/ref/` pour la comparaison.

## 1. Pourquoi tes tests ne montraient qu'un seul trade

| # | Cause | Ce qui se passait | v2.40 |
|---|---|---|---|
| 1 | **Ordre de test du testeur** (`InpSelfTest = true`) | Au démarrage, l'EA ouvrait puis fermait 1 lot minimum pour vérifier l'exécution. Ce trade apparaît dans le rapport. Si l'EA ne trade pas ensuite, le rapport montre **exactement 1 trade**. | Désactivé par défaut. Le diagnostic le signale s'il est activé. |
| 2 | **Lot minimum trop risqué** | À 1 % de risque, sur un petit compte, ou si le lot minimum du symbole est gros (0,1 ou 1 lot), chaque setup est refusé (« lot < lot minimum »). Sur le test « petit compte », la v2.30 refuse ainsi **282 setups** en 3 × 60 jours. | Règle de ta v6.20 : le lot minimum est accepté si son risque reste **≤ 1,5 × le risque voulu**, jamais au-delà du plafond dur de 3 %. Sinon, le refus est expliqué en chiffres. Résultat : **70 refus** sur le même test. |
| 3 | **DD total 8 % = arrêt définitif** | C'est la règle prop firm de ton RiskManager. Sur un long backtest, après un drawdown de 8 %, l'EA ne prend **plus aucun trade jusqu'à la fin**. | Règle conservée. Le diagnostic l'indique clairement ; mets `InpMaxTotalDDPct = 0` pour un backtest long. |
| 4 | **« SL trop large »**, rejet n° 1 (≈ 55 % des setups ICT complets) | Ta règle impose un SL au-delà du sweep, plafonné à 2,5 ATR M5 (profil Standard). | Règle conservée par défaut. Option RiskGuard : `InpSLCapMode = SL ramené au plafond` (voir §6). |
| 5 | **Mode « Prix d'ouverture uniquement »** | Les prises de liquidité étaient détectées au tick. Sans les mèches, une prise pouvait passer inaperçue. | Elles sont aussi détectées sur la mèche de chaque bougie M1 clôturée. Le test « 1 tick par bougie » trade normalement. Pour un résultat fiable, utilise quand même « Chaque tick basé sur les ticks réels ». |
| 6 | **Comptage des trades du jour** | Le compteur était en mémoire : il repartait de zéro après un redémarrage. Un trade ouvert et fermé sur le même tick n'était ni compté ni enregistré : 126 lignes `trades` pour 128 exécutions sur un test v2.30. | Les entrées du jour sont relues dans l'historique du compte (règle RiskGuard). Chaque exécution a sa ligne dans `trades`. |

Vérifie aussi :

- le fuseau du serveur, avec `InpServerTZ` ;
- la ligne « Trading autorisé / BLOQUÉ » au démarrage.

**Le fichier le plus utile** : `Common\Files\ICTNAS\diagnostic.txt`, écrit chaque jour et à l'arrêt. Il contient l'entonnoir complet :

- les sweeps et les setups ;
- les décisions avec leurs raisons ;
- les modèles v6.20 et leurs raisons de rejet ;
- en section 8, **les pistes en clair** : lot minimum, DD total, SL trop large, limites journalières, ordre de test.

## 2. L'union des EA : qui apporte quoi

| EA | Repris dans la v2.40 | Non repris, et pourquoi |
|---|---|---|
| **ICT NAS v2.22** (ton EA principal) | Tout, comme base et chaîne de décision unique :<br>- modèles Shadow, Silver Bullet, CRT, Killzone, SB Momentum, OPR, ERL→IRL ;<br>- contexte (MOR/OPR/STDV, liquidité, gaps, Quarterly, SMT, news) ;<br>- score ICT, ML ONNX ;<br>- SQLite, partiels, panneau, diagnostic. | — |
| **OPR + FVG** (cahier + PDF, v2.30) | Modèle `LONDON_OPR_PDF` (§ Historique v2.30). | — |
| **ICT Ultimate Pro v6.20** | Détection, portée telle quelle avec le préfixe `V6` :<br>- `SB_V6` (Silver Bullet 1er FVG) et `MACRO_BREAKER` (breaker / Unicorn dans les macros ICT) ;<br>- carte de liquidité v6.20 (IPDA 20/40/60, sessions, EQH/EQL, PDH/PDL, PWH/PWL) ;<br>- niveaux de référence (true opens, OPR, TBR 08:12-09:12, NDOG/NWOG) ;<br>- score v6.20 (OTE, macro, true open, BPR, profil hebdo), cibles en déviations standard ;<br>- passe stricte puis relâchée, arbitrage SB / MB, 1 trade par fenêtre / macro ;<br>- tolérance de 150 % sur le lot minimum ;<br>- filtre de spread en fraction d'ATR (option). | - Moteur d'exécution, risque, journal CSV, apprentissage adaptatif, ONNX, news et licence : remplacés par leurs équivalents ICT NAS, pour une seule chaîne de risque et une seule base de données.<br>- Gestion des positions v6.20 (partiel 40 % à 2R, trailing ATR, time stop) : les trades suivent la gestion ICT NAS.<br>- Entrée « OB après le FVG » : option non utilisée par défaut dans la v6.20. |
| **ICT_RiskGuard** | - Risque ouvert cumulé max 3 % : positions dont le SL n'est pas au BE, plus les ordres en attente.<br>- Lot maximum absolu, délai minimum entre deux ordres.<br>- SL borné : option « ramené au plafond ».<br>- Entrées du jour lues dans l'historique.<br>- Déjà présents dans ICT NAS : jamais d'achat et de vente en même temps, 2 positions maximum, partiel unique, lot arrondi vers le bas. | - `MaxTP_RR = 3` : ta cible ICT est la liquidité (DOL), plafonnée à 5 R par le profil Standard.<br>- `MaxMarginUsePct = 20` : ICT NAS a déjà `InpMaxMarginPct` (80 %). Mets 20 si tu veux la valeur du RiskGuard. |
| **ICT Ultimate Pro v6.00** | Seul son module RiskGuard (ligne ci-dessus). | Sa stratégie EMA 7/21/50 + UT Bot est un croisement de moyennes, pas un modèle ICT. |
| **LRL Map** (autre EA du dépôt) | — | Concept différent : LRL + iFVG sur des timeframes de 1 à 5 min reconstruits, avec ses propres statistiques. Il peut devenir un modèle de plus si tu le souhaites (question 5). |

## 3. Comment l'EA décide

À chaque bougie M1 :

1. **Contexte** : heure de New York, MOR/OPR, carte de liquidité, gaps, Quarterly, SMT, news.
2. **Trois moteurs proposent des setups** :
   - la séquence ICT NAS : sweep → MSS/CISD → displacement → FVG ;
   - le moteur London OPR du PDF ;
   - le moteur v6.20 : Silver Bullet 1er FVG et Macro Breaker.
3. **Chaque setup suit la même chaîne** :
   1. filtres horaires (lunch, news, macro d'accumulation 15:15-15:45, flat 15:50) ;
   2. RR et score du modèle, ML ;
   3. risque du jour (stop -2 %, objectif +3 %, DD 8 %), 3 trades exécutés par jour au plus ;
   4. un seul sens à la fois, 2 positions maximum ;
   5. spread et délai entre deux ordres (options) ;
   6. lot (tolérance sur le lot minimum) ;
   7. risque ouvert ≤ 3 % ;
   8. ordre.
4. **Plusieurs setups sur la même bougie** : priorité Shadow > CRT 45 min > Silver Bullet (ICT NAS et v6.20) > CRT 08:30 / Macro Breaker > London OPR > OPR…
5. **Gestion** : BE à 1R, 50 % au TP1, reste à la cible, flat à 15:50. Le modèle London PDF garde sa cible unique.

Chaque setup est enregistré dans SQLite, pris ou rejeté, avec son modèle (`SB_V6`, `MACRO_BREAKER`…). Tu peux donc mesurer chaque modèle séparément avec ict_quant.

## 4. Les modèles v6.20

### SB_V6 : Silver Bullet, 1er FVG (M5)

Fenêtres : 03:00-04:00, 10:00-11:00 et 14:00-15:00 NY.

1. **Sweep confirmé** d'une liquidité de la carte v6.20 :
   - pénétration ≥ 0,04 ATR ;
   - retour en 3 bougies au plus ;
   - pas plus de 6 bougies au-delà du niveau ;
   - le sweep peut précéder la fenêtre de 45 min.
2. **MSS** dans les 15 bougies, avec un displacement dont le corps fait ≥ 0,8 ATR M5.
3. **1er FVG de la jambe** (≥ 0,12 ATR) : ordre limite au bord proximal du FVG, si le retracement de la jambe atteint au moins 35 %.
4. **SL** derrière l'extrême du sweep + 0,1 ATR, au plus 6 ATR M5.
5. **TP** juste avant le pool opposé le plus proche, à 1,5 ATR D1 au plus. RR ≥ 2 ; sans pool atteignable, cible au RR minimum.
6. **Score** ≥ 3.

**Passe relâchée** 30 min après le début de la fenêtre si rien n'est passé :

- plus d'exigence de biais HTF, de discount, de true open ni de corps ;
- score - 3, RR ≥ 1,5 ;
- seuils de displacement, de FVG et de sweep × 0,6.

### MACRO_BREAKER : breaker / Unicorn (M1)

Macros autorisées : 03:20, 03:50, 08:20, 09:20, 09:50, 10:20, 10:50, 11:20, 13:20, 14:20, 15:15 et 15:50.

1. **Stop hunt** dans les 90 dernières bougies M1.
2. **Breaker confirmé** par un corps au-delà du corps du swing opposé, dans les 30 bougies, pendant la macro ou au plus 25 min avant.
3. **Displacement** ≥ 0,8 ATR M1.
4. **Entrée au bord du breaker.** Unicorn si un FVG est dans le breaker.
5. **SL** derrière le breaker (ou derrière le sweep si le breaker fait moins de 0,5 ATR) + 0,2 ATR, × 1,5 pendant la macro 09:20. Au plus 12 ATR M1.
6. **TP** avant le pool, RR ≥ 2. Pas de trade si la cible est atteinte avant l'entrée.
7. **Score** ≥ 2.
8. **Retest** accepté jusqu'à 25 min après la macro. Passe relâchée après 8 min.

Si les deux modèles ont un setup, l'arbitrage de la v6.20 s'applique : setup strict prioritaire, puis meilleur score, puis Unicorn.

### Intégration dans ICT NAS

- **Paramètres** : toutes les valeurs par défaut sont celles de ta v6.20 (groupes « v6.20 : … »). La v6.20 était réglée pour l'or, mais tous ses seuils sont en ATR et ses heures en heure de New York : ils s'adaptent au NAS100.
- **Filtres horaires d'ICT NAS appliqués avant l'évaluation**, comme le blackout news de la v6.20 : un setup n'est pas perdu à cause d'un filtre horaire. Avec les réglages ICT NAS, **les macros 15:15 et 15:50 ne sont donc pas tradées** (macro d'accumulation et flat à 15:50). Pour les activer : `InpBlockAccumMacro = false` et/ou un `InpFlatTime` plus tardif.
- **RR et score** : ceux de la v6.20 (RR 2, ou 1,5 en passe relâchée ; score 3 pour le SB, 2 pour le MB). Le score ICT NAS est calculé et enregistré, sans bloquer.
- **1 trade par fenêtre / macro**, compté comme la v6.20 : ordres v6.20 en attente, plus entrées v6.20 depuis le début de la fenêtre. Un Macro Breaker de 10:20 compte donc aussi dans la fenêtre Silver Bullet 10:00-11:00.
- **Une décision par setup** : la v6.20 retentait un setup refusé pour le risque à la bougie suivante. Ici, chaque setup est décidé une fois, pour garder une ligne par setup dans SQLite.
- **Fuseau** : seul `InpServerTZ` d'ICT NAS compte. Les paramètres d'offset de la v6.20 ne sont pas repris.

## 5. Nouveaux paramètres

| Groupe | Paramètre | Défaut | Origine |
|---|---|---|---|
| v6.20 : Silver Bullet 1er FVG et Macro Breaker | `InpV6EnableSB`, `InpV6EnableMB` | oui, oui | ta v6.20 |
| | `InpV6MaxTradesPerWindow` | 1 | v6.20 |
| | `InpV6SBRelaxAfterMin`, `InpV6MBRelaxAfterMin` | 30, 8 | v6.20 |
| | `InpV6UseLondonSB`, `InpV6UseNYAMSB`, `InpV6UseNYPMSB` | oui | v6.20 |
| v6.20 : Silver Bullet (M5), Macro Breaker (M1), tips ICT | tous les `InpV6…` | valeurs de la v6.20 | v6.20 |
| Garde-fous (RiskGuard / v6.20) | `InpMinLotRiskTol` | 1,5 | v6.20 (150 %) |
| | `InpMaxLots` | 0 = aucun | RiskGuard : 1,00 (dépend du compte, à régler) |
| | `InpMaxOpenRiskPct` | 3 | RiskGuard |
| | `InpMinSecondsBetweenTrades` | 0 = aucun | RiskGuard : 900 |
| | `InpMaxSpreadATR` | 0 = aucun | v6.20 : 0,15 |
| | `InpSLCapMode` | rejet | ta règle « SL toujours au-delà du sweep » ; RiskGuard : ramené au plafond |
| Diagnostic | `InpSelfTest` | **non** (v2.30 : oui) | cause n° 1 du « 1 seul trade » |

`InpMaxLots`, `InpMinSecondsBetweenTrades` et `InpMaxSpreadATR` sont désactivés par défaut. Avec les valeurs du RiskGuard ou de la v6.20, ils réduiraient le nombre de trades, alors que c'est justement ton problème. Active-les si tu veux exactement ces règles.

## 6. Tests et comparatif

`tests/run_tests.sh` convertit le MQL5 en C++, le compile avec g++ contre une API MT5 simulée, puis joue 60 jours tick par tick (4 ticks par bougie M1). L'API simule :

- les unités de temps ;
- l'ATR ;
- les ordres, SL, TP et partiels ;
- l'historique des deals ;
- une vraie base SQLite.

**Contrôles v2.40 (tous OK)**, en plus de ceux de la v2.30 :

- les modèles v6.20 prennent des trades ;
- jamais plus d'une entrée v6.20 par fenêtre Silver Bullet ou par macro ;
- chaque exécution a sa ligne dans `trades` : 459 exécutions, 459 lignes. La v2.30 en perdait 3 sur 411 ;
- au plus 3 trades exécutés par jour, 2 positions, jamais un achat et une vente en même temps ;
- aucune entrée après le stop journalier ;
- perte par trade ≤ 1 % (≤ 1,5 % sur le petit compte, avec la tolérance du lot minimum) ;
- l'EA trade régulièrement (plus de 20 trades sur 60 jours) ;
- variantes testées :
  - observation ;
  - redémarrage en cours de route ;
  - London v2.22 ;
  - configuration invalide ;
  - mode visuel ;
  - petit compte ;
  - testeur en « prix d'ouverture » (1 tick par bougie).

**Comparatif** (mêmes données, 3 graines × 60 jours) :

| Configuration | trades/jour | dont London PDF | dont SB Momentum | dont v6.20 (SB 1er FVG + Macro Breaker) | autres | perte max par trade | refus « lot < lot minimum » |
|---|---|---|---|---|---|---|---|
| v2.22 (origine) | 1,65 | 0 | 1,40 | 0 | 0,25 | 3,01 % | 0 |
| v2.30 | 2,28 | 0,32 | 1,74 | 0 | 0,22 | 1,00 % | 0 |
| v2.40 sans les modèles v6.20 | 2,28 | 0,32 | 1,74 | 0 | 0,22 | 1,00 % | 0 |
| **v2.40** | **2,55** | 0,26 | 1,42 | **0,69** | 0,18 | 1,02 % | 0 |
| v2.40 sans le modèle London PDF | 2,56 | 0 | 1,56 | 0,82 | 0,19 | 1,02 % | 0 |
| option RiskGuard : SL ramené au plafond | 2,57 | 0,21 | 1,85 | 0,36 | 0,15 | 1,02 % | 0 |
| v2.30, petit compte (10 000, lot min 0,1) | 2,03 | 0,33 | 1,44 | 0 | 0,26 | 1,00 % | 282 |
| **v2.40, petit compte** | **2,52** | 0,25 | 1,31 | 0,78 | 0,19 | 1,49 % | **70** |

**Attention, ces chiffres ne mesurent pas la rentabilité.** Les données sont une marche aléatoire synthétique : aucune donnée NQ réelle n'est accessible ici. Seul le testeur MT5 sur l'historique de ton broker peut dire si un modèle gagne.

Ce que le tableau montre :

- **Corrections sans effet sur tes règles.** La v2.40 sans les modèles v6.20 prend exactement les mêmes trades que la v2.30 (411, mêmes gagnants et perdants). Seuls le comptage et l'enregistrement changent.
- **Les modèles v6.20 ajoutent 0,69 trade par jour** : 0,13 Silver Bullet 1er FVG et 0,56 Macro Breaker. Le total passe de 2,28 à 2,55 trades par jour. Avec ta limite de 3 trades par jour et un seul sens à la fois, ils remplacent une partie des SB Momentum (1,74 → 1,42) et du London PDF (0,32 → 0,26). Sur ces données, le total en R est équivalent : 164 R contre 167 R sans eux. La v2.40 trade donc plus souvent, mais ces données ne disent pas si c'est mieux. Compare sur ton historique avec `InpV6EnableSB` / `InpV6EnableMB`, et par modèle dans SQLite (colonne `model`).
- **Le rejet « SL trop large » passe de 56 % à 32 % des signaux.** Les modèles v6.20 ont leurs propres bornes de stop : 6 ATR M5 pour le SB, 12 ATR M1 pour le MB.
- **Petit compte** : la v2.30 refuse 282 setups pour le lot minimum et la v2.40 seulement 70, ce qui fait passer le rythme de 2,03 à 2,52 trades par jour. La perte maximale monte à 1,49 % : c'est la tolérance de 1,5 × le risque.
- **Option « SL ramené au plafond »** : plus de trades SB Momentum, et un meilleur résultat sur ces données. Mais elle place le SL à l'intérieur de la zone du sweep, contrairement à ta règle. Sur ces données, le SB Momentum gagne même +0,5 R par trade : cela montre surtout que le générateur a des tendances exploitables par un modèle momentum. Ces R ne sont pas transposables au marché réel. Teste cette option sur ton historique avant de l'utiliser.

## 7. Limites connues

- **Compilation** : le code est vérifié par traduction en C++ et par les tests ci-dessus, pas par MetaEditor (non disponible ici). Si MetaEditor signale une erreur, envoie-la-moi telle quelle.
- **Redémarrage de MT5** : les ordres déjà envoyés ne sont jamais doublés (identifiant déterministe `SB…` / `MB…`). En revanche, le compteur « 1 trade par fenêtre » de la v6.20 est en mémoire : un redémarrage au milieu d'une fenêtre peut permettre un second trade v6.20 dans cette fenêtre.
- **Ordres en attente** : comme en v2.30, ils comptent dans les 3 trades par jour tant qu'ils vivent. Un ordre Macro Breaker non exécuté occupe une place jusqu'à son expiration (fin de macro + 35 min).
- **Ticks** : le Silver Bullet v6.20 travaille sur les bougies M5 clôturées et le Macro Breaker sur les M1 clôturées, comme dans la v6.20. Les résultats ne dépendent donc pas du mode de ticks, sauf pour l'exécution des ordres.

## 8. Questions pour finaliser

1. Peux-tu m'envoyer le `diagnostic.txt` d'un backtest sur ton broker ? Indique aussi :
   - le symbole ;
   - le capital du testeur ;
   - le lot minimum ;
   - le décalage GMT du serveur ;
   - le mode de ticks.
2. Les macros 15:15 et 15:50 du Macro Breaker sont bloquées par tes règles ICT NAS (macro d'accumulation, flat à 15:50). Faut-il les garder bloquées ?
3. SL : garder le rejet au-delà de 2,5 ATR (ta règle) ou essayer « ramené au plafond » (RiskGuard) sur ton historique ?
4. Valeurs RiskGuard désactivées par défaut (lot max 1,00, délai de 900 s, spread 0,15 ATR) : faut-il en activer certaines ?
5. Faut-il ajouter le modèle LRL Map (LRL + iFVG) comme modèle supplémentaire ?

---

# Historique : v2.30 (fusion avec le moteur OPR + FVG)

### v2.30 - 1. Ce qui change

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

### v2.30 - 2. Le modèle LONDON_OPR_PDF (moteur OPR + FVG)

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

### v2.30 - 3. Paramètres ajoutés

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

### v2.30 - 4. Tests

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

### v2.30 - 5. Divergences et limites connues

**Reprises du rapport OPR + FVG :**

- Entrée sur **breaker / orderblock** (PDF) : non implémentée. Seul le FVG est utilisé (« en priorité »).
- **Cible EQH/EQL M15** prioritaire et **seconde entrée vers -3 STD** : non implémentées.
- **FPFVG de minuit** : le PDF demande « le plus évident » ; l'EA prend le premier FVG M1 ≥ taille minimale. C'est une référence seulement.
- **Méthode CRT 5 h / 9 h du PDF** (DOL, SMT EUR/USD–GBP/USD) : non formalisée. Tes modèles CRT de la v2.22 sont inchangés.

**Propres à la fusion :**

- Le modèle book du moteur ignore les filtres d'ICT NAS : risque du jour, conflit, news. Dans les tests, 58 des 93 trades book (environ 60 %) sont exécutés réellement ; les autres sont surtout bloqués parce qu'un trade SB Momentum occupe déjà la fenêtre de Londres. Les trades exécutés sont, eux, identiques à ceux du book.
- Après un redémarrage de MT5, un ordre London déjà envoyé n'est pas doublé (identifiant déterministe `LP<id>`). Comme en v2.22, la gestion active (BE, partiels) des positions **ouvertes avant le redémarrage** n'est pas reprise. Leur SL et leur TP restent chez le broker.

### v2.30 - 6. Questions pour finaliser

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
