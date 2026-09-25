# Console Alpha Edge (plateforme de trading MetaTrader 5) : guide complet

> **Nouveau (v0.3.0).** La même adresse sert désormais le **site Liberté Financière** (accueil,
> robots, copytrading, académie vidéo, offres, paiement Wave, espace membre) à la racine `/`,
> et la **console de trading** décrite ici à **`/console`**. Guide du site :
> [docs/SITE.md](SITE.md).

La console pilote vos bots de trading sur MT5, depuis un navigateur (ordinateur ou
téléphone). Elle sert à :

- **choisir l'actif** : or, argent, Nasdaq, S&P 500, DAX, Bitcoin, Ethereum, forex,
  pétrole… (la liste vient directement de votre broker) ;
- **choisir une stratégie** : suivi de tendance, retour à la moyenne, paire (valeur
  relative, par exemple or/argent ou Nasdaq/S&P 500), ou **vos deux EA ICT** portés sur la
  plateforme : *ICT Ultimate Pro v6* (croisement EMA + Silver Bullet) et *ICT Ultimate Pro
  v6.20* (Silver Bullet + Macro Breaker), voir §5 bis ;
- **backtester** un bot sur l'historique MT5 avant de le lancer ;
- **démarrer ou arrêter** chaque bot, et tout arrêter d'un clic (**arrêt d'urgence**) ;
- **suivre les résultats** dans un tableau de bord : valeur du portefeuille, drawdown,
  résultat par bot, positions, exécutions, alertes, journal d'audit.

> **Important.** Aucune stratégie n'est validée sur données réelles. Commencez **toujours
> par un compte démo**, pendant plusieurs semaines. Le trading sur compte réel est
> **verrouillé par défaut** et demande trois actions volontaires (§8).

---

## 1. Comment ça marche

```
Navigateur (PC / téléphone)
      │  HTTPS (Cloudflare Tunnel ou Caddy)
      ▼
Plateforme web (FastAPI) ── connexion sécurisée, 2FA, journal d'audit
      │
Moteur de bots ── pour chaque bot, à chaque nouvelle bougie :
      │             stratégie → modèle de décision (Jev) → règles fixes → moteur de risque
      ▼
Connecteur MT5 (paquet officiel MetaTrader5) ── ordres, positions, historique des prix
      │
Terminal MetaTrader 5 (sur le même PC Windows) ── votre broker
```

- Le **moteur de risque** s'applique à tous les bots ensemble : perte maximale de 15 % →
  arrêt d'urgence ; perte de 3 % dans la journée → plus de nouvelle position jusqu'au
  lendemain ; position maximale de 25 % du capital par actif ; limite par famille d'actifs ;
  etc. Aucun modèle ne peut passer outre.
- La plateforme ne touche **qu'à ses propres positions**, marquées par un numéro magique
  (770077). Vos autres robots (par exemple ICT Pure Master) et vos trades manuels sont
  ignorés.
- Tout est enregistré dans un journal infalsifiable (`var/platform_<mode>.db`).

## 2. Les trois modes

| Mode | Prix | Ordres | Usage |
|---|---|---|---|
| **Simulation** | simulés | simulés | Découvrir l'interface sans MT5 (Linux, Mac, aperçu) |
| **Papier** | réels (MT5) | simulés, rien n'est envoyé | Tester les bots en conditions réelles sans risque |
| **MT5** | réels (MT5) | **envoyés au compte connecté** | Compte **démo** d'abord ; compte réel seulement après déverrouillage (§8) |

Chaque mode a son propre historique : les résultats simulés ne se mélangent jamais avec
ceux du broker.

## 3. Prérequis

- Un **PC Windows** ou un **VPS Windows** (beaucoup de brokers en offrent un gratuitement).
  Le paquet MT5 pour Python ne fonctionne que sous Windows.
- **MetaTrader 5** installé et connecté à votre compte (démo pour commencer).
- **Python 3.11 ou plus récent** (python.org ; cochez **« Add python.exe to PATH »**).

## 4. Installation pas à pas

