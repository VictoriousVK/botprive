# Configuration du bot Discord

Durée : environ 20 minutes. Tous les secrets vont dans `.env` (en local) ou dans les variables Railway (en production), **jamais dans un chat**.

## 1. Créer l'application

1. Va sur <https://discord.com/developers/applications> → **New Application** → nom : `V_ICT_ORIOUS Live Club`.
2. Onglet **General Information** : copie l'**Application ID** → `DISCORD_CLIENT_ID`.
3. Onglet **OAuth2** :
   - **Client Secret** → *Reset Secret* → copie-le dans `DISCORD_CLIENT_SECRET`.
   - **Redirects** → ajoute :
     - `https://TON-DOMAINE/api/auth/discord/callback` (production)
     - `http://localhost:3000/api/auth/discord/callback` (développement)

## 2. Créer le bot

Onglet **Bot** :
1. **Reset Token** → copie le token dans `DISCORD_BOT_TOKEN`. (S'il fuit un jour : Reset Token immédiatement.)
2. **Public Bot** : désactive-le (personne d'autre ne pourra l'ajouter à son serveur).
3. **Privileged Gateway Intents** : active **Server Members Intent**. Il est indispensable pour la réconciliation et l'arrivée des membres. *Presence* et *Message Content* restent désactivés.

## 3. Inviter le bot sur ton serveur

Ouvre ce lien, en remplaçant `CLIENT_ID` :

```
https://discord.com/oauth2/authorize?client_id=CLIENT_ID&scope=bot+applications.commands&permissions=268438529
```

Permissions demandées (ni plus, ni moins) :

| Permission | Pourquoi |
|---|---|
| Gérer les rôles | Donner et retirer le rôle abonné |
| Créer une invitation | Exigée par Discord pour ajouter un membre au serveur (`guilds.join`) |
| Voir les salons + Envoyer des messages | Salon de logs |

Si tu actives l'option d'expulsion (`EXPIRY_ACTION=kick`), utilise `permissions=268438531` (ajoute « Expulser des membres »).
**Ne donne jamais la permission Administrateur.**

## 4. Hiérarchie des rôles (indispensable)

Discord n'autorise un bot à gérer que les rôles **situés en dessous du sien**.

1. Paramètres du serveur → **Rôles**.
2. Crée le rôle des abonnés (ex : `Membre Live Club`) s'il n'existe pas. Donne-lui l'accès aux salons privés du club.
3. **Fais glisser le rôle du bot au-dessus du rôle `Membre Live Club`.**
4. Le rôle du bot doit rester **en dessous** de ton rôle admin.

Sans cela, l'attribution échoue avec « Missing Permissions ». Les tâches sont réessayées et une alerte apparaît dans le salon de logs.

## 5. Salon de logs privé

1. Crée un salon texte `#logs-club`, visible uniquement par toi, les modérateurs et le bot.
2. Donne au rôle du bot : *Voir le salon* + *Envoyer des messages*.

Le bot y poste : nouvel abonné, paiement, renouvellement, retrait d'accès, erreurs, résumé de réconciliation. Les mentions s'affichent sans notifier personne.

## 6. Récupérer les identifiants

Active le **mode développeur** : Paramètres utilisateur → Avancés → Mode développeur. Ensuite, clic droit → « Copier l'identifiant » :

| Variable | Où |
|---|---|
| `DISCORD_GUILD_ID` | Clic droit sur l'icône du serveur |
| `DISCORD_MEMBER_ROLE_ID` | Paramètres du serveur → Rôles → clic droit sur le rôle abonné |
| `DISCORD_ADMIN_ROLE_ID` | Idem, ton rôle admin (seul autorisé à utiliser les commandes) |
| `DISCORD_LOG_CHANNEL_ID` | Clic droit sur `#logs-club` |
| `DISCORD_EXEMPT_ROLE_IDS` | Rôles jamais touchés par la réconciliation (modérateurs, invités spéciaux…), séparés par des virgules |
| `DISCORD_EXEMPT_USER_IDS` | Personnes jamais touchées (toi, invités ponctuels…), séparées par des virgules |

## 7. Enregistrer les commandes admin

Une fois `.env` rempli :

```bash
pnpm discord:register
```

Résultat attendu : `Commandes enregistrées : /abonne, /ajouter, /retirer, /expirations, /stats`.
En production, tu peux aussi lancer `node dist/register-commands.js` dans le service worker.

Les commandes sont masquées aux membres qui n'ont pas la permission « Gérer les rôles ». Le bot vérifie en plus, à chaque appel, que l'auteur a le rôle `DISCORD_ADMIN_ROLE_ID`. Tu peux affiner : Paramètres du serveur → Intégrations → ton bot → autoriser uniquement ton rôle admin.

## 8. Les commandes

| Commande | Effet |
|---|---|
| `/abonne @membre` | Fiche : statut, formule, échéance, mode de renouvellement, derniers paiements |
| `/ajouter @membre jours:30 note:"Wave perso 50 000"` | Prolonge l'accès (paiement manuel, geste commercial). Variante `formule:Mensuel` |
| `/retirer @membre raison:…` | Suspend l'accès immédiatement (rôle retiré). `/ajouter` le rétablit |
| `/expirations jours:7` | Échéances à venir |
| `/stats` | Membres actifs, encaissé sur 30 jours, prévisionnel |

Chaque commande est journalisée (audit en base + salon de logs).

**Paiement reçu sur ton numéro Wave personnel** : il ne déclenche aucun webhook. Valide-le avec `/ajouter @membre formule:Mensuel note:"Wave perso, réf. …"`.

## 9. Vérification

- [ ] Le bot apparaît en ligne sur le serveur après le démarrage du worker.
- [ ] `🟢 Worker démarré` s'affiche dans `#logs-club`.
- [ ] `/stats` répond (réponse visible par toi seul).
- [ ] `/ajouter @un-compte-test jours:1` → le rôle apparaît en quelques secondes.
- [ ] `/retirer @un-compte-test` → le rôle disparaît.
- [ ] Un compte sans le rôle admin reçoit « Commande réservée à l'administration ».
