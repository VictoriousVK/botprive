# Appliquer ICT à l'or (XAUUSD) et au Nasdaq (NAS100 / NQ)

## Or (XAUUSD)

- Cotation en dollars par once. Sur la plupart des brokers MT5, **1 lot = 100 onces** : un
  mouvement de 1 $ vaut 100 $ par lot (à vérifier chez son broker).
- Très sensible au **dollar** (souvent inverse au DXY), aux **taux US** et aux news US :
  CPI, NFP, FOMC, discours de la Fed. Les mouvements autour de 08:30 et 14:00 NY peuvent être
  violents ; écarts (spreads) élargis à l'ouverture de 18:00 NY et autour des news.
- Sessions les plus utiles : **Londres** (souvent le premier grand mouvement) et **NY AM**.
  L'Asie construit en général un range dont les extrêmes servent de liquidité.
- Les niveaux ronds (par exemple 2 300, 2 350 $) attirent souvent des ordres.

## Nasdaq (NAS100 en CFD, NQ en contrats à terme)

- Indice des grandes valeurs technologiques US. **NQ** (CME) est le contrat que suit ICT ; le
  CFD NAS100 de MT5 le réplique avec un prix légèrement différent.
- Heures clés (NY) : **08:30** news, **09:30** ouverture des actions (souvent très volatile
  dans les premières minutes), killzone NY AM 08:30–11:00, Silver Bullet 10:00–11:00, session
  PM 13:30–16:00, Silver Bullet 14:00–15:00.
- SMT naturelle avec **ES** (S&P 500).
- Les opening gaps (**NDOG**, **NWOG**) et l'ouverture de 09:30 servent de niveaux de
  référence intrajournaliers.

## Différences CFD MT5 / contrats à terme

- Les heures du graphique MT5 sont celles du **serveur du broker** (souvent GMT+2 ou GMT+3),
  pas celles de New York. Convertir avant d'appliquer les killzones.
- Les gaps et volumes peuvent différer entre CFD et futures ; un FVG visible sur NQ peut être
  un peu décalé sur NAS100.

## Erreurs fréquentes

- Trader l'or ou le Nasdaq dans les minutes qui précèdent une news majeure sans plan.
- Utiliser la même taille de stop sur l'or et sur le Nasdaq : leur volatilité diffère, il faut
  recalculer la taille de position à chaque trade.
