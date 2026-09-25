# Démarrer le projet en local, étape par étape

Le projet contient trois choses qui tournent ensemble dans **un seul programme Python** :

| Adresse (en local) | Quoi |
|---|---|
| http://127.0.0.1:8000 | le site **Liberté Financière** (accueil, formation ICT, offres, espace membre) |
| http://127.0.0.1:8000/console | la **console de trading Alpha Edge** (vos bots MT5) |
| http://127.0.0.1:8000/admin/ | l'**administration du site** (paiements Wave, membres, cours, réglages) |

Le site est déjà compilé dans le projet : **pas besoin de Node.js** pour le faire tourner.
Node.js ne sert que si vous voulez modifier le design du site (étape C).

Choisissez votre cas :

- **A. Sur Windows avec MetaTrader 5** : la vraie plateforme (prix et ordres MT5).
- **B. Sans MT5 (Windows, Mac ou Linux)** : prix simulés, pour découvrir le site et la console.
- **C. Modifier le site** (développeurs).

---

## A. Windows avec MetaTrader 5 (recommandé)

### Ce qu'il faut

- Windows 10/11 ou un VPS Windows.
- **MetaTrader 5** installé et connecté à un compte **démo**.
- **Python 3.11 ou plus récent** : https://www.python.org/downloads/ ; à l'installation, cochez
  **« Add python.exe to PATH »**.

### Étapes

1. **Décompressez** le zip, par exemple dans `C:\LiberteFinanciere`.
2. Ouvrez le dossier, faites **Shift + clic droit** dans le vide → **« Ouvrir la fenêtre
   PowerShell ici »** (ou « Ouvrir dans le terminal »).
3. Autorisez les scripts (une seule fois, répondez **O**) :
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
4. **Installez** (2 à 5 minutes) :
   ```powershell
   .\deploy\windows\install.ps1
   ```
   Cela crée l'environnement Python `.venv` et le fichier de réglages `.env.ps1`.
5. **Créez votre compte opérateur** (il n'existe aucun compte par défaut ; mot de passe de
   12 caractères minimum, demandé deux fois) :
   ```powershell
   .\.venv\Scripts\python.exe -m hedgefund.web create-user --username victor
   ```
6. **Réglez `.env.ps1`** : ouvrez-le avec le Bloc-notes et, pour un usage en local, mettez
   ```powershell
   $env:HF_COOKIE_SECURE = "0"
   ```
   (à remettre à `"1"` le jour où le site sera en ligne en HTTPS).
7. Dans **MetaTrader 5** : connectez-vous au compte démo et activez le bouton
   **« Algo Trading »** (il doit être vert).
8. **Démarrez** :
   ```powershell
   .\deploy\windows\start.ps1
   ```
   Laissez cette fenêtre ouverte : c'est la plateforme. La ligne
   `Plateforme : http://127.0.0.1:8000 (flux : mt5 …)` confirme qu'elle tourne.
9. **Ouvrez votre navigateur** :
   - http://127.0.0.1:8000 : le site ;
   - http://127.0.0.1:8000/console : connectez-vous avec le compte de l'étape 5 ;
   - http://127.0.0.1:8000/admin/ : l'administration (après la connexion à la console).

### Premiers réglages (5 minutes)

1. `/admin/` → **Réglages** : collez vos liens d'invitation Telegram et Discord.
2. Sur le site, **créez un compte membre de test** (bouton « Commencer gratuitement »), puis
   achetez la formation ICT : vous verrez le paiement Wave manuel (numéro, montant,
   référence). Déclarez un faux ID de transaction, validez-le dans `/admin/` → **Paiements**,
   et vérifiez que l'accès et les boutons Telegram / Discord apparaissent dans l'espace membre.
   Ensuite, suspendez ce membre de test dans `/admin/` → **Membres**.
3. `/admin/` → **Académie** : créez le cours avec l'adresse `victorious-trader` et l'accès
   « Formation ICT Victorious Trader », puis ajoutez les vidéos (voir `docs/SITE.md` §3).
4. `/console` → **Réglages** : mode **Papier** d'abord (prix MT5, aucun ordre envoyé), puis
   **Bots** → créez un bot ICT Pro v6.20 sur l'or, **Backtester**, **Enregistrer**,
   **Démarrer**.

### Arrêter, redémarrer

