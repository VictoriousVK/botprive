---
name: ict-definitions
description: Définitions ICT versionnées du moteur (swing, FVG, mitigation, sweep, MSS, killzones, macros, premium/discount). À lire avant de toucher au moteur ICT, au golden set ou aux explications de l'Analyste et du Mentor.
---

# Définitions ICT du moteur — version `victor-v0`

**Statut : à valider par Victor.** Ces définitions sont celles du code actuel, porté de l'EA
*ICT Ultimate Pro v6.20* (`hedgefund/strategy/library/ict_core.py`, `ict_clock.py`). Toute
modification crée une nouvelle version (`victor-v1`…) : le numéro de version est enregistré avec
chaque objet détecté (`DefinitionRef`) et avec chaque cas du golden set.

Toutes les heures sont en **heure de New York** (UTC−5, UTC−4 en heure d'été américaine), calculées
depuis l'UTC ; jamais depuis l'heure du serveur du broker.

## Structure

| Concept | Définition | Paramètres |
|---|---|---|
| Swing high | Fractal : le plus haut de la bougie `i` dépasse strictement les `s` bougies précédentes et n'est pas dépassé par les `s` suivantes | `s = 2` (swing_strength) |
| Swing low | Symétrique | `s = 2` |
| Biais de structure (BOS) | Direction de la dernière clôture au-delà du dernier swing opposé, en parcourant l'historique | calculé en H1 pour le biais HTF |
| MSS | Après un sweep : clôture au-delà du dernier swing opposé formé avant l'extrême du sweep, avec une bougie de **déplacement** (corps ≥ 0,8 ATR) dans les 15 bougies | `mss_max_bars = 15`, `disp_body_atr = 0,8`, `mss_min_range_atr = 0,3` |

## Fair Value Gap

| Concept | Définition | Paramètres |
|---|---|---|
| BISI (FVG haussier) | Bougie centrale `m` haussière ; `bas(m−1) − haut(m+1) ≥ taille minimale` | taille ≥ 0,12 ATR (Silver Bullet), 0,15 ATR (Macro Breaker) |
| SIBI (FVG baissier) | Symétrique | idem |
| Consequent encroachment | Milieu du FVG | 50 % |
| Partiellement mitigé | Une mèche ultérieure est entrée dans le FVG sans le traverser | |
| Mitigé | Une mèche ultérieure a traversé tout le FVG (sous le bas d'un BISI, au-dessus du haut d'un SIBI) | |
| BPR | Un FVG opposé plus ancien chevauche le FVG | bonus de score |

## Liquidité

| Niveau | Rang | Source |
|---|---|---|
| PDH / PDL, PWH / PWL, IPDA 20/40/60 jours | 3 | barres D1 |
| Hauts et bas de session (Asie 20:00–00:00, Londres 02:00–05:00, NY AM 07:00–12:00) | 2 | barres M5 |
| Equal highs / equal lows (écart ≤ 0,10 ATR) | 2 | swings M5 |
| Swings H1 | 2 | |
| Swings M5 et M1 | 1 | |

**Sweep confirmé** : la mèche dépasse le niveau d'au moins 0,04 ATR, puis le prix clôture de nouveau
de l'autre côté en 3 bougies au plus ; l'épisode dure 6 bougies au plus ; le niveau doit exister
avant le sweep.

**Premium / discount** : range de référence = plus haut et plus bas IPDA 20 jours. Au-dessus de 55 % :
premium ; sous 45 % : discount ; entre les deux : équilibre.

## Temps

| Fenêtre | Heure de New York |
|---|---|
| Killzone Asie | 20:00–00:00 |
| Killzone Londres | 02:00–05:00 |
| Killzone NY AM | 07:00–10:00 |
| NY Lunch | 12:00–13:30 |
| Killzone NY PM | 13:30–16:00 |
| Silver Bullet | 03:00–04:00, 10:00–11:00, 14:00–15:00 |
| Macros | liste `MACROS` de `ict_clock.py` (ex. 08:50–09:10, 09:50–10:10, 10:50–11:10…) |
| Midnight open | ouverture de la bougie de 00:00 |
| Daily open 18 h | ouverture de la bougie de 18:00 (début de la journée de trading) |

## Setups

- **Silver Bullet (M5)** : dans une fenêtre SB, sweep d'un niveau de liquidité → MSS avec déplacement →
  entrée sur le premier FVG de la jambe ; score par règles (discount, alignement HTF, OTE, macro, true
  open, BPR, jour de la semaine) ; score minimal 3 ; RR minimal 2.
- **Macro Breaker (M1)** : dans une macro, sweep → breaker → entrée au bord du breaker ; score minimal 2.

Le **score est toujours calculé par les règles**, jamais par un modèle.
