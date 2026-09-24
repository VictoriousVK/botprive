# Plateforme HedgeFund pour MetaTrader 5 : guide complet

La plateforme web pilote vos bots de trading sur MT5, depuis un navigateur (ordinateur ou
téléphone). Elle sert à :

- **choisir l'actif** : or, argent, Nasdaq, S&P 500, DAX, Bitcoin, Ethereum, forex,
  pétrole… (la liste vient directement de votre broker) ;
- **choisir une stratégie** : suivi de tendance, retour à la moyenne, ou paire (valeur
  relative, par exemple or/argent ou Nasdaq/S&P 500) ;
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
7. Ouvrez **http://127.0.0.1:8000** dans le navigateur du PC et connectez-vous.

## 5. Utilisation

1. **Réglages → Mode d'exécution** : commencez en **Papier** (prix MT5, aucun ordre).
2. **Réglages → Capital alloué** : la somme que les bots peuvent utiliser pour calculer
   leurs tailles de position (par défaut, l'équité du compte).
3. **Bots → + Nouveau bot** :
   - choisissez une **stratégie** ;
   - choisissez l'**actif** : filtrez par famille (Métaux, Indices, Crypto, Forex…) ou
     tapez « or », « nasdaq », « btc »… La fiche affiche le prix, le spread et la **taille
     minimale d'un ordre** chez votre broker ;
   - choisissez l'unité de temps (15 min, 1 h, 4 h, 1 jour), le sens (achat et vente, achat
     seul, vente seule), le risque par trade (0,05 % à 1,5 %) et la position maximale ;
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
| Ordres refusés « below min notional » | Capital ou risque trop faible pour la taille minimale du broker : augmentez le risque par trade ou choisissez un actif avec une taille minimale plus petite |
