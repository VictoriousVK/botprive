# Importer tes membres actuels

Tes membres actuels gardent leur date de fin, **sans repayer**. L'import se fait en deux temps : **aperçu** (rien n'est écrit), puis **import confirmé**.

## 1. Préparer le fichier

### Le plus simple : partir de la liste Discord
Tableau de bord → **Import CSV** → **Exporter les détenteurs actuels du rôle abonné**.
Tu obtiens un CSV avec l'identifiant Discord et le pseudo de chaque personne qui a déjà le rôle. Il ne reste qu'à compléter `formule` et `date_de_fin` (et, si tu les as, `email` et `téléphone`).
Cet export est en lecture seule : il ne modifie rien sur Discord.

### Sinon : à la main
Télécharge le modèle (Import CSV → **Télécharger le modèle**) ou crée un tableau avec ces colonnes, dans cet ordre :

| discord_user_id | nom | email | téléphone | formule | date_de_fin |
|---|---|---|---|---|---|
| 123456789012345678 | Awa Diop | awa@exemple.sn | +221 77 000 00 01 | Mensuel | 2026-11-30 |
| 234567890123456789 | Moussa Ndiaye | | +221 77 000 00 02 | Trimestriel | 15/01/2027 |

**Trouver l'identifiant Discord d'un membre** : Paramètres Discord → Avancés → active le *Mode développeur*. Ensuite, clic droit (ou appui long sur mobile) sur le membre → **Copier l'identifiant**. C'est un nombre de 17 à 20 chiffres. Le pseudo ne suffit pas : il peut changer.

### Règles
- `formule` : `Mensuel`, `Trimestriel` ou `Annuel` (majuscules et accents indifférents).
- `date_de_fin` : `AAAA-MM-JJ` (2026-11-30) ou `JJ/MM/AAAA` (30/11/2026). L'accès court jusqu'à la fin de ce jour, heure de Dakar.
- `email` et `téléphone` : facultatifs. Sans email, les rappels passent seulement par message Discord.
- Une ligne par membre, sans doublon d'identifiant.

### Enregistrer depuis Excel ou Google Sheets
- Excel : Fichier → Enregistrer sous → **CSV UTF-8 (délimité par des virgules)**. Le point-virgule est aussi accepté.
- Google Sheets : Fichier → Télécharger → **Valeurs séparées par des virgules (.csv)**.
- ⚠️ Excel peut transformer les identifiants Discord en `1,23457E+17`. Avant de coller les identifiants, mets la colonne `discord_user_id` au format **Texte**.

## 2. Vérifier (aperçu)
Tableau de bord → **Import CSV** → choisis le fichier → **Vérifier le fichier**. Chaque ligne est contrôlée :

| Résultat | Signification |
|---|---|
| **OK** | Importable |
| **À vérifier** | Importable, avec une remarque : absent du serveur Discord, pas d'email, date passée (importé comme expiré), échéance dépassée (importé en période de grâce), date de fin inhabituellement lointaine |
| **Rejetée** | Identifiant invalide, doublon, formule inconnue, date ou email invalide. Corrige le fichier et recommence |
| **Ignorée** | Membre déjà enregistré avec un abonnement (rien n'est écrasé) |

La présence sur le serveur est vérifiée en lecture seule auprès de Discord. Si le bot n'est pas configuré, elle apparaît comme « non vérifié ».

## 3. Importer
Clique sur **Importer N membre(s)**. Le fichier est revérifié côté serveur. L'import est sans risque de doublon : relancer le même fichier n'importe rien de plus.

**Et Discord ?** Tant que le mode Discord est sur **Observation** (par défaut), l'import ne modifie aucun rôle. Le salon de logs indique ce qui serait fait. Quand tout est vérifié, passe en mode **Réel** (Tableau de bord → Discord) : le bot alignera alors les rôles sur les abonnements.

**Ordre conseillé** : importer → vérifier les fiches (Tableau de bord → Membres) → lire la réconciliation du lendemain en mode observation (retraits et attributions qui auraient eu lieu) → passer Discord en réel.

## En ligne de commande (alternative)
```bash
pnpm import:members membres.csv           # aperçu détaillé
pnpm import:members membres.csv --apply   # import
```
