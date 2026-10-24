# Informations à fournir avant la mise en production

Rien de ce qui suit ne bloque le développement en mode test. **Ne colle jamais un secret (clé, token, mot de passe) dans un chat** : les secrets vont dans les variables d'environnement (Railway ou `.env`).

## 1. Administratif (bloquant pour encaisser réellement)
- [ ] Forme juridique choisie (entreprise individuelle conseillée pour démarrer) — [guide](guide-administratif.md)
- [ ] **RCCM** et **NINEA** obtenus
- [ ] Compte bancaire pour les versements du prestataire
- [ ] Avis d'un comptable sur le régime fiscal ; avis d'un juriste sur les futurs « signaux swing Gold »

## 2. Paiement
- [ ] Prestataire choisi : Flutterwave (recommandé), PayDunya, ou les deux — [comparatif](comparatif-prestataires.md)
- [ ] **Dès maintenant, sans RCCM** : compte Flutterwave individuel en mode test, et/ou application PayDunya en mode test → clés de test dans les variables d'environnement
- [ ] Après les tests en sandbox : KYC validé chez le prestataire, clés de production
- [ ] Choix de qui paie les frais du prestataire (toi ou le client)
- [ ] Confirmation que le prélèvement automatique fonctionne en FCFA (test en sandbox ensemble)

## 3. Tarifs (dans le tableau de bord)
- [ ] Prix encaissés en FCFA : mensuel, trimestriel, annuel (`/admin/tarifs`)
- [ ] Décision sur l'annuel : affiché 900 $, plus cher que 4 trimestres (4 × 200 $ = 800 $)
- [ ] **Validation des tarifs** (bouton dans `/admin/tarifs`)

## 4. Lives et contenu
- [ ] Horaires du mardi, mercredi et vendredi (`/admin/lives`)
- [ ] Affiches du Live Club dans `assets/affiches/` (voir `assets/affiches/LISEZMOI.md`)
- [ ] Logo (SVG ou PNG transparent), si tu veux remplacer le logo texte
- [ ] Numéro WhatsApp à afficher (actuellement +221 76 413 99 46, celui de l'affiche)
- [ ] Lien Telegram dans la variable `TELEGRAM_INVITE_URL` (le lien que tu m'as donné ; volontairement absent du code, car le dépôt est public)
- [ ] Visibilité du lien Telegram : publique (par défaut) ou réservée aux membres actifs (`/admin/telegram`). Attention, en mode public toute personne peut rejoindre le groupe et voir les replays

## 5. Discord (dans les variables d'environnement)
- [ ] Application Discord créée, bot invité, intent « Server Members » activé — [guide](guide-discord.md)
- [ ] `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_BOT_TOKEN`
- [ ] IDs : serveur, rôle abonné, rôle admin, salon de logs
- [ ] `ADMIN_DISCORD_IDS` : ton identifiant Discord (accès au tableau de bord)
- [ ] Exceptions : rôles et membres à ne jamais toucher (modérateurs, invités spéciaux)
- [ ] Un compte Discord de test (pour vérifier rôles et messages en mode observation)

## 6. Membres existants
- [ ] Fichier CSV de tes membres actuels — [guide](guide-import-membres.md) (export du rôle depuis le tableau de bord, puis formule et date de fin à compléter)
- [ ] **Ton autorisation explicite** pour passer Discord en mode réel, après vérification de l'import

## 7. Domaine et emails
- [ ] Nom de domaine choisi et acheté — [options et coûts](guide-domaine.md)
- [ ] Compte Resend + domaine vérifié (SPF, DKIM) pour les emails

## 8. Juridique (à faire valider)
- [ ] CGV complétées : raison sociale, RCCM, NINEA, adresse, TVA, médiation
- [ ] Politique de remboursement arrêtée
- [ ] Politique de confidentialité ; démarches éventuelles auprès de la CDP

## 9. Hébergement
- [ ] Compte Railway (ou VPS) et dépôt GitHub passé en **privé**
- [ ] Mot de passe de l'ancien outil Streamlit changé (son hash a été public)
