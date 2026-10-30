# LRL Map EA — MetaTrader 5

Expert Advisor MQL5 qui applique la stratégie **LRL Map [Herman]** : *Low Resistance Liquidity*
+ iFVG du plus haut timeframe, avec exécution automatique et statistiques auto-mesurées.

| Fichier | Rôle |
|---|---|
| `LRL_Map_EA.mq5` | L'EA : exécution réelle (ordres limites, sizing au risque, fenêtre NY, flat), dessin, tableau, alertes, export CSV |
| `LRL_Engine.mqh` | Le moteur de la stratégie : swings, LRL, HTF reconstruits, FVG/iFVG, zone surveillée, modèle *book* et statistiques. Aucun appel de trading ni de dessin |

## Installation

1. Copier le dossier `LRL_Map` dans `MQL5/Experts/` (Fichier → Ouvrir le dossier des données).
2. Ouvrir `LRL_Map_EA.mq5` dans MetaEditor et compiler (F7). Les deux fichiers doivent rester dans le même dossier.
3. Attacher l'EA à un graphique de l'instrument (NQ, MNQ, ES, US100, US500…) et activer *Algo Trading*.
4. Vérifier dans le journal la ligne `fuseau auto -> serveur GMT+x, serveur - NY = y h`. Elle doit correspondre à votre broker (voir *Heure de New York*).

Le graphique peut être dans n'importe quel timeframe. Le moteur travaille toujours sur `InpBaseTF` (M1 par défaut).

## Ce que fait l'EA

Rien ne se passe tant que la chaîne complète n'est pas réunie :

1. **Swings** : pivots confirmés (`InpPivotLeft` / `InpPivotRight`), les `InpMaxSwings` derniers par côté.
2. **LRL** : chaque paire de swings définit une ligne candidate. Elle est retenue si :
   - au moins `InpMinTouches` swings sont à moins de `InpTouchTolATR × ATR`, espacés d'au moins `InpMinSpacing` bougies ;
   - aucun swing du côté opposé ne la casse ;
   - bougie par bougie, rien ne l'a traversée de plus que la tolérance depuis la première touche.

   La meilleure ligne (plus de touches, puis la plus récente) est décalée sur la touche la plus extrême. Elle est retirée quand elle est balayée (mèche ou clôture) ou après `InpExpireBars` bougies sans nouvelle touche.
