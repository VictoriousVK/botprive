# App Flow : pages et parcours (v0.4)

> Toutes les pages et les chemins que suivent visiteurs, membres et opérateurs. Les diagrammes
> s'affichent sur GitHub (Mermaid).

## 1. Plan du site

```mermaid
flowchart TB
  HOME["/ Accueil"] --> FICT["/formation-ict/"]
  HOME --> ROB["/robots/"]
  HOME --> COPY["/copytrading/"]
  HOME --> ACA["/academie/"] --> COURS["/academie/cours/?c=slug"]
  HOME --> APPS["/app/ espace de trading (SaaS)"]
  APPS --> BIEN["/app/bienvenue/ mise en route"]
  APPS --> MENT["/app/mentor/ Mentor IA (questions ICT)"]
  COACH["/coach/ (ancienne adresse)"] -.-> MENT
  HOME --> TAR["/tarifs/"]
  HOME --> RISK["/risques/ (conditions, confidentialité)"]
  HOME --> CPT["/compte/ connexion · inscription · espace membre"]
  CPT --> VER["/compte/verifier/?jeton=… (lien e-mail)"]
  CPT --> MDP["/compte/mot-de-passe/?jeton=… (lien e-mail)"]
  ADM["/admin/ (opérateurs)"]
  CON["/console (opérateurs, trading)"]
```

