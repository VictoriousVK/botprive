# Le temps chez ICT : sessions, killzones, Silver Bullet, macros, opens

ICT insiste : **le temps compte autant que le prix**. Les setups sont recherchés à des heures
précises, toujours exprimées en **heure de New York**.

## Conversion heure de New York → heure GMT (Dakar, Abidjan)

New York change d'heure, Dakar non :

- **Heure d'été de New York** (du 2e dimanche de mars au 1er dimanche de novembre) :
  GMT = heure NY **+ 4 h**.
- **Heure d'hiver de New York** (du 1er dimanche de novembre au 2e dimanche de mars) :
  GMT = heure NY **+ 5 h**.
- Pays en GMT+1 (Cameroun, RDC Kinshasa, Gabon…) : ajouter encore 1 h.

| Repère (heure de New York) | GMT, été NY | GMT, hiver NY |
|---|---|---|
| Asian killzone 20:00–00:00 | 00:00–04:00 | 01:00–05:00 |
| Midnight open 00:00 | 04:00 | 05:00 |
| London killzone 02:00–05:00 | 06:00–09:00 | 07:00–10:00 |
| Silver Bullet Londres 03:00–04:00 | 07:00–08:00 | 08:00–09:00 |
| NY AM killzone 07:00–10:00 | 11:00–14:00 | 12:00–15:00 |
| News US 08:30 (CPI, NFP…) | 12:30 | 13:30 |
| Ouverture actions US 09:30 | 13:30 | 14:30 |
| Silver Bullet NY AM 10:00–11:00 | 14:00–15:00 | 15:00–16:00 |
| London close 10:00–12:00 | 14:00–16:00 | 15:00–17:00 |
| NY PM 13:30–16:00 | 17:30–20:00 | 18:30–21:00 |
| Silver Bullet NY PM 14:00–15:00 | 18:00–19:00 | 19:00–20:00 |
| Annonce FOMC 14:00 | 18:00 | 19:00 |
| CBDR 14:00–20:00 | 18:00–00:00 | 19:00–01:00 |

## Killzones

Fenêtres où la volatilité et les setups ICT sont les plus fréquents :

- **Asian killzone** 20:00–00:00 NY : construit souvent le **range asiatique**, dont le
  sommet et le creux deviennent de la liquidité pour Londres.
- **London open killzone** 02:00–05:00 NY : fait souvent le sommet ou le creux de la journée
  sur le forex.
- **New York AM killzone** 07:00–10:00 NY pour le forex ; pour les indices (Nasdaq, S&P), ICT
  utilise plutôt **08:30–11:00**.
- **London close killzone** 10:00–12:00 NY : prises de bénéfices, retracements.
- **New York PM session** 13:30–16:00 NY (indices).

Les bornes exactes varient un peu selon les vidéos d'ICT ; l'important est le principe :
trader dans les fenêtres actives, éviter le milieu de nuit et l'heure du déjeuner NY
(environ 12:00–13:30), souvent sans direction.

## Silver Bullet

Trois fenêtres d'**une heure** : **03:00–04:00**, **10:00–11:00** et **14:00–15:00** heure de
New York. Pendant la fenêtre, on cherche un **FVG** formé par un déplacement vers le **draw on
liquidity**, souvent après une prise de liquidité. Voir la fiche modèles d'entrée.

## Macros

Courtes fenêtres (environ 20 minutes) où ICT observe que l'algorithme va chercher de la
liquidité ou combler un FVG. Liste couramment citée (heure NY) : 02:33–03:00, 04:03–04:30,
08:50–09:10, 09:50–10:10, 10:50–11:10, 11:50–12:10, 13:10–13:40, 15:15–15:45. Les robots de la
plateforme (Macro Breaker) utilisent une liste plus large de fenêtres de 20 minutes (par
exemple 08:20, 09:20, 10:20, 13:20, 15:15, 15:50). Les macros sont une notion récente et
moins standardisée que les killzones.

## Prix d'ouverture de référence

- **Midnight open** (00:00 NY) : ICT l'utilise comme ouverture « vraie » de la journée ; au-
  dessus = zone premium du jour, au-dessous = discount (lecture intrajournalière).
- **08:30** (news) et **09:30** (ouverture des actions US) pour les indices.
- **18:00 NY** : début de la journée de trading des contrats à terme (CME Globex).
- Les robots de la plateforme suivent aussi l'ouverture de 07:30 NY.

## CBDR et range asiatique

- **CBDR** (Central Bank Dealers Range) : 14:00–20:00 NY. Un CBDR étroit (ICT parlait de moins
  de 40 pips sur le forex) annonce souvent une expansion le lendemain ; ses écarts-types
  servent de projections.
- **Asian range** : 20:00–00:00 NY, utilisé de la même façon.

## Erreurs fréquentes

- Oublier le changement d'heure de New York (deux semaines par an, l'Europe et les USA ne
  changent pas le même jour).
- Lire les heures du graphique MT5 comme des heures NY : le serveur du broker est souvent en
  GMT+2/GMT+3. Il faut convertir.
