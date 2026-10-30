# Mise en route de la v0.4 (sans coder)

Quatre réglages à faire une fois : **e-mails**, **Sentry**, **IA (Mentor, Coach, Analyste)**, et en option
**Cloudflare Turnstile**. Tous se font dans votre fichier `.env.ps1` (copie de
`deploy/windows/env.example.ps1`), puis **redémarrez la plateforme**
(`.\deploy\windows\start.ps1`).

> Avant de mettre à jour : **copiez le dossier `var\`** ailleurs (sauvegarde). La v0.4
> ajoute une colonne à la table des membres ; vos membres actuels restent actifs
> automatiquement.

---

## 1. E-mails (obligatoire pour la confirmation d'inscription)

Sans serveur d'e-mail, les liens de confirmation sont seulement écrits dans la fenêtre du
serveur : les membres ne les reçoivent pas.

### Option A : Brevo (gratuit jusqu'à 300 e-mails/jour, interface en français)

1. Créez un compte sur brevo.com.
2. **Expéditeurs, domaines** → ajoutez votre domaine (ex. `liberte-financiere.com`) et
   recopiez chez votre hébergeur DNS les enregistrements proposés (DKIM, et DMARC
   conseillé). Sans cela, vos e-mails iront dans les spams.
3. **SMTP et API** → onglet SMTP : notez le serveur, le port, l'identifiant et générez une
   **clé SMTP**.
4. Dans `.env.ps1` :

```powershell
$env:LF_PUBLIC_URL = "https://liberte-financiere.com"   # votre adresse publique, obligatoire
$env:LF_SMTP_HOST = "smtp-relay.brevo.com"
$env:LF_SMTP_PORT = "587"
$env:LF_SMTP_SECURITY = "starttls"
$env:LF_SMTP_USER = "votre-identifiant-smtp@smtp-brevo.com"
$env:LF_SMTP_PASSWORD = "votre-cle-smtp"
$env:LF_MAIL_FROM = "Liberté Financière <no-reply@liberte-financiere.com>"
```

### Option B : Resend (3 000 e-mails/mois gratuits)

Même principe : vérifiez votre domaine, créez une clé API, puis :

```powershell
$env:LF_SMTP_HOST = "smtp.resend.com"
$env:LF_SMTP_PORT = "465"
$env:LF_SMTP_SECURITY = "ssl"
$env:LF_SMTP_USER = "resend"
$env:LF_SMTP_PASSWORD = "re_votre_cle_api"
$env:LF_MAIL_FROM = "Liberté Financière <no-reply@liberte-financiere.com>"
```

Vérifiez les valeurs exactes dans le tableau de bord du fournisseur : elles peuvent évoluer.

### Tester

Inscrivez-vous avec une autre adresse que la vôtre (Gmail par exemple). L'e-mail doit
arriver en moins d'une minute. Sinon, regardez la fenêtre du serveur : l'erreur SMTP y est
écrite (et dans Sentry s'il est actif).

### Si un membre ne reçoit rien

`/admin/` → **Membres** → bouton **Confirmer l'e-mail** sur sa ligne.

---

## 2. Sentry : voir les erreurs et la santé du site

1. Créez un compte sur sentry.io (offre gratuite « Developer » suffisante pour démarrer).
2. Créez **deux projets** : `liberte-financiere-serveur` (plateforme **Python → FastAPI**) et
   `liberte-financiere-site` (plateforme **Browser JavaScript**).
3. Pour chacun : **Settings → Projects → Client Keys (DSN)**, copiez le DSN.
4. Installez le module une fois :

```powershell
.\.venv\Scripts\python.exe -m pip install -e ".[web,saas,mt5,research,monitoring]"
```

5. Dans `.env.ps1` :

```powershell
$env:SENTRY_DSN = "https://...@o123.ingest.sentry.io/111"           # projet serveur
$env:SENTRY_BROWSER_DSN = "https://...@o123.ingest.sentry.io/222"   # projet site
$env:SENTRY_ENVIRONMENT = "production"
```

6. Redémarrez. Au démarrage, le journal affiche « Sentry actif ».

### Ce que vous verrez dans Sentry

| Écran Sentry | À quoi il sert pour vous |
|---|---|
| **Issues** | chaque bug, avec la page, le nombre de membres touchés, la version |
| **Performance / Traces** | les routes lentes (paiement, Mentor…) |
| **Uptime** (Alerts → Uptime Monitor) | ajoutez `https://votre-domaine/api/health` : alerte si le PC ou le tunnel tombe |
| **Alerts** | e-mail (ou Discord via l'intégration) dès qu'une nouvelle erreur apparaît |
| **Releases** | quelle version a introduit un problème |

Les chiffres business (membres, paiements, revenus) restent dans **`/admin/`** : Sentry
surveille la santé technique, l'admin pilote l'activité.

**Le plus utile quand on ne code pas :** dans Claude Code, avec le serveur MCP Sentry (voir
[CLAUDE_CODE_OUTILS.md](CLAUDE_CODE_OUTILS.md)), demandez simplement :
« Liste les erreurs Sentry de la semaine, explique-les simplement et corrige-les avec des
tests. »

Aucune donnée sensible n'est envoyée : pas de mot de passe, cookie, e-mail, ni contenu de
formulaire.

---

## 3. IA : Mentor (questions ICT), Coach et Analyste

Les questions sur ICT passent par le **Mentor** de l'espace de trading (`/app/mentor/`) : il
répond à partir des 15 fiches ICT, des définitions du moteur et des cours, et affiche ses sources.
L'ancienne adresse `/coach/` y renvoie.

1. Créez une clé sur console.anthropic.com (ajoutez un moyen de paiement et une limite de
   dépense mensuelle).
2. Dans `.env.ps1` :

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

3. Redémarrez. Sans clé, tout fonctionne quand même : le Mentor montre les passages les plus
   proches, le Coach et l'Analyste écrivent leurs textes avec les règles (mêmes chiffres).

Qui y a accès : le Mentor est ouvert aux offres Starter (60 questions par mois), Pro Trader (120)
et Quant Elite (300), réglées dans `config/saas.yaml` avec un plafond de coût IA par membre.
Les modèles sont fixés dans `config/models.yaml`.

Pour l'améliorer : `/admin/` → **SaaS IA** → **Questions posées au Mentor**, case « Seulement
celles à couvrir ». Chaque question listée est une fiche à écrire dans
`hedgefund/saas/fiches_ict/` (mode d'emploi dans le `README.md` du dossier), puis **Réindexer**.
Vous pouvez demander à Claude Code : « Écris une fiche ICT sur <sujet> au même format que les
autres, en français, et relis-la avec moi. »

Coût : environ 0,02 $ par question au Mentor (estimation de `config/saas.yaml`). Surveillez la
consommation dans console.anthropic.com et dans `/admin/` → SaaS IA les premières semaines.

---

## 4. Cloudflare Turnstile (option, recommandé si les robots insistent)

1. Tableau de bord Cloudflare → **Turnstile** → **Add widget** → votre domaine → mode
   « Managed ».
2. Copiez la **Site Key** et la **Secret Key** :

```powershell
$env:LF_TURNSTILE_SITE_KEY = "0x4AAAA..."
$env:LF_TURNSTILE_SECRET = "0x4AAAA..."
```

3. Redémarrez : la vérification apparaît sous le formulaire d'inscription.

---

## 5. Autres réglages anti-robots

```powershell
$env:LF_BLOCKED_EMAIL_DOMAINS = "domaine-suspect.com,autre.xyz"  # en plus de la liste intégrée
# $env:LF_EMAIL_VERIFICATION = "0"   # désactiver la confirmation (uniquement pour tester en local)
# $env:LF_REGISTRATION = "0"         # fermer les inscriptions
```

## 6. Vérification finale

- [ ] Inscription → e-mail reçu → lien → connecté automatiquement.
- [ ] Connexion avant confirmation → message + bouton « Renvoyer le lien ».
- [ ] « Mot de passe oublié » → e-mail → nouveau mot de passe.
- [ ] Sentry : Issues vide, Uptime vert sur `/api/health`.
- [ ] Mentor : un compte Starter (ou plus) pose une question ICT dans `/app/mentor/`, les passages
  cités s'affichent ; `/coach/` renvoie bien vers le Mentor.
- [ ] `/admin/` : « Membres confirmés » et « + N en attente ».
