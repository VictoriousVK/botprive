# TRD : architecture technique (v0.4)

> Technical Requirements Document. **Comment** le produit est construit. Le besoin est dans
> [PRD.md](PRD.md) ; les tables et routes dans [BACKEND_SCHEMA.md](BACKEND_SCHEMA.md).

## 1. Vue d'ensemble

Un seul processus Python sert tout, sur une seule adresse :

```mermaid
flowchart LR
  V[Visiteur / membre<br>navigateur] -->|HTTPS| CF[Cloudflare Tunnel<br>ou Caddy]
  O[Opérateur] -->|HTTPS| CF
  CF -->|http 127.0.0.1:8000| APP
  subgraph PC[PC Windows de l'opérateur]
    APP[FastAPI<br>hedgefund.web] --> SITE[Site statique<br>hedgefund/web/site]
    APP --> DB[(SQLite<br>var/platform.db)]
    APP --> LED[(Journal append-only<br>var/platform_mode.db)]
    APP --> ENG[Moteur de bots] --> MT5[Terminal MetaTrader 5]
  end
  APP -->|HTTPS| WAVE[API Wave]
  APP -->|SMTP| MAIL[Brevo / Resend]
  APP -->|HTTPS| CLAUDE[API Anthropic<br>Coach IA]
  APP -->|HTTPS| SENTRY[Sentry]
  V -->|erreurs JS| SENTRY
  V -->|captcha| TS[Cloudflare Turnstile]
```

- **Pas de Node.js en production** : le site Next.js est exporté en HTML statique
  (`npm run publish-site`) et copié dans `hedgefund/web/site`, servi par FastAPI.
- **Même origine** pour le site et l'API : pas de CORS, cookies `SameSite`, CSP stricte.
- **SQLite** (mode WAL) pour l'état ; journal **append-only chaîné par hash** pour l'audit.

## 2. Stack

| Couche | Technologie | Version |
|---|---|---|
| Langage serveur | Python | ≥ 3.11 (testé en 3.13) |
| API | FastAPI + Uvicorn, Pydantic v2 | fastapi ≥ 0.110 |
| Front | Next.js (export statique, Turbopack), React, TypeScript, Tailwind CSS v4, Framer Motion, lucide-react | next 16.3, react 19.3, tailwind 4.3 |
| Base de données | SQLite (stdlib `sqlite3`) | — |
| Trading | MetaTrader5 (Windows), flux simulé ailleurs | — |
| IA | SDK `anthropic` ; Coach : `claude-sonnet-5-5` par défaut ; recherche : `claude-opus-5-5` | anthropic ≥ 1.8 |
| E-mail | `smtplib` (stdlib), tout fournisseur SMTP | — |
| Anti-bot | Cloudflare Turnstile (optionnel) | — |
| Supervision | `sentry-sdk[fastapi]` (serveur), `@sentry/browser` chargé à la demande (site) | sentry-sdk ≥ 2, @sentry/browser 10 |
| Tests | pytest, httpx (TestClient), Playwright (contrôles visuels) | pytest ≥ 8 |
| CI | GitHub Actions `.github/workflows/tests.yml` | — |

> **Attention Next.js** : `apps/web/AGENTS.md` rappelle que cette version de Next.js a des
> changements incompatibles. Avant de modifier le front, lire le guide concerné dans
> `apps/web/node_modules/next/dist/docs/`.

## 3. Arborescence utile

```
config/site.yaml              offres, prix, textes, robots affichés (modifiable sans code)
hedgefund/web/app.py          application FastAPI, sécurité, CSP, routes console
hedgefund/web/security.py     mots de passe scrypt, sessions, CSRF, TOTP, anti-bruteforce
hedgefund/web/observability.py Sentry (serveur + config du site)
hedgefund/members/api.py      routes /api/site, /api/m, /api/admin, webhook Wave
hedgefund/members/service.py  comptes, confirmation e-mail, reset, paiements, accès
hedgefund/members/mailer.py   envoi SMTP + modèles d'e-mails
hedgefund/members/antibot.py  e-mails jetables, Turnstile
hedgefund/members/academy.py  cours vidéo
hedgefund/members/copytrading.py copytrading démo
hedgefund/coach/              Coach IA + knowledge/ (fiches ICT)
apps/web/src/app/             pages du site (une route = un dossier page.tsx + view.tsx)
apps/web/src/components/      UI partagée (chrome, ui, markdown, turnstile, brand…)
apps/web/src/lib/             client API, session
tests/                        tests automatiques (193)
```

