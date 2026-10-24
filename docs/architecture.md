# Architecture

## Vue d'ensemble

```
             Navigateur (mobile)                         Prestataires
                    │                              Flutterwave · Wave Business
                    ▼                                  │            ▲
   ┌──────────────────────────────────┐   webhooks     │            │ vérification
   │ apps/web (Next.js)               │◀───────────────┘            │ serveur à serveur
   │ site · OAuth Discord · checkout  │─────────────────────────────┘
   │ espace membre · /api/webhooks/*  │
   └───────────────┬──────────────────┘
                   │ écrit l'état + des tâches (même transaction)
                   ▼
           ┌───────────────┐
           │  PostgreSQL   │  membres · abonnements · paiements · périodes
           │               │  webhooks · tâches · rappels · audit · sessions
           └───────▲───────┘
                   │ lit les tâches (SKIP LOCKED), passages planifiés chaque minute
   ┌───────────────┴──────────────────┐
   │ apps/worker (process permanent)  │──▶ Discord (REST) : rôles, messages privés, salon de logs
   │ bot discord.js · tâches · rappels│──▶ Resend : emails
   │ expirations · réconciliation     │
   └──────────────────────────────────┘
```

- **Toute la logique métier** est dans `packages/core`, sans dépendance au framework : le site et le worker l'appellent, les tests aussi.
- **Le site n'appelle jamais Discord pour les rôles** : il enregistre en base une tâche `sync_access`. Le worker l'exécute et la réessaie si Discord est indisponible (outbox transactionnelle).
- **Aucun état en mémoire** : tâches, échéances et rappels sont en base. On peut redémarrer le worker à tout moment : le premier passage rattrape ce qui a été manqué.

## Choix techniques

| Choix | Pourquoi |
|---|---|
| Monorepo pnpm TypeScript | Un seul langage, types partagés entre site, worker et tests |
| Next.js 16 (App Router), mode `standalone` | Site + API + webhooks dans un seul service ; image Docker légère |
| discord.js v14 + REST | Gateway pour les commandes et les arrivées ; REST (limites de débit gérées) pour les rôles |
| PostgreSQL + Drizzle | Contraintes d'unicité et verrous (`FOR UPDATE`, `SKIP LOCKED`) pour l'idempotence et la file de tâches |
| File de tâches maison en base | Persistante, testable avec une horloge simulée, aucune infrastructure supplémentaire |
| Railway pour tout (au lieu de Vercel + Railway) | Le plan gratuit de Vercel interdit l'usage commercial (Pro à 20 $/mois). Tout sur Railway coûte environ 10 à 15 $/mois, sur un réseau privé |
| Flutterwave API v3 | Les *payment plans* (prélèvement carte) ne sont documentés qu'en v3 |
| PayDunya (facture avec redirection) | Carte et Mobile Money ; pas d'abonnement : renouvellement assisté |
| Zod, rate limiting, contrôle d'origine | Validation des entrées et protection des endpoints publics |

## Réglages modifiables et garde-fous

| Réglage (table `settings`, écran `/admin`) | Défaut |
|---|---|
| Prix des formules (FCFA encaissé, $ affiché, badge, accroche, active), plan Flutterwave | **Aucun prix FCFA** : formules non achetables tant qu'ils ne sont pas saisis |
| Validation des tarifs | Non validés (obligatoire en `PAYMENT_MODE=live`) |
| Horaires des lives | MAR / MER / VEN, horaire « à venir » |
| Telegram | lien repris de `TELEGRAM_INVITE_URL` au premier démarrage, public |
| Mode Discord | **Observation** : aucun rôle modifié, aucun message aux membres réels (sauf comptes de test) |

- Changer un prix annule la validation et détache le plan Flutterwave (un plan garde son montant). Le montant du prélèvement est figé sur l'abonnement (`recurring_amount`).
- `PAYMENT_MODE=test` : un prestataire configuré en production (clé réelle, API réelle) est écarté au démarrage.
- Les réglages sont lus avec un cache de 10 s : le worker voit une modification du tableau de bord en moins de 10 s.

