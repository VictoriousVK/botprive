# Configuration des paiements

Trois prestataires sont intégrés derrière la même interface (`PaymentProvider`). Tu actives celui ou ceux dont tu as le compte :

```
PAYMENT_MODE=test                            # test (défaut) ou live
PAYMENT_PROVIDER_CARD=flutterwave            # flutterwave, paydunya ou none
PAYMENT_PROVIDER_MOBILE_MONEY=flutterwave    # flutterwave, paydunya, wave ou none
```

| | Flutterwave | PayDunya | Wave Business |
|---|---|---|---|
| Carte | ✅ avec prélèvement automatique | ✅ sans prélèvement automatique | ❌ |
| Mobile Money | ✅ Orange Money, Wave (Free Money à confirmer) | ✅ Orange Money, Wave, Free Money | ✅ Wave uniquement |
| Prélèvement automatique | ✅ carte uniquement (FCFA à confirmer en sandbox) | ❌ renouvellement assisté | ❌ |
| Sandbox | ✅ clés de test | ✅ mode test | ⚠️ non documentée (faux serveur local uniquement en mode test) |
| Sans RCCM | ✅ en mode test | ⚠️ à confirmer avec PayDunya | ❌ |

Choix détaillé : [comparatif-prestataires.md](comparatif-prestataires.md).

**Mode test (`PAYMENT_MODE=test`, par défaut)** : aucun encaissement réel n'est possible. Un prestataire configuré avec une clé réelle (Flutterwave sans `_TEST`, PayDunya sur l'API de production, Wave sur l'API réelle) est **écarté automatiquement** (alerte dans le tableau de bord et les logs). Un bandeau « mode test » s'affiche sur le site.
**Mode réel (`PAYMENT_MODE=live`)** : exige des **tarifs validés** dans `/admin/tarifs`.

**Prix** : saisis dans le tableau de bord (`/admin/tarifs`), jamais dans le code. Le montant encaissé est toujours ce prix FCFA fixe, sans conversion. Aucun prix n'est prédéfini.

---|---|---|
| Carte | ✅ avec renouvellement automatique | ❌ |
| Mobile Money | ✅ Orange Money, Wave (Free Money à confirmer) | ✅ Wave uniquement |
| Prélèvement automatique | ✅ carte uniquement (*payment plans*) | ❌ |
| Frais (Sénégal, à confirmer dans ton contrat) | carte 4,8 %, MoMo 2 %, HT (+18 % de TVA) | ~1 % (1,5 % selon une source) |
| Sandbox | ✅ clés de test | ⚠️ non documentée officiellement |

**Prérequis commun : une structure immatriculée (RCCM + NINEA).** Sans compte marchand, seuls les paiements manuels validés avec `/ajouter` sont possibles.

---

## Flutterwave (prestataire n°1 recommandé)

### Compte
1. Crée un compte sur flutterwave.com (pays : Sénégal) et complète le KYC : documents d'immatriculation, pièce d'identité, attestation fiscale, coordonnées bancaires.
2. En attendant la validation, travaille en **mode test** (bascule dans le dashboard).

### Clés et webhook
1. Dashboard → **Settings → API Keys** : copie la *Secret Key* (`FLWSECK_TEST-…` en test) → `FLW_SECRET_KEY`.
2. Dashboard → **Settings → Webhooks** :
   - URL : `https://TON-DOMAINE/api/webhooks/flutterwave`
   - **Secret hash** : invente une longue valeur aléatoire (`openssl rand -hex 32`), saisis-la ici **et** dans `FLW_WEBHOOK_HASH`.
   - Active les réessais de webhook et les webhooks des transactions échouées si les options existent.
3. **Frais** : par défaut, Flutterwave les fait payer au client. Pour que le prix affiché soit le prix payé, mets-les à ta charge dans les paramètres du compte.

### Plans de prélèvement automatique (carte)
Dans `/admin/tarifs`, une fois le prix FCFA saisi : bouton **« Créer le plan … »**. Le plan est créé chez Flutterwave au prix actuel et rattaché à la formule (équivalent en ligne de commande : `pnpm flw:create-plans --apply`).
**Si tu changes un prix**, le plan est détaché automatiquement : un plan garde son montant. Crée alors un nouveau plan. Les abonnés déjà en prélèvement automatique gardent leur montant d'origine.

### Points à confirmer en sandbox (phase 5)
| Point | Comment vérifier |
|---|---|
| Option Mobile Money (`FLW_MOBILE_MONEY_OPTION=mobilemoneyfranco`) | Lancer un paiement Mobile Money : Orange Money et Wave Sénégal doivent être proposés |
| Free Money | Présent dans les pages d'aide, absent de la doc API d'encaissement |
| Champ `plan` dans la vérification d'un prélèvement récurrent | Rattachement automatique du prélèvement mensuel. Sinon, alerte « prélèvement sans abonné » dans les logs |
| Recherche d'abonnement `GET /v3/subscriptions?transaction_id=` | L'identifiant d'abonnement doit apparaître dans `/abonne` |
| Annulation `PUT /v3/subscriptions/:id/cancel` | Bouton « Annuler le renouvellement » → statut annulé dans le dashboard Flutterwave |
| Webhook `subscription.cancelled` | Un ancien rapport indique qu'il n'est pas toujours envoyé pour les annulations par API. Ce n'est pas bloquant : notre état change dès la réponse de l'API |

