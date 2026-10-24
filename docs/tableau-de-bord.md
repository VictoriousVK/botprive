# Tableau de bord administrateur

Adresse : `https://ton-domaine/admin` (en local : `http://localhost:3000/admin`).

**Accès** : connexion avec ton compte Discord. Ton identifiant Discord doit figurer dans la variable `ADMIN_DISCORD_IDS`. Chaque page et chaque action vérifient ce droit, et chaque modification est enregistrée dans le journal d'audit.

## Écrans

| Écran | Ce que tu y fais |
|---|---|
| **Vue d'ensemble** | Mode des paiements (test ou réel), mode Discord (observation ou réel), alertes (prix manquants, tarifs non validés, Telegram public…), chiffres clés, échéances à 7 jours, derniers paiements |
| **Tarifs** | Prix FCFA encaissés, prix $ affichés, badge, accroche, formule proposée ou non. **Validation des tarifs** (obligatoire avant tout encaissement réel). Création des plans de prélèvement Flutterwave |
| **Lives** | Jours et horaires (MAR / MER / VEN par défaut, horaire « à venir » tant que la case est vide), format, note. Affichés sur le site et dans le message de bienvenue |
| **Telegram** | Lien du groupe et visibilité : **public** (accueil + espace membre) ou **membres actifs uniquement**. Le lien initial vient de `TELEGRAM_INVITE_URL` |
| **Discord** | Mode **Observation** (rien n'est modifié pour tes membres réels) ou **Réel** (il faut taper `ACTIVER`). Comptes de test pour lesquels les actions sont réelles même en observation |
| **Membres** | Recherche (ID Discord, pseudo, email, référence de paiement) et fiche : abonnement, paiements, périodes, journal |
| **Paiements** | Liste filtrable par statut |
| **Import CSV** | Export des détenteurs actuels du rôle, modèle, aperçu ligne par ligne, import ([guide](guide-import-membres.md)) |
| **Journal** | Les 200 dernières actions (paiements, rôles réels ou simulés, commandes, réglages) |

## Règles importantes
- **Aucun montant n'est prédéfini.** Une formule sans prix FCFA reste affichée « Bientôt disponible » et ne peut pas être achetée.
- **Changer un prix annule la validation** et détache le plan Flutterwave de la formule : un plan garde son montant, il faut en créer un nouveau. Les abonnés déjà en prélèvement automatique gardent leur montant d'origine.
- **Mode test** (`PAYMENT_MODE=test`, par défaut) : un bandeau l'indique sur tout le site, et des clés réelles sont automatiquement écartées. Le passage en réel se fait par la variable d'environnement, pas depuis l'écran (protection contre une erreur de clic).
- **Ajouter ou retirer un accès** : commandes `/ajouter` et `/retirer` sur Discord (journalisées).

## Ordre de mise en route conseillé
1. Lives : saisir les horaires dès qu'ils sont fixés.
2. Telegram : choisir la visibilité.
3. Tarifs : saisir les prix, vérifier sur le site, **valider**.
4. Discord : ajouter un compte de test, faire un paiement de test, vérifier rôle et messages.
5. Import CSV de tes membres actuels.
6. Discord : passer en **Réel**.
7. Paiements : passer `PAYMENT_MODE=live` avec les clés de production (après validation du prestataire).
