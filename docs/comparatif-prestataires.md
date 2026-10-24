# Flutterwave ou PayDunya ?

> Recherche du 24/10/2026 dans les pages officielles et des sources tierces (signalées). Les deux prestataires
> sont **intégrés et testés contre un faux serveur**. Aucun n'a encore été testé en sandbox réelle.

## En résumé

| | Flutterwave | PayDunya |
|---|---|---|
| Statut au Sénégal | Agréé établissement de paiement par la BCEAO (Flutterwave Sénégal, EP.SN.004/2025, 22/05/2025) | Société sénégalaise. DUNYA Digital Payment SA est citée parmi les établissements de paiement agréés par la BCEAO (Agence Ecofin, 2025) |
| Commencer sans RCCM | ✅ compte individuel, **en mode test uniquement** | ⚠️ compte Business : RCCM + NINEA + pièce d'identité demandés pour l'encaissement |
| Documents pour encaisser | Documents d'immatriculation, pièce d'identité (original couleur), attestation fiscale, coordonnées bancaires | RCCM, NINEA, photo de la pièce d'identité et photo de la personne (vérification sur le site web) |
| Carte bancaire | ✅ | ✅ (page hébergée ; le paiement carte « direct » SOFTPAY est réservé aux entreprises certifiées PCI-DSS) |
| Mobile Money Sénégal | Orange Money, Wave (Free Money cité par les pages d'aide, à confirmer) | Orange Money, Wave, Free Money |
| **Prélèvement automatique** | ✅ **carte uniquement** (*payment plans*). Le FCFA pour les plans reste **à confirmer en sandbox**. Solution de repli : carte enregistrée (tokenisation) | ❌ rien de documenté. Renouvellement assisté : lien de paiement ou « demande de paiement » par SMS ou email à chaque échéance |
| Frais (indicatifs) | Carte 4,8 %, Mobile Money 2 %, hors TVA (+18 %) ; payés par le client par défaut, paramétrable | 3 % + 100 FCFA par transaction sous 10 M FCFA/mois (2,5 % + 100 au-delà) ; les CGU mentionnent 20 000 FCFA/mois de frais de gestion (à vérifier) |
| Sandbox | ✅ clés de test | ✅ mode test avec clients fictifs |
| Remboursement par API | ✅ | ❌ non documenté (depuis le tableau de bord PayDunya) |
| Sécurité des notifications | Secret `verif-hash` (pas une signature du contenu) | `hash` = SHA-512 de la clé principale (valeur constante) |

Dans les deux cas, notre système **revérifie chaque paiement auprès de l'API** avant d'accorder l'accès : une notification seule ne suffit jamais.

Frais sur un paiement de 50 000 FCFA (exemple) :

| | Calcul | Total |
|---|---|---|
| Flutterwave, carte | 4,8 % = 2 400 FCFA HT | 2 832 FCFA TTC |
| Flutterwave, Mobile Money | 2 % = 1 000 FCFA HT | 1 180 FCFA TTC |
| PayDunya | 3 % + 100 FCFA | 1 600 FCFA (hors éventuels frais mensuels) |

## Abonnements récurrents : ce qui est réellement possible

- **Prélèvement automatique : seulement par carte, et seulement avec Flutterwave.** Le client donne son accord (case obligatoire sur le site) et Flutterwave débite la carte à chaque échéance. Notre système rattache chaque prélèvement, prolonge l'accès et n'envoie qu'un avis, jamais de lien de paiement (pas de double paiement).
- **Mobile Money (Wave, Orange Money, Free Money), quel que soit le prestataire :** aucun prélèvement automatique, le client doit valider chaque paiement sur son téléphone. Notre système fait du **renouvellement assisté** : rappels J-3, J-1 et J0 (Discord + email) avec un lien de paiement pré-rempli, puis prolongation automatique dès la confirmation.
- **PayDunya, même par carte :** renouvellement assisté uniquement.

## Recommandation

1. **Flutterwave en prestataire principal.** C'est le seul qui permette un vrai prélèvement automatique par carte, et le seul que tu peux **ouvrir dès aujourd'hui sans RCCM** (mode test). Il couvre aussi Orange Money et Wave.
2. **PayDunya en alternative ou en complément pour le Mobile Money**, si les tests montrent que Flutterwave couvre mal Free Money ou Wave, ou si ses frais Mobile Money conviennent mieux. Il suffit de changer `PAYMENT_PROVIDER_MOBILE_MONEY=paydunya`.
3. **Wave Business en direct, plus tard**, pour réduire les frais Wave (environ 1 %) une fois l'entreprise immatriculée.

## Ce que tu peux faire dès maintenant (sans RCCM)

1. Crée un compte Flutterwave (pays : Sénégal, compte individuel) et récupère les **clés de test** (`FLWSECK_TEST-…`).
2. Crée un compte PayDunya et une application en **mode test**, puis récupère les clés de test.
3. Envoie-moi seulement la confirmation que c'est fait (**jamais les clés dans le chat**) : on les met dans les variables d'environnement et on lance les tests en sandbox réelle (phase 5).

## Points à confirmer en sandbox
- Flutterwave : plans de prélèvement en FCFA, option `mobilemoneyfranco`, présence du champ `plan` lors des prélèvements récurrents, annulation par API.
- PayDunya : format exact de l'IPN (formulaire ou JSON), paramètre `channels` pour restreindre les moyens de paiement, montants renvoyés par `confirm`.

## Sources
- [Registre BCEAO des établissements de paiement (février 2026)](https://www.bceao.int/sites/default/files/2026-03/LISTE%20DES%20ETABLISSEMENTS%20DE%20PAIEMENT%20AGR%C3%89%C3%89S%20DANS%20L%E2%80%99UMOA%20au%2031%20janvier%202026.pdf)
- [Agence Ecofin : fintech agréées par la BCEAO](https://www.agenceecofin.com/actualites-finance/2705-128730-paiements-numeriques-dans-l-umoa-9-fintech-deja-agreees-par-la-bceao)
- [Flutterwave : conditions au Sénégal](https://flutterwave.com/sn/support/general/what-are-the-requirements-for-using-flutterwave) · [Tarifs Sénégal](https://flutterwave.com/sn/pricing) · [Payment plans (v3)](https://developer.flutterwave.com/v3.0/docs/payment-plans-1) · [Tokenisation](https://developer.flutterwave.com/docs/recurring-payments/tokenization)
- [PayDunya : documentation](https://developers.paydunya.com/doc/EN/introduction) · [Demande de paiement](https://developers.paydunya.com/doc/FR/dmp) · [Sandbox](https://developers.paydunya.com/doc/FR/sandbox_softpay) · [FAQ](https://paydunya.com/faq) · [Frais](https://ecommerce.paydunya.com/pricing) · [CGU](https://paydunya.com/terms-of-service)