- Arrêter : **Ctrl+C** dans la fenêtre PowerShell (deux fois si elle redémarre seule).
- Redémarrer : `.\deploy\windows\start.ps1`.
- Démarrage automatique à l'ouverture de session : `.\deploy\windows\register-task.ps1`.
- Vos données (comptes, bots, paiements, journal) sont dans le dossier `var\`. Sauvegardez-le.

---

## B. Sans MT5 : prix simulés (Windows, Mac, Linux)

Il faut seulement **Python 3.11+**.

**Windows (PowerShell)**, dans le dossier du projet :
```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[web]"
.\.venv\Scripts\python.exe -m hedgefund.web create-user --username victor
$env:HF_FEED = "simulation"; $env:HF_COOKIE_SECURE = "0"
.\.venv\Scripts\python.exe -m hedgefund.web serve
```

**Mac / Linux (Terminal)**, dans le dossier du projet :
```bash
python3 -m venv .venv
.venv/bin/pip install -e ".[web]"
.venv/bin/python -m hedgefund.web create-user --username victor
HF_FEED=simulation HF_COOKIE_SECURE=0 .venv/bin/python -m hedgefund.web serve
```

Puis ouvrez http://127.0.0.1:8000. Le bandeau affiche « PRIX SIMULÉS » : rien n'est réel,
aucun ordre n'est envoyé nulle part.

---

## C. Modifier le site (optionnel, développeurs)

Il faut **Node.js 22** (https://nodejs.org) en plus de Python, et la plateforme lancée
(A ou B) dans une autre fenêtre, **avec en plus le réglage `HF_PUBLIC_HOST=localhost:3000`**
(sinon la plateforme refuse les formulaires envoyés depuis le port 3000, par sécurité) :

```bash
# Mac / Linux
HF_PUBLIC_HOST=localhost:3000 HF_FEED=simulation HF_COOKIE_SECURE=0 .venv/bin/python -m hedgefund.web serve
```
```powershell
# Windows : dans .env.ps1, $env:HF_PUBLIC_HOST = "localhost:3000", puis .\deploy\windows\start.ps1
```

Puis, dans une seconde fenêtre :

```bash
cd apps/web
npm ci                  # une fois
npm run dev             # site en direct sur http://localhost:3000 (se recharge à chaque modification)
```

Le site de développement parle à la plateforme sur le port 8000. Quand le résultat vous
convient :

```bash
npm run publish-site    # compile et copie le site dans hedgefund/web/site
```

Rechargez http://127.0.0.1:8000 : la plateforme sert la nouvelle version (pas besoin de la
redémarrer). Remettez `HF_PUBLIC_HOST` à vide (ou à votre nom de domaine) une fois fini.

Les textes, prix, offres, numéro Wave et WhatsApp se changent sans Node.js, dans
`config/site.yaml` (redémarrez la plateforme après modification).

---

## Vérifier que tout fonctionne (développeurs)

```bash
pip install -e ".[research,web,dev]"
pytest -q                      # tous les tests Python
python -m hedgefund validate   # configuration
```

## En cas de problème

| Symptôme | Solution |
|---|---|
| `python` n'est pas reconnu | Réinstallez Python en cochant « Add python.exe to PATH », puis rouvrez PowerShell |
| « l'exécution de scripts est désactivée » | Étape A.3 : `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| « Aucun utilisateur : créez-en un d'abord » | Étape A.5 (`create-user`) |
| La connexion à la console échoue sans message | `HF_COOKIE_SECURE` doit valoir `"0"` en local (étape A.6), puis redémarrez |
| « MT5 déconnecté » | MT5 doit être ouvert, connecté, et lancé par le même utilisateur Windows |
| Le port 8000 est déjà utilisé | Dans `.env.ps1` : `$env:HF_PORT = "8001"`, puis ouvrez http://127.0.0.1:8001 |
| Mot de passe opérateur oublié | `.\.venv\Scripts\python.exe -m hedgefund.web reset-password --username victor` |
| Mot de passe d'un membre oublié | `.\.venv\Scripts\python.exe -m hedgefund.web member-password --email membre@exemple.com` |

Pour aller plus loin : `docs/PLATFORM.md` (console, MT5, mise en ligne en HTTPS, compte réel)
et `docs/SITE.md` (site, Wave, académie, copytrading, offres).