1. Copiez le dossier du projet sur le PC, par exemple dans `C:\hedgefund`.
2. Ouvrez **PowerShell** dans ce dossier (Shift + clic droit → « Ouvrir PowerShell ici »), puis :
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # une seule fois, répondez O
   .\deploy\windows\install.ps1
   ```
3. Créez votre compte administrateur. Il n'y a **aucun compte par défaut** : c'est vous
   qui choisissez le nom et le mot de passe (12 caractères minimum).
   ```powershell
   .\.venv\Scripts\python.exe -m hedgefund.web create-user --username vic
   ```
4. Ouvrez `.env.ps1` (créé par l'installation) et vérifiez les réglages. Pour un premier
   essai **en local**, mettez `$env:HF_COOKIE_SECURE = "0"`.
5. Dans MT5 : connectez-vous à votre compte **démo** et activez le bouton **« Algo Trading »**
   (barre d'outils, il doit être vert).
6. Démarrez la plateforme :
   ```powershell
   .\deploy\windows\start.ps1
   ```
7. Ouvrez **http://127.0.0.1:8000/console** dans le navigateur du PC et connectez-vous
   (le site Liberté Financière est à **http://127.0.0.1:8000**, l'administration du site à
   **http://127.0.0.1:8000/admin/** une fois connecté à la console).

### Mettre à jour la plateforme (nouvelle version reçue en zip)

1. Arrêtez la plateforme : **Ctrl+C** dans la fenêtre PowerShell de `start.ps1` (deux fois
   si elle redémarre toute seule), puis fermez cette fenêtre.
2. Décompressez le zip **dans le même dossier parent** que l'ancienne version et acceptez
   « **Remplacer les fichiers** ». Vos données sont conservées : le zip ne contient ni
   `.venv`, ni `var` (comptes, bots, historique), ni `.env.ps1` (vos réglages).
   **Ne décompressez pas dans un nouveau dossier** : vous repartiriez de zéro.
3. Dans PowerShell, dans le dossier du projet : `.\deploy\windows\install.ps1`, puis
   `.\deploy\windows\start.ps1`.
4. Dans le navigateur : **Ctrl+F5**. L'onglet **Bots → Stratégies disponibles** affiche le
   numéro de version (par exemple « Version 0.2.0 · 5 stratégies »).

## 5. Utilisation

1. **Réglages → Mode d'exécution** : commencez en **Papier** (prix MT5, aucun ordre).
2. **Réglages → Capital alloué** : la somme que les bots peuvent utiliser pour calculer
   leurs tailles de position (par défaut, l'équité du compte).
3. **Bots → + Nouveau bot** :
   - choisissez une **stratégie** ;
   - choisissez l'**actif** : filtrez par famille (Métaux, Indices, Crypto, Forex…) ou
     tapez « or », « nasdaq », « btc »… La fiche affiche le prix, le spread et la **taille
     minimale d'un ordre** chez votre broker ;
   - choisissez l'unité de temps (proposée selon la stratégie : 1 min pour ICT Pro v6.20,
     5 min à 1 h pour ICT v6, 15 min à 1 jour pour les autres), le sens (achat et vente,
     achat seul, vente seule), le risque par trade (0,05 % à 1,5 %) et la position maximale ;
   - **Paramètres avancés** : les réglages de la stratégie (pour les EA ICT : fenêtres,
     macros, scores, filtres, break-even, clôture partielle, stop suiveur, time stop) ;
   - cliquez sur **Backtester** pour voir le résultat sur l'historique MT5 (coûts inclus,
     swaps non inclus) ;
   - puis **Enregistrer**, et **Démarrer**.
4. Le bot décide **à chaque clôture de bougie**. Son message indique la dernière décision
   (par exemple « aucun signal », « enter », ou la raison d'un refus).
5. Après quelques semaines en **Papier**, passez en mode **MT5** avec un **compte démo** :
   les ordres partent alors vraiment vers le broker (démo).

**Arrêt d'urgence** (bouton rouge en haut) : ferme toutes les positions de la plateforme
et bloque tout nouvel ordre. Le réarmement demande votre mot de passe (et la 2FA si elle
est activée). Vous pouvez aussi créer un fichier `var\KILL_SWITCH`, ce qui fonctionne
même si l'interface ne répond plus.

## 5 bis. Vos EA ICT sur la plateforme

Les deux Expert Advisors MQL5 ont été réécrits en Python, en reprenant leurs algorithmes et
leurs valeurs par défaut. Chaque bot passe ensuite par les mêmes garde-fous que les autres :
avis de Jev, moteur de risque, arrêt d'urgence, journal.

| Stratégie dans la plateforme | EA d'origine | Unité de temps | Ce qu'elle fait |
|---|---|---|---|
| **ICT Ultimate Pro v6.20 (Silver Bullet + Macro Breaker)** | `ICT_Ultimate_Pro_AllInOne.mq5` v6.20 | 1 minute (+ contexte M5, H1, D1) | Silver Bullet M5 dans les fenêtres 03-04, 10-11, 14-15 heure de New York (sweep → MSS avec displacement → 1ère FVG) ; Macro Breaker M1 dans les macros ICT (stop hunt → breaker confirmé → retest) ; passe stricte puis relâchée ; score ; objectif sur le pool de liquidité opposé (RR ≥ 2) |
| **ICT Ultimate Pro v6 (croisement EMA + Silver Bullet)** | `ICT_Ultimate_Pro_v6.mq5` + `ICT_RiskGuard.mqh` | 5 min, 15 min ou 1 h | Croisement EMA 7/21 filtré par la EMA 50 ; Silver Bullet v6 prioritaire dans les fenêtres (heure serveur 02-05, 09-12, 13-16, 18-21) ; filtres de phase AMD, de volatilité et de spread |

**Repris à l'identique** : carte de liquidité (PDH/PDL, PWH/PWL, IPDA 20/40/60, sessions
Asie/Londres/NY, swings H1 et M5, equal highs/lows, swings M1), niveaux de référence (true
open minuit et 07:30, opening ranges, TBR, NDOG/NWOG, ADR), biais H1 par cassure de
structure, sweeps, MSS, FVG (mitigation, BPR, OTE), breakers et Unicorn, scores, passe
relâchée, arbitrage SB/MB, horloge de New York **avec les heures d'été américaine et
européenne**, plafonds de trades par jour et par fenêtre, vendredi après 12 h NY, spread
maximal en fraction de l'ATR, filtre ADR, break-even, **une** clôture partielle, stop
suiveur ATR / swing, time stop, fermeture programmée.

**Adapté à la plateforme** (à connaître) :

- **Stops et objectifs virtuels.** Aucun SL/TP n'est posé chez le broker. La plateforme les
  surveille à chaque clôture de bougie et **toutes les 15 secondes sur le prix live**, puis
  ferme au marché. Dans un marché rapide, la sortie peut se faire un peu au-delà du stop.
  Si la plateforme est arrêtée, les positions ne sont plus surveillées : gardez-la en marche
  24 h/24 (§7) ou arrêtez les bots avant de l'éteindre.
- **Entrées limites.** Quand l'EA posait un ordre limite (bord de la FVG ou du breaker), la
  plateforme arme une entrée en attente, prise au marché dès qu'une bougie touche le niveau.
  Elle est annulée à l'expiration, si une clôture traverse la zone, ou si l'objectif est
  atteint avant.
- **Taille de position.** C'est la plateforme qui calcule la taille : risque % du capital ÷
  distance du stop, **plafonnée par la position maximale du bot (25 % du capital au plus)**.
  Avec les stops très serrés de l'or en M1/M5, ce plafond s'applique presque toujours : le
  risque réel par trade est alors **nettement plus faible** que dans l'EA, qui pouvait
  utiliser un fort effet de levier. C'est volontaire.
- **Une position par bot**, et **pas d'ordre contraire entre bots** sur le même actif
  (anti-couverture, comme `AllowHedging = false`).
- **Jev et le moteur de risque ont le dernier mot.** Un setup valide peut être refusé
  (message « confidence … < required 0.62 », « regime high_vol… ») si la volatilité est
  anormale ou si les données manquent. La raison s'affiche sur le bot et dans le Journal.
- **Non repris** : filtre d'annonces économiques (le calendrier MQL5 n'est pas accessible
  depuis Python : évitez de laisser tourner le bot pendant le NFP/CPI/FOMC, ou arrêtez-le),
  apprentissage adaptatif et modèle ONNX, mode « order block après FVG », plafond de perte
  hebdomadaire (la perte journalière de 3 % et l'arrêt sur drawdown de la plateforme
  s'appliquent), confirmation UT Bot (désactivée par défaut dans l'EA).

**Mise en route conseillée** : un bot *ICT Pro v6.20* sur XAUUSD en mode **Papier** pendant
au moins 2 semaines, en comparant ses setups à ceux de l'EA sur le même compte démo ; puis
mode **MT5 sur compte démo**. Le backtest de la plateforme porte sur 5 jours de M1
(ICT Pro) ou environ 4 000 bougies (ICT v6) : c'est un contrôle du fonctionnement, pas une
preuve de rentabilité. Les positions ouvertes par vos EA (autres numéros magiques) ne sont
jamais touchées par la plateforme.

## 6. Accéder à la plateforme depuis votre téléphone (mise en ligne)

La plateforme écoute seulement sur `127.0.0.1`. **N'ouvrez jamais le port 8000 sur
Internet.** Deux solutions sûres existent.

### Option A (recommandée) : Cloudflare Tunnel

Pas de port à ouvrir, HTTPS automatique, et possibilité d'ajouter une seconde barrière
d'identification (Cloudflare Access).

1. Créez un compte Cloudflare gratuit et ajoutez-y votre nom de domaine.
2. Installez `cloudflared` sur le PC/VPS, puis :
   ```powershell
   cloudflared tunnel login
   cloudflared tunnel create hedgefund
   cloudflared tunnel route dns hedgefund trading.mondomaine.com
   ```
3. Créez `C:\Users\<vous>\.cloudflared\config.yml` :
   ```yaml
   tunnel: hedgefund
   credentials-file: C:\Users\<vous>\.cloudflared\<id-du-tunnel>.json
   ingress:
     - hostname: trading.mondomaine.com
       service: http://127.0.0.1:8000
     - service: http_status:404
   ```
4. Installez le tunnel comme service Windows : `cloudflared service install`.
5. Dans `.env.ps1`, réglez :
   `$env:HF_COOKIE_SECURE = "1"`, `$env:HF_PUBLIC_HOST = "trading.mondomaine.com"`,
   `$env:HF_TRUST_PROXY = "1"`.
6. (Recommandé) Dans Cloudflare Zero Trust → Access, protégez `trading.mondomaine.com`
   par une règle « e-mail = le vôtre ».

### Option B : Caddy (reverse proxy HTTPS)

Il faut un domaine pointant vers l'IP du VPS, avec les ports 80 et 443 ouverts. Adaptez
`deploy/Caddyfile.example`, puis lancez `caddy run --config deploy\Caddyfile`. Réglez ensuite
`.env.ps1` comme à l'étape 5 de l'option A.

## 7. Fonctionnement 24 h/24 sur un VPS

- `.\deploy\windows\register-task.ps1` : la plateforme démarre automatiquement à chaque
  ouverture de session.
- Configurez MT5 pour qu'il démarre avec Windows (raccourci dans le dossier Démarrage).
- Sur un VPS, **fermez la fenêtre Bureau à distance au lieu de vous déconnecter**. Sinon la
  session s'arrête et MT5 avec elle.
- `start.ps1` relance la plateforme automatiquement si elle s'arrête. Les bots actifs
  reprennent tout seuls, et l'état est reconstruit depuis le journal.

## 8. Trading sur compte réel (à ne faire qu'après validation en démo)

Trois verrous doivent tous être levés :

1. Sur le serveur, dans `.env.ps1` : `$env:HF_ALLOW_REAL_TRADING = "1"`, puis redémarrez.
2. Dans **Réglages → Trading sur compte réel** : tapez `JE COMPRENDS LE RISQUE`, votre mot
   de passe et le code 2FA.
3. Au démarrage de chaque bot, confirmez l'avertissement « argent réel ».

Tant que ces trois verrous ne sont pas levés, la plateforme **refuse d'envoyer le moindre
ordre** sur un compte réel, même en mode MT5.

## 9. Sécurité : liste de contrôle

- [ ] Mot de passe long et unique (12 caractères minimum ; 20 ou plus recommandé).
- [ ] **2FA activée** (Réglages → Sécurité) avec Google Authenticator, Aegis ou 1Password.
- [ ] Plateforme exposée **uniquement** via Cloudflare Tunnel ou Caddy (HTTPS), jamais en
      ouvrant le port 8000.
- [ ] `HF_COOKIE_SECURE = "1"` dès que l'accès se fait par Internet.
- [ ] `.env.ps1` et le dossier `var\` ne sont ni partagés ni versionnés (ils contiennent vos
      réglages et votre historique).
- [ ] Sauvegarde régulière du dossier `var\`.
- [ ] Compte Windows du VPS protégé par un mot de passe fort. Bureau à distance limité
      (port changé ou VPN).

Ce que la plateforme fait déjà :

- mots de passe hachés avec scrypt ;
- sessions aléatoires dont seul le condensé est stocké ;
- cookies HttpOnly/SameSite=Strict/Secure ;
- jeton anti-CSRF et contrôle de l'origine des requêtes ;
- blocage après 5 échecs de connexion en 15 minutes ;
- en-têtes de sécurité stricts (CSP, anti-iframe) ;
- mot de passe redemandé pour toute action sensible ;
- aucune documentation d'API exposée ;
- journal d'audit infalsifiable.

## 10. Limites, à connaître absolument

- **Aucune stratégie n'a d'avantage démontré.** Les backtests sur simulation ne prouvent
  rien. Même un bon backtest sur l'historique MT5 peut échouer ensuite.
- **Swaps non modélisés** dans le résultat interne : tenir une position plusieurs jours
  coûte des frais de financement. L'**équité MT5** affichée sur le tableau de bord (courbe
  orange en mode MT5) est la référence.
- **Taille minimale des ordres** : avec un petit capital, 0,01 lot d'or représente environ
  2 400 USD d'exposition. Certains ordres calculés par le moteur de risque peuvent être
  trop petits et sont alors refusés (c'est affiché).
- **Écarts du week-end et spreads élargis** hors séance : le stop peut être dépassé.
- **Stratégies ICT** : stops virtuels, taille plafonnée et filtre d'annonces non repris
  (§5 bis).
- **Heure du serveur** : la plateforme détecte le décalage horaire du broker quand le
  marché est ouvert. Réglez `MT5_SERVER_UTC_OFFSET_HOURS` pour les périodes de fermeture.
- **Le connecteur MT5 est testé contre un simulateur de terminal, pas contre votre broker.**
  D'où l'obligation de passer par un compte démo : vérifiez que les ordres, les lots et les
  positions affichés correspondent à ce que montre MT5.

## 11. Dépannage

| Symptôme | Solution |
|---|---|
| `No module named 'yaml'` / `'fastapi'` | Environnement non activé : `.\.venv\Scripts\Activate.ps1`, puis relancez `install.ps1` |
| « MT5 déconnecté » | MT5 est-il ouvert et connecté ? Même utilisateur Windows ? Renseignez `MT5_PATH` si besoin |
| « Activez le bouton Algo Trading » | Bouton « Algo Trading » de MT5 à activer (vert) |
| « compte réel verrouillé » | Normal : utilisez un compte démo, ou voir §8 |
| « Marché fermé » sur un bot | Week-end ou hors séance : le bot reprendra à l'ouverture |
| « Historique insuffisant » | Augmentez « Nombre max. de barres dans le graphique » dans MT5 (Outils → Options → Graphiques), ou choisissez une unité de temps plus longue |
| « trop de tentatives » à la connexion | Attendez 15 minutes |
| Mot de passe oublié | Sur le PC : `.\.venv\Scripts\python.exe -m hedgefund.web reset-password --username vic` |
| Un membre du site a oublié son mot de passe | `.\.venv\Scripts\python.exe -m hedgefund.web member-password --email membre@exemple.com` |
| J'arrive sur le site au lieu de la console | La console est maintenant à `/console` (le site est à `/`) |
| Je ne vois pas mes stratégies ICT | Vous utilisez encore l'ancienne version : suivez « Mettre à jour la plateforme » (§4). Elles apparaissent dans **Bots → Stratégies disponibles** et dans la liste « Stratégie » du formulaire. Elles ne s'affichent **pas dans MT5** : le calcul se fait dans la plateforme, MT5 ne voit que les ordres (commentaire `hf…`) |
| « spread … > 0.15 ATR M5 » (bot ICT) | Spread du broker trop large par rapport à la volatilité (souvent la nuit ou avant les annonces) : c'est le filtre de l'EA. Réglable dans les paramètres avancés |
| « hors fenêtre Silver Bullet et hors macro » | Normal : le bot ICT Pro ne cherche des setups que dans les fenêtres et macros de New York |
| « confidence … < required 0.62 » | Jev juge la situation trop incertaine (volatilité anormale, données manquantes) : aucune nouvelle position, les positions ouvertes restent gérées |
| Ordres refusés « below min notional » | Capital ou risque trop faible pour la taille minimale du broker : augmentez le risque par trade ou choisissez un actif avec une taille minimale plus petite |
