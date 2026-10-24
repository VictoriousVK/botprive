# Configuration des paiements

Deux prestataires sont intégrés derrière la même interface (`PaymentProvider`). Tu actives celui ou ceux dont tu as le compte marchand :

```
PAYMENT_PROVIDER_CARD=flutterwave            # ou none
PAYMENT_PROVIDER_MOBILE_MONEY=flutterwave    # ou wave, ou none
```

| | Flutterwave | Wave Business |
|---|---|---|
| Carte | ✅ avec renouvellement automatique | ❌ |
| Mobile Money | ✅ Orange Money, Wave (Free Money à confirmer) | ✅ Wave uniquement |
| Prélèvement automatique | ✅ carte uniquement (*payment plans*) | ❌ |
| Frais (Sénégal, à confirmer dans ton contrat) | carte 4,8 %, MoMo 2 %, HT (+18 % de TVA) | ~1 % (1,5 % selon une source) |
| Sandbox | ✅ clés de test | ⚠️ non documentée officiellement |

**Prérequis commun : une structure immatriculée (RCCM + NINEA).** Sans compte marchand, seuls les paiements manuels validés avec `/ajouter` sont possibles.

**Prix** : définis dans [`packages/core/src/config/club.ts`](../packages/core/src/config/club.ts) (`priceXof`). Le montant encaissé est toujours ce prix XOF fixe, jamais une conversion. Les valeurs actuelles (50 000 / 115 000 / 520 000 FCFA) sont **provisoires** : confirme-les.

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
```bash
pnpm flw:create-plans            # affiche ce qui sera créé
pnpm flw:create-plans --apply    # crée les 3 plans (mensuel, trimestriel, annuel) aux prix de club.ts
```
Copie les 3 lignes `FLW_PLAN_ID_…=` affichées dans `.env`. **Si tu changes un prix, crée de nouveaux plans** : un plan garde son montant, et un prélèvement d'un montant différent du prix configuré est refusé à la vérification (alerte dans les logs).

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
Dans `.env`, pointe `FLW_API_BASE_URL` et `WAVE_API_BASE_URL` vers `http://127.0.0.1:4010`, avec les clés factices de la fin de `.env.example`. Le bouton « Payer » de la page factice envoie un vrai webhook signé à l'application, qui revérifie auprès du faux serveur.

```bash
pnpm webhook:send --provider wave --checkout cos-xxx --ref VK-XXX            # webhook valide
pnpm webhook:send --provider wave --checkout cos-xxx --ref VK-XXX --forge    # signature fausse → 401
pnpm webhook:send --provider wave --checkout cos-xxx --ref VK-XXX --replay   # trop ancien → 401
```

## Règles appliquées dans tous les cas
- L'accès n'est **jamais** accordé par la page de retour du navigateur.
- Webhook non signé ou mal signé : 401, rien n'est écrit.
- Chaque paiement est revérifié serveur à serveur : statut, montant **exact**, devise, référence.
- Un même paiement ne prolonge qu'une fois, même s'il est notifié plusieurs fois.
- Un paiement en attente est revérifié automatiquement (20 min, 1 h, 6 h, 24 h), puis considéré abandonné après 48 h.
- Prélèvement carte actif : le site refuse un paiement manuel en parallèle (pas de double paiement).
- Une opération non supportée par un prestataire (ex. abonnement chez Wave) lève une erreur explicite, jamais simulée.

## Ajouter un prestataire (V2 : PayDunya, PayTech…)
Implémente l'interface `PaymentProvider` (`packages/core/src/payments/types.ts`) dans `packages/core/src/payments/providers/`, enregistre-le dans `registry.ts`, ajoute ses variables à `.env.example` et des tests sur le modèle de `webhooks.test.ts`.
