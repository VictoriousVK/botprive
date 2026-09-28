---
name: mql5-conventions
description: Conventions MQL5 des EA de Victor et de l'usine EA (numéro magique, gestion d'erreurs, lots, sessions, spread, WebRequest). À lire avant d'écrire, de revoir ou de générer du code MQL5.
---

# Conventions MQL5

1. **Numéro magique** : `input long InpMagic = 770077;` ; tout ordre, toute position lue et toute
   fermeture filtrent sur ce numéro. Jamais de gestion des positions d'un autre EA.
2. **Aucun appel réseau** dans un EA de trading, sauf l'EA `JournalSync` (lecture seule, `WebRequest`
   vers l'URL autorisée dans MT5). Aucune DLL.
3. **Lots** : normaliser avec `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_STEP`, `SYMBOL_VOLUME_MAX` ; calculer la
   taille depuis le risque en devise et `SYMBOL_TRADE_TICK_VALUE` / `SYMBOL_TRADE_TICK_SIZE` ; refuser un
   lot hors bornes plutôt que l'arrondir vers le haut.
4. **Stops** : respecter `SYMBOL_TRADE_STOPS_LEVEL` et `SYMBOL_TRADE_FREEZE_LEVEL` ; SL obligatoire à
   l'ouverture ; pas de martingale, pas de grille sans stop.
5. **Erreurs** : vérifier le retour de chaque `OrderSend` / `CTrade` (`ResultRetcode`) ; gérer
   `TRADE_RETCODE_REQUOTE`, `PRICE_OFF`, `NO_MONEY`, `MARKET_CLOSED` ; journaliser avec `PrintFormat`.
6. **Sessions et temps** : calculer l'heure de New York depuis `TimeGMT()` (règles de l'heure d'été
   américaine) ; jamais depuis `TimeCurrent()` seul (heure du serveur).
7. **Spread** : filtre `max_spread` en fraction de l'ATR ; pas d'entrée pendant le rollover de 17:00 NY.
8. **Nouvelles barres** : décisions sur la clôture (`iTime` a changé) ; pas de décision intrabar.
9. **Paramètres** : tous en `input`, documentés, avec des valeurs par défaut prudentes.
10. **Revue** : la checklist déterministe de l'usine EA (`hedgefund/saas/ea_factory.py`) doit passer
    avant tout backtest.