---

## PayDunya (renouvellement assisté)

### Compte et clés de test
1. Crée un compte sur paydunya.com, puis **Intégrez nos API → Créer une application**, en **mode test**.
2. Copie les trois clés de test : `PAYDUNYA_MASTER_KEY`, `PAYDUNYA_PRIVATE_KEY` (`test_private_…`), `PAYDUNYA_TOKEN`.
3. Laisse `PAYDUNYA_API_BASE_URL` vide : la sandbox est utilisée en mode test, l'API réelle en mode live.
4. Choisis PayDunya pour le Mobile Money (`PAYMENT_PROVIDER_MOBILE_MONEY=paydunya`) et/ou la carte (`PAYMENT_PROVIDER_CARD=paydunya`, sans prélèvement automatique).
5. Pour tester un paiement, crée des **clients fictifs** dans le tableau de bord PayDunya (mode test).

L'URL de notification (`callback_url`) est envoyée automatiquement à chaque facture : `https://TON-DOMAINE/api/webhooks/paydunya`.
**Vérification** : le `hash` de l'IPN (SHA-512 de la clé principale) est contrôlé, puis la facture est relue par `GET /checkout-invoice/confirm/{token}` (statut, montant, référence). Sans prélèvement automatique, les membres PayDunya reçoivent des rappels avec lien de paiement.
**À confirmer en sandbox** : format exact de l'IPN, paramètre `channels` (restriction des moyens de paiement), montants renvoyés par `confirm`.

---

## Wave Business (Mobile Money, frais réduits)

### Compte
Ouvre un compte **marchand** Wave Business (RCCM, NINEA, pièce d'identité, justificatif d'adresse, RIB pro selon les sources). Un numéro Wave **personnel** ne déclenche ni API ni webhook : il reste réservé aux validations manuelles.

### Clés et webhook
1. Portail Wave Business → **Développeurs** → crée une clé API avec l'accès **Checkout** → `WAVE_API_KEY`. Elle ne s'affiche qu'une fois.
2. **Webhooks** → ajoute `https://TON-DOMAINE/api/webhooks/wave`, événement `checkout.session.completed`, mode de sécurité **Signing secret** (pas « Shared secret ») → `WAVE_WEBHOOK_SECRET`.
3. Puis `PAYMENT_PROVIDER_MOBILE_MONEY=wave`.

Vérification : en-tête `Wave-Signature: t=…,v1=…`, HMAC-SHA256 (horodatage + corps brut), requêtes de plus de 5 minutes refusées, puis lecture de la session via `GET /v1/checkout/sessions/:id`.

### Tester sans sandbox
La doc officielle ne mentionne pas de sandbox. Pour un test réel à petit montant : sur un déploiement de test, mets temporairement `priceXof: 100` au mensuel, paie 100 FCFA, vérifie le rôle, puis rembourse depuis le portail Wave.

---

## Développer sans compte : le faux serveur

```bash
pnpm mock:providers   # http://127.0.0.1:4010 : imite les API Flutterwave et Wave
```
Dans `.env`, pointe `FLW_API_BASE_URL`, `WAVE_API_BASE_URL` (`http://127.0.0.1:4010`) et `PAYDUNYA_API_BASE_URL` (`http://127.0.0.1:4010/sandbox-api/v1`) vers le faux serveur, avec les clés factices de la fin de `.env.example`. Le bouton « Payer » de la page factice envoie un vrai webhook signé à l'application, qui revérifie auprès du faux serveur.

```bash
pnpm webhook:send --provider wave --checkout cos-xxx --ref VK-XXX            # webhook valide
pnpm webhook:send --provider wave --checkout cos-xxx --ref VK-XXX --forge    # signature fausse → 401
pnpm webhook:send --provider wave --checkout cos-xxx --ref VK-XXX --replay   # trop ancien → 401
pnpm webhook:send --provider paydunya --token test_xxx --ref VK-XXX          # IPN PayDunya
```

## Règles appliquées dans tous les cas
- L'accès n'est **jamais** accordé par la page de retour du navigateur.
- Webhook non signé ou mal signé : 401, rien n'est écrit.
- Chaque paiement est revérifié serveur à serveur : statut, montant **exact**, devise, référence.
- Un même paiement ne prolonge qu'une fois, même s'il est notifié plusieurs fois.
- Un paiement en attente est revérifié automatiquement (20 min, 1 h, 6 h, 24 h), puis considéré abandonné après 48 h.
- Prélèvement carte actif : le site refuse un paiement manuel en parallèle (pas de double paiement).
- Une opération non supportée par un prestataire (ex. abonnement chez Wave) lève une erreur explicite, jamais simulée.

## Ajouter un prestataire (PayTech…)
Implémente l'interface `PaymentProvider` (`packages/core/src/payments/types.ts`) dans `packages/core/src/payments/providers/`, enregistre-le dans `registry.ts`, ajoute ses variables à `.env.example` et des tests sur le modèle de `webhooks.test.ts`.