3. **Biais** : LRL sous le prix → short ; LRL au-dessus → long. Si les deux existent, la ligne qui a le plus de touches l'emporte ; à égalité, la plus proche.
4. **Timeframes supérieurs** : jusqu'à 3 HTF (`InpHTF1..3`, en minutes), reconstruits à partir des bougies de base. Une bougie HTF se clôture sur la bougie de base dont la clôture coïncide avec la sienne. Il n'y a ni `iHigh` HTF ni *lookahead*.
5. **iFVG** : un FVG est détecté sur les bougies de son niveau. Il est inversé quand une bougie *de ce niveau* clôture au-delà du gap, et invalidé quand une clôture de ce niveau revient de l'autre côté.
6. **Zone surveillée** : parmi les iFVG vivants dans le sens du biais, seul celui du **plus haut timeframe** est surveillé (à égalité, l'inversion la plus récente). Les zones de timeframes inférieurs sont ignorées tant qu'il vit.
7. **Trade** : au **premier retest** (CE ou bord). Le stop est placé au-delà du swing de la jambe (entre le gap et l'inversion) + `InpStopBufferTicks`, ou au-delà de la zone. La cible est à `InpRR` × R.
   - Filtres : stop minimum `InpMinStop` (en unités de prix, ex. 15 points NQ), stop maximum `InpMaxStopATR` × ATR, et LRL au-delà de la cible.
   - Chaque zone ne sert qu'une fois, tradée ou rejetée.
8. **Modèle book** : chaque trade imprimé est résolu de façon conservatrice. Sur la bougie d'entrée, seul le stop est vérifié ; si une bougie touche stop et cible, c'est une perte. Les trades sont clôturés dans la fenêtre flat (15:55–16:00 NY). Les statistiques sont séparées entre trades dans et hors de la fenêtre.

### Exécution réelle

- À la clôture de chaque bougie de base, si un setup est **armé** (zone surveillée + filtres OK), l'EA place un **ordre limite** au niveau d'entrée, avec SL et TP.
- L'ordre est supprimé dès que le setup disparaît : biais perdu, zone de plus haut TF apparue, zone invalidée, filtre, sortie de fenêtre, etc.
- Les niveaux sont arrondis au tick dans le sens qui garde le déclenchement réel identique au modèle book.
- Si le prix a déjà dépassé le niveau, l'entrée se fait au marché, dans la limite de `InpMaxChaseR` × R.
- Mode alternatif : `InpOrderMode = marché au toucher`.
- Volume au risque (`InpRiskPct` % du solde, via `OrderCalcProfit`) ou en lots fixes. Il est plafonné par `InpMaxLots` et par la marge libre.
- Protections : positions simultanées max, trades par jour, perte journalière max, spread max, sens autorisés, break-even optionnel.
- Fenêtre flat : positions clôturées et ordres supprimés.
- Au redémarrage, l'EA reprend son ordre en attente et ne retrade jamais une zone déjà exécutée.

## Heure de New York

`InpTzMode` :

- **Auto** (défaut) : en live, le décalage serveur/NY est mesuré au démarrage. Cela suppose un serveur aligné sur le DST US, ce qui est le cas de la plupart des brokers GMT+2/+3. Dans le testeur, on utilise `InpServerMinusNY` (7 h par défaut).
- **Serveur = NY + fixe** : `InpServerMinusNY` heures (7 pour la majorité des brokers).
- **Serveur = GMT + fixe** : `InpServerGMT` heures. Le DST US est alors calculé (2e dimanche de mars → 1er dimanche de novembre). À utiliser si votre serveur est en GMT fixe.

## Écarts avec l'indicateur TradingView d'origine

- MT5 n'a pas de bougies de 30 secondes : la base par défaut est **M1**, avec des HTF **2 / 3 / 5 min** (au lieu d'un graphique 30 s avec des HTF 1 / 2 / 3 min). Tout est paramétrable. Les HTF doivent être des multiples de la base et diviser 24 h.
- Les HTF sont alignés sur minuit serveur. C'est identique à TradingView pour toutes les périodes qui divisent 60 min.
- Au démarrage, l'EA rejoue `InpWarmupBars` bougies d'historique : les lignes, les zones et les statistiques sont disponibles immédiatement.
- Le code source de l'original n'est pas public. Ce moteur est une implémentation à partir de la description publiée, pas une copie.

## Tableau et alertes

Le tableau (thème sombre/clair, coin haut droit/gauche) affiche :

- **état live** : LRL basse/haute, biais, zone surveillée, setup (armé avec entrée/stop/cible, ou raison du blocage), fenêtre NY ;
- **statistiques book** : trades, W/L, win rate, R net et moyen, dans/hors fenêtre, rejets par filtre ;
- **compte** : exécution, positions/ordres, P&L du jour, dernier statut.

Alertes à la clôture de bougie (popup / push / son) : LRL confirmée, setup armé, entrée short, entrée long, trade clôturé.

`InpExportCsv = true` exporte tous les trades book dans `MQL5/Files/LRL_Map_<symbole>_<tf>.csv` quand l'EA est retiré.

## Backtest dans le testeur de stratégie

- Modèle : « Chaque tick basé sur des ticks réels » (ou « Chaque tick »), sur le symbole voulu.
- Réglez `InpServerMinusNY` selon votre broker (le mode Auto n'est pas disponible dans le testeur).
- Pour tester la règle « 30 premières minutes » : fenêtre `09:30`–`10:00` et `InpTradeOnlyInWin = false`. Le tableau montre alors côte à côte les statistiques dans et hors fenêtre.
- Le rapport du testeur donne les résultats **réels** (spread, fills). Le tableau donne le modèle **book** : entrée au niveau, résolution conservatrice. Ce sont deux mesures différentes.

## Tests (harnais C++)

MetaEditor ne tourne pas sous Linux. Le dossier `tests/` convertit donc le code MQL5 en C++ (`tests/mq2cpp.py`) et le compile avec g++ contre une API MT5 simulée (`tests/shim/`).

```bash
tests/run_tests.sh
```

- **Moteur** (84 vérifications) :
  - heure NY et DST ; agrégation HTF, y compris les bougies manquantes ;
  - LRL exacte sur un scénario construit ; chaîne complète LRL → iFVG 2m → retest CE → +1R ;
  - règle conservatrice stop/cible ; stop sur la bougie d'entrée ; inversion jugée uniquement sur la clôture HTF ;
  - filtres stop min et LRL au-delà de la cible ; entrée au bord / stop à la zone ; fenêtre et flat ;
  - déterminisme ; invariants sur 3 × 300 000 bougies aléatoires (environ 4 µs par bougie).
- **EA complet** (4 variantes, 120 000 bougies live chacune, tick par tick) :
  - warmup, ordres limites, SL/TP, flat, fenêtre, sizing au risque ;
  - dessin borné, tableau, CSV, break-even, limite journalière, redémarrage de l'EA ;
  - avec positions multiples, **1311 trades réels sur 1311 = trades book**, même entrée, même issue.

Le harnais vérifie la syntaxe, les types et la logique, et un *lint* contrôle les règles propres à MQL5. Il ne remplace pas une compilation dans MetaEditor : si MetaEditor signale une erreur, envoyez-la pour correction.

## Avertissement

Les statistiques *book* ne sont ni un backtest ni une promesse : fills, slippage et commissions ne sont pas modélisés. Sur les données **aléatoires** des tests, le résultat est négatif, ce qui est normal puisqu'une marche aléatoire n'a pas d'avantage. Seules vos données réelles diront si la règle fonctionne sur votre instrument.

Testez en **compte démo** et dans le testeur avant tout usage réel. La tolérance, l'espacement et les pivots décident des lignes qui qualifient : ajustez-les par instrument et par timeframe.