## Modèle de données

| Table | Contenu |
|---|---|
| `members` | Compte Discord (ID unique), pseudo, email, téléphone, drapeau d'exception |
| `subscriptions` | **Une ligne par membre**, qui évolue : formule, statut, mode de renouvellement, période en cours, jour d'ancrage, fin de grâce, abonnement chez le prestataire |
| `payments` | Chaque tentative : notre référence unique, prestataire, montant XOF, statut, identifiant de transaction (unique par prestataire) |
| `subscription_periods` | Historique des périodes (paiement, ajout admin, import). `payment_id` unique : un paiement ne prolonge qu'une fois |
| `webhook_events` | Événements reçus, unicité `(prestataire, clé d'événement)` |
| `jobs` | File de tâches : type, charge utile, essais, prochaine exécution, verrou |
| `reminders` | Rappels envoyés, unicité `(abonnement, fin de période, J-x)` |
| `audit_logs` | Journal d'audit (système, admin, membre, prestataire) |
| `sessions` | Empreinte SHA-256 des jetons de session |
| `settings` | Réglages du tableau de bord (JSON validé par schéma), avec auteur et date |

Toutes les dates sont en `timestamptz` (UTC). Affichage en `Africa/Dakar` (UTC+0 toute l'année).

## Machine à états

```
pending_payment ──payment_confirmed──▶ active ──(J-3)──▶ renewal_due ──(échéance)──▶ grace_period ──(fin de grâce)──▶ expired
                                        ▲                     │                          │                              │
                                        └──payment_confirmed──┴──────────────────────────┴──────────payment_confirmed──┘
canceled   : renouvellement annulé, accès jusqu'à la fin de la période payée, puis expired (sans grâce)
refunded   : paiement de la période en cours remboursé, accès retiré
suspended  : suspendu par l'admin (/retirer), accès retiré ; /ajouter le rétablit
```

Table complète : [`packages/core/src/state-machine.ts`](../packages/core/src/state-machine.ts). Toute transition absente est refusée (`InvalidTransitionError`, testée).

| Statut | Rôle Discord | Rappels |
|---|---|---|
| active, renewal_due | oui | oui (J-3, J-1, J0) |
| grace_period | oui | message « période de grâce » |
| canceled | oui jusqu'à la fin | non |
| expired, refunded, suspended, pending_payment | non | — |

Cas particuliers retenus :
- **Annulation pendant la grâce** : le statut reste `grace_period`, le mode passe en manuel. Le membre peut encore payer par Mobile Money.
- **Prélèvement carte arrivé après une annulation** (événements dans le désordre) : la période est prolongée, l'annulation est conservée.
- **Paiement d'un membre suspendu** : la période est enregistrée, l'accès n'est pas rétabli, une alerte est postée dans les logs.

## Calcul des périodes

- `fin = activation + durée` en mois calendaires, **jour d'ancrage** conservé : 31 janv. → 28/29 févr. → 31 mars.
- **Renouvellement anticipé** ou **pendant la grâce** : la nouvelle période part de la fin de la précédente.
- **Après expiration** : nouvelle période à partir du paiement, nouveau jour d'ancrage.
- **`/ajouter N jours`** : prolonge la période ; le jour d'ancrage suit la nouvelle date de fin.

## Flux de paiement

1. Le membre choisit formule et moyen de paiement. Pour le prélèvement automatique, la case de consentement est obligatoire (vérifiée côté serveur).
2. `startCheckout` crée le paiement `pending` avec une référence unique, puis la session chez le prestataire, et programme une re-vérification à +20 min (filet de sécurité si le webhook se perd).
3. Le prestataire redirige vers `/paiement/retour`. Cette page **affiche** le statut, elle n'accorde rien.
4. Webhook `/api/webhooks/{prestataire}` :
   - signature vérifiée (Wave : HMAC horodaté, anti-rejeu 5 min ; Flutterwave : `verif-hash`). Sinon 401, rien n'est écrit ;
   - événement enregistré avec une clé unique. Un doublon déjà traité répond 200 sans effet ;
   - **re-vérification serveur à serveur** : statut, montant, devise, référence ;
   - transaction : période créée (unique par paiement), statut mis à jour, tâches de rôle, notifications et log.
5. Prélèvement récurrent carte : nouvelle transaction Flutterwave, rattachée à l'abonnement (identifiant d'abonnement, sinon email + plan).