| Page | Accès | Rôle |
|---|---|---|
| `/` | public | présentation, offres, robots, FAQ |
| `/formation-ict/` | public | programme Victorious Trader, achat |
| `/robots/` | public | catalogue des EA |
| `/copytrading/` | public ; suivre = membre | stratégies, copie démo |
| `/academie/`, `/academie/cours/` | public ; vidéos selon les droits | cours vidéo |
| `/app/` | membre connecté | espace de trading : tableau de bord, journal, revue du Coach, analyse ICT, risque, Mentor, laboratoire, usine EA, formation, réglages (fonctions selon l'offre, voir [SAAS.md](SAAS.md)) |
| `/app/bienvenue/` | membre connecté | mise en route en 4 étapes (profil, prop firm, plan de risque, premier compte) |
| `/app/mentor/` | droit `academy_member` | questions sur ICT et la formation, passages cités |
| `/coach/` | public | ancienne adresse du coach : renvoie vers `/app/mentor/` |
| `/tarifs/` | public | offres et durées, paiement Wave |
| `/compte/` | public → membre | connexion, inscription, mot de passe oublié, espace membre, paiements |
| `/compte/verifier/` | lien e-mail | confirme l'adresse et connecte |
| `/compte/mot-de-passe/` | lien e-mail | nouveau mot de passe |
| `/admin/` | opérateur connecté à la console | pilotage du site |
| `/console` | opérateur | bots, MT5, arrêt d'urgence |

## 2. Inscription et confirmation d'e-mail

```mermaid
sequenceDiagram
  actor U as Visiteur
  participant S as Site /compte/
  participant A as API
  participant M as Boîte e-mail
  U->>S: Remplit nom, e-mail, mot de passe, accepte les conditions
  S->>A: POST /api/m/register (+ captcha si Turnstile, champ piège vide)
  alt Champ piège rempli (robot)
    A-->>S: {pending} (rien n'est créé)
  else Adresse jetable / trop d'inscriptions / captcha faux
    A-->>S: 400 message clair
  else OK
    A->>A: compte en attente + jeton 48 h
    A->>M: E-mail « Confirmez votre adresse »
    A-->>S: {pending: true, email}
    S-->>U: Écran « Confirmez votre adresse e-mail » (renvoyer le lien)
    U->>M: Ouvre l'e-mail, clique
    M->>S: /compte/verifier/?jeton=…
    S->>A: POST /api/m/verify {token}
    A-->>S: profil + cookie de session
    S-->>U: « Adresse confirmée » → /app/bienvenue/ (ou l'offre qu'il payait, même navigateur)
  end
```

Cas particuliers :

- **Connexion avant confirmation** → 403 « e-mail non confirmé » + bouton **Renvoyer le lien**.
- **Lien expiré ou déjà utilisé** → page « Lien non valide » → connexion → renvoyer le lien.
- **Faute de frappe dans l'e-mail** → se réinscrire avec la bonne adresse ; l'ancienne
  inscription en attente disparaît après 7 jours.
- **E-mail jamais reçu** → l'opérateur peut confirmer à la main dans `/admin/` → Membres.

## 3. Connexion et mot de passe oublié

```mermaid
flowchart LR
  L[Connexion] -->|ok| E[Espace membre]
  L -->|2FA activée| T[Code 2FA] --> E
  L -->|e-mail non confirmé| R[Renvoyer le lien]
  L -->|Mot de passe oublié ?| F[Saisir l'e-mail] --> FM[E-mail lien 60 min]
  FM --> P["/compte/mot-de-passe/"] --> N[Nouveau mot de passe x2] --> E
```

Après un changement de mot de passe, toutes les anciennes sessions sont fermées. Un compte
avec 2FA doit se reconnecter normalement.

## 4. Achat d'une offre (Wave)

```mermaid
sequenceDiagram
  actor U as Membre
  participant S as Site
  participant A as API
  participant W as Wave
  U->>S: /tarifs/ → choisit offre + durée
  S->>S: /compte/?offre=…&mois=… (connexion si besoin)
  U->>S: « Payer X FCFA avec Wave »
  S->>A: POST /api/m/checkout
  alt API Wave configurée
    A->>W: crée la session de paiement
    A-->>S: launch_url
    U->>W: paie dans l'app Wave
    W->>S: retour /compte/?paiement=…
    W->>A: webhook signé
    A->>W: relit la session (montant, devise, référence)
    A->>A: crédite l'accès (une seule fois)
  else Transfert manuel
    A-->>S: numéro Wave + référence
    U->>S: déclare l'ID de transaction
    Note over A: l'opérateur valide dans /admin/ → Paiements
  end
  S-->>U: accès visible dans l'espace membre
```

## 5. Questions ICT : le Mentor

```mermaid
flowchart TB
  C["/coach/ (ancienne adresse)"] --> M["/app/mentor/"]
  M --> Q{Connecté ?}
  Q -- non --> LOG[Connexion / inscription]
  Q -- oui --> D{Droit academy_member ?}
  D -- non --> UP[Fonction de l'offre Starter et plus → /tarifs/]
  D -- oui --> ASK[Question]
  ASK -->|POST /api/app/mentor/ask| R{Passages trouvés ?}
  R -- non --> OOC[« Hors des contenus »]
  R -- oui --> ANS[Réponse + passages cités]
  ASK -->|quota du mois atteint| LIM[Message clair, rien ne casse]
  ASK -->|demande de conseil| REF[Refus : pas de conseil personnalisé]
```

- Sources : fiches ICT, définitions du moteur, cours de l'académie, documents de l'équipe,
  filtrés selon les droits du membre.
- Sous chaque réponse : les passages cités et un verdict (sourcée, partielle, hors des contenus).
- Sans IA : les passages les plus proches, tels quels, avec un avertissement.

## 6. Académie

Catalogue → cours → parties. Une partie verrouillée affiche l'offre qui la débloque ; la
progression est enregistrée toutes les quelques secondes (`POST /api/m/progress`).

## 7. Copytrading (démo)

`/copytrading/` → stratégie → réglages (allocation, multiplicateur, drawdown max) → accepter
l'avertissement → suivi démo. Arrêt manuel ou automatique au drawdown max. Aucun ordre réel.

## 8. Opérateurs

```mermaid
flowchart LR
  OP[Opérateur] --> CON[/console : connexion + 2FA/]
  CON --> ADM[/admin/]
  ADM --> PAY[Paiements : valider / refuser les transferts Wave]
  ADM --> MEM[Membres : attribuer un accès, suspendre, confirmer un e-mail]
  ADM --> ACA[Académie : cours et vidéos]
  ADM --> CP[Copytrading : stratégies]
  ADM --> LEAD[Prospects]
  ADM --> CO[SaaS IA : santé, base du Mentor, questions à couvrir]
  ADM --> SET[Réglages : liens Telegram / Discord]
  OP --> SEN[Sentry : erreurs, performances, disponibilité]
```

Les opérateurs sont créés uniquement sur le serveur :
`python -m hedgefund.web create-user --username NOM`.

## 9. États vides et erreurs (à respecter sur toute nouvelle page)

| Situation | Comportement attendu |
|---|---|
| Chargement | `<Spinner />` avec un libellé |
| Liste vide | `<Empty />` avec une phrase utile et, si possible, une action |
| Erreur API | `<Notice kind="error">` avec le message du serveur (déjà en français) |
| Réseau coupé | « Connexion impossible : vérifiez votre réseau. » |
| Non connecté | invitation à se connecter, jamais une page blanche |
| Droit manquant | ce que l'offre débloque + lien vers `/tarifs/` |
