# Checklist de mise en production

À cocher ensemble avant d'ouvrir les paiements réels.

## Décisions de Victor
- [ ] Prix FCFA définitifs des 3 formules dans `packages/core/src/config/club.ts`
- [ ] Prix de l'annuel revu (900 $ > 4 × 200 $ du trimestriel)
- [ ] Horaires des lives (`liveHours`) et numéro WhatsApp affiché (`whatsappNumber`)
- [ ] Délai de grâce (3 jours) et action à l'expiration (retrait du rôle) confirmés
- [ ] Affiches et logo fournis : ajustements visuels du site
- [ ] Lien Telegram privé (`TELEGRAM_INVITE_URL`)

## Juridique (à faire valider, rien n'est garanti conforme)
- [ ] CGV complétées : raison sociale, RCCM, NINEA, adresse, TVA, médiation (`apps/web/content/legal/cgv.md`)
- [ ] Politique de remboursement arrêtée (`remboursement.md`)
- [ ] Politique de confidentialité complétée ; démarches auprès de la CDP vérifiées (`confidentialite.md`)
- [ ] Avertissement sur les risques du trading validé

## Comptes et accès
- [ ] Dépôt GitHub passé en privé
- [ ] Mot de passe de l'ancien outil Streamlit changé (son hash était public)
- [ ] Compte marchand validé (KYC) chez le prestataire n°1
- [ ] Application Discord : bot non public, intent *Server Members* actif, rôle du bot au-dessus du rôle abonné
- [ ] Domaine relié, HTTPS actif
- [ ] Domaine vérifié chez Resend (SPF, DKIM)

## Configuration
- [ ] Toutes les variables Railway renseignées (`NODE_ENV=production`, `APP_URL` en https)
- [ ] `SESSION_SECRET` de 48+ caractères aléatoires, identique sur web et worker
- [ ] URLs déclarées : redirect OAuth Discord, webhook Flutterwave (+ secret hash), webhook Wave (signing secret)
- [ ] Plans Flutterwave créés aux bons prix (`FLW_PLAN_ID_*`)
- [ ] Commandes Discord enregistrées (`/stats` répond)
- [ ] Exceptions de réconciliation renseignées (admins, modérateurs, invités)
- [ ] Sauvegardes Postgres actives, une restauration testée

## Tests en sandbox (phase 5), avec preuves (captures et logs)
- [ ] Inscription → connexion Discord → ajout au serveur si absent
- [ ] Paiement Mobile Money test → rôle attribué → message privé + email reçus
- [ ] Paiement carte avec renouvellement automatique → abonnement visible chez Flutterwave
- [ ] Webhook rejoué depuis le dashboard du prestataire → aucune double prolongation
- [ ] Annulation depuis l'espace membre → annulée chez le prestataire, accès conservé
- [ ] `/ajouter`, `/retirer`, `/abonne`, `/expirations`, `/stats` sur un compte test
- [ ] Expiration accélérée (compte test avec `/ajouter jours:1`) → grâce → retrait du rôle → repaiement → rôle rendu
- [ ] Réconciliation du lendemain : résumé dans `#logs-club` sans anomalie
- [ ] Site sur téléphone (Android + iPhone) : lisibilité, paiement, retour

## Ouverture
- [ ] Bascule des clés test → production chez le prestataire, et des plans Flutterwave de production
- [ ] Import CSV des membres actuels (`--apply`) et vérification des rôles
- [ ] Premier vrai paiement suivi en direct dans `#logs-club`
- [ ] Message aux membres : nouveau lien d'inscription, fin des paiements par WhatsApp