L'ordre d'arrivée des événements n'a pas d'importance : l'état final dépend de la vérification serveur, et un succès n'est jamais rétrogradé.

## Synchronisation Discord

- Principe de l'**état désiré** : `sync_access(membre)` compare le statut en base avec le rôle réel, puis ajoute ou retire. C'est idempotent et rejouable à volonté.
- Erreurs Discord transitoires (réseau, 429, 5xx) : la tâche est réessayée (15 s, 30 s, 1 min… plafond 1 h, jusqu'à 30 essais).
- Arrivée d'un membre sur le serveur : son rôle lui est rendu s'il est abonné.
- **Exceptions**, jamais touchées : IDs de `DISCORD_EXEMPT_USER_IDS`, rôles de `DISCORD_EXEMPT_ROLE_IDS` et le rôle admin, les bots, le drapeau `reconcile_exempt`.
- Expiration : retrait du rôle par défaut ; expulsion si `EXPIRY_ACTION=kick`.
- **Mode observation** : le changement est calculé, journalisé (`discord.role_*_simulated`) et annoncé dans le salon de logs, mais rien n'est modifié. La réconciliation liste les retraits et attributions qui auraient eu lieu.

## Tâches planifiées (worker)

Chaque minute :
1. Récupération des tâches verrouillées par un worker arrêté (verrou > 10 min).
2. Transitions liées au temps (renewal_due, grace_period, expired), avec rattrapage.
3. Rappels dus. Si plusieurs sont dus en même temps, seul le plus proche de l'échéance part.
4. Programmation de la réconciliation du jour (une seule par jour, à partir de 04:00 UTC).

Réconciliation quotidienne : re-vérification des paiements restés en attente, transitions, retrait des rôles sans abonnement, réparation des abonnés sans rôle, liste des abonnés absents du serveur, résumé dans le salon de logs.

## Notifications

- Message privé Discord **et** email, en deux tâches séparées : l'échec de l'un ne renvoie pas l'autre.
- Prélèvement carte actif : **jamais de lien de paiement manuel** (évite le double paiement), seulement un avis.
- Liens de renouvellement en 1 clic : jeton signé HMAC (membre + formule), valable 10 jours.
- Un message devenu caduc (membre renouvelé entre-temps) n'est pas envoyé.

## Tests

`pnpm test` : tests sur une vraie base Postgres jetable, avec un faux serveur Flutterwave / Wave / PayDunya (HTTP réel) et un faux Discord.

| Exigence du cahier des charges | Fichier |
|---|---|
| 1. Calcul des dates | `packages/core/test/dates.test.ts` |
| 2. Machine à états, transitions interdites | `packages/core/test/state-machine.test.ts` |
| 3. Webhooks : valide, doublon, falsifié, désordre | `packages/core/test/webhooks.test.ts` |
| 4. Paiement pendant une panne Discord | `packages/core/test/lifecycle.test.ts` |
| 5. Expiration, grâce, retrait, restauration | `packages/core/test/lifecycle.test.ts` |
| 6. Redémarrage du worker | `packages/core/test/lifecycle.test.ts` |
| 7. Espace d'un autre membre refusé | `packages/core/test/access-and-reconciliation.test.ts` |
| 8. Réconciliation et exceptions | `packages/core/test/access-and-reconciliation.test.ts` |
| Commandes admin | `apps/worker/test/admin-commands.test.ts` |
| Réglages, tarifs, mode test, mode observation, aperçu d'import | `packages/core/test/settings-and-guards.test.ts` |
| PayDunya | `packages/core/test/paydunya.test.ts` |