## 4. Sécurité

| Sujet | Mise en œuvre |
|---|---|
| Mots de passe | scrypt (N=2^15, r=8, p=1), sel 16 octets, 12 caractères min |
| Sessions | jeton 256 bits, seul son SHA-256 est stocké ; expiration absolue + inactivité ; cookie `HttpOnly`, `Secure`, `SameSite=Lax` (membres) / `Strict` (console) |
| CSRF | jeton par session dans `X-CSRF-Token` + contrôle de l'`Origin` sur toute écriture |
| Force brute | 5 échecs/15 min par login, 20 par IP |
| Inscription | piège invisible, domaines jetables, 5 inscriptions/h/IP, Turnstile optionnel, confirmation e-mail |
| Liens e-mail | jetons aléatoires, hachés en base, usage unique, 48 h (confirmation) / 60 min (reset) ; origine = `LF_PUBLIC_URL` ou `HF_PUBLIC_HOST`, jamais l'en-tête Host |
| Énumération | « renvoyer le lien » et « mot de passe oublié » répondent pareil que l'adresse existe ou non |
| En-têtes | CSP par page (scripts inline autorisés par hash), HSTS, `X-Frame-Options: DENY`, `no-referrer` |
| CSP tierces | Turnstile (`challenges.cloudflare.com`) et Sentry (hôte d'ingestion) ajoutés **seulement** s'ils sont configurés |
| Webhook Wave | signature HMAC vérifiée ; le paiement est relu depuis l'API Wave avant crédit |
| Journal | toute action opérateur et événement sensible (paiement, reset, e-mail confirmé, inscription bloquée) dans le journal append-only |
| Sentry | pas de corps de requête, cookies, en-têtes sensibles, jetons ni e-mails ; `send_default_pii=False` |

## 5. Composants v0.4

### 5.1 Confirmation d'e-mail

- Colonne `members.email_verified_at` ; table `email_tokens` (hash, membre, but, expiration,
  utilisation). Migration automatique au démarrage : les comptes existants sont marqués
  confirmés à leur date de création.
- `Members.register` → compte en attente → `send_verification` → e-mail → `POST /api/m/verify`
  consomme le jeton, confirme, ouvre la session.
- `member_opt` et `entitlements` refusent un compte non confirmé (défense en profondeur).
- Purge paresseuse : à chaque inscription, suppression des comptes non confirmés de plus de
  7 jours sans paiement.
- Désactivable (`LF_EMAIL_VERIFICATION=0`) pour un usage local.

### 5.2 E-mail

`mailer_from_env()` : `SmtpMailer` si `LF_SMTP_HOST` est défini (envoi dans un thread, erreurs
journalisées et donc remontées à Sentry), sinon `LogMailer` (écrit le lien dans le journal du
serveur et avertit au démarrage). Modèles HTML sobres + texte brut, contenu échappé.

### 5.3 Coach IA

- `hedgefund/coach/knowledge/*.md` : une fiche par sujet ; toute la base (~41 000 caractères)
  est envoyée dans le prompt système **mis en cache** (`cache_control: ephemeral`).
- Règles du prompt : la base fait foi ; dire « hors base » ; ne rien inventer ; pas de signal ;
  dernière ligne `SOURCES: id1, id2` analysée par le serveur puis retirée.
- Historique limité aux 8 derniers échanges ; question ≤ 2 000 caractères.
- Quota par membre et par jour UTC (`coach_questions`) ; chaque question est enregistrée pour
  l'admin.
- Activé si `ANTHROPIC_API_KEY` est présent (ou `LF_COACH=1`).

### 5.4 Sentry

- Serveur : `init_sentry()` dans `build_platform()` ; intégrations FastAPI et logging
  automatiques ; `before_send` nettoie les événements ; release `liberte-financiere@<version>`.
- Site : `/api/site` expose `sentry: {dsn, environment, release}` si `SENTRY_BROWSER_DSN` est
  défini ; `session.tsx` charge `@sentry/browser` à la demande ; les URL sont tronquées avant
  le `?` (jetons).

## 6. Configuration (variables d'environnement)

Sous Windows, dans `.env.ps1` (copié depuis `deploy/windows/env.example.ps1`).

| Variable | Rôle | Défaut |
|---|---|---|
| `HF_FEED` | `auto`, `mt5`, `simulation` | `auto` |
| `HF_HOST` / `HF_PORT` | écoute | `127.0.0.1` / `8000` |
| `HF_COOKIE_SECURE` | cookies `Secure` (mettre 0 seulement en http local) | `1` |
| `HF_PUBLIC_HOST` | domaine public derrière le tunnel | — |
| `HF_TRUST_PROXY` | lire l'IP réelle derrière Cloudflare/Caddy | `0` |
| `HF_ALLOW_REAL_TRADING` | autoriser l'argent réel | `0` |
| `LF_PUBLIC_URL` | `https://votre-domaine` : liens Wave et e-mails | — |
| `LF_WAVE_API_KEY`, `LF_WAVE_WEBHOOK_SECRET` | Wave Checkout | — |
| `LF_REGISTRATION` | inscriptions ouvertes | `1` |
| `LF_EMAIL_VERIFICATION` | confirmation d'e-mail obligatoire | `1` |
| `LF_SMTP_HOST`, `LF_SMTP_PORT`, `LF_SMTP_USER`, `LF_SMTP_PASSWORD`, `LF_SMTP_SECURITY`, `LF_MAIL_FROM` | envoi des e-mails | — / 587 / — / — / `starttls` / — |
| `LF_TURNSTILE_SITE_KEY`, `LF_TURNSTILE_SECRET` | Cloudflare Turnstile | — |
| `LF_BLOCKED_EMAIL_DOMAINS` | domaines refusés en plus (virgules) | — |
| `ANTHROPIC_API_KEY` | active le Coach IA | — |
| `LF_COACH`, `LF_COACH_MODEL`, `LF_COACH_DAILY_LIMIT` | coach : forcer on/off, modèle, quota | auto / `claude-sonnet-5-5` / 30 |
| `SENTRY_DSN`, `SENTRY_BROWSER_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_TRACES_SAMPLE_RATE` | Sentry | — / — / `production` / 0.1 |
| `LF_COPYTRADING` | `off`, `demo` | `demo` |
| `LF_MEDIA_HOSTS` | domaines vidéo autorisés | — |

## 7. Qualité

- `pytest -q` doit passer (193 tests en v0.4) avant tout commit ; la CI le refait.
- Front : `npm run lint` (TypeScript) puis `npm run publish-site` pour reconstruire
  `hedgefund/web/site`.
- Vérification visuelle avec Playwright (MCP Playwright dans Claude Code) sur 1 360 px et
  390 px.
- Les nouveaux fichiers Python passent `ruff check`.

## 8. Décisions d'architecture

| Décision | Pourquoi |
|---|---|
| Un seul processus, SQLite | Un opérateur, un PC, zéro administration de base de données ; suffisant pour quelques milliers de membres |
| Export statique du site | Pas de Node en production, CSP stricte, sécurité plus simple |
| SMTP générique plutôt qu'un SDK | Changer de fournisseur = changer 4 variables |
| Base du coach en Markdown dans le dépôt | Relue, versionnée et corrigée comme du code ; pas de base vectorielle à maintenir |
| Toute la base dans le prompt (pas de RAG) | ~11 000 tokens, mis en cache : plus fidèle et plus simple qu'une recherche approximative |
| Sentry optionnel | La plateforme ne dépend d'aucun service tiers pour fonctionner |

## 9. Dette technique connue

- `SameSite=Lax` et sessions membres de 72 h : à revoir si une app mobile arrive.
- Les e-mails partent d'un thread du processus : en cas d'arrêt brutal, un e-mail en cours
  peut être perdu (le membre peut renvoyer le lien).
- Pas encore de relance automatique avant expiration des abonnements.
- `app.py` (Streamlit, licences ICT Pure Master) reste séparé et utilise SHA-256 non salé pour
  son admin : à migrer ou retirer.
- Le dépôt GitHub est public : passer en privé.
