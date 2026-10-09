# Présenter le MVP à un client

Une commande lance la plateforme complète sur des **données fictives** : site, inscription, espace
de trading, Coach, garde-fou, analyse ICT, Mentor, administration et console. Tout est simulé :
prix simulés, comptes et trades inventés pour l'exemple, aucun ordre, aucun paiement réel. Un
bandeau le dit en haut de chaque page. Les données de démonstration vivent dans `var/demo`, à part
des vraies données, qu'elles ne touchent jamais.

---

## 1. Ce que montre le MVP

| Parcours | Dans la démo | État |
|---|---|---|
| Site, offres, paiement Wave manuel | oui | prêt |
| Inscription en deux temps, accueil guidé en 4 étapes | oui, en direct | prêt |
| Journal : import MT5, statistiques par killzone, notes par trade | oui (FTMO 100K fictif) | prêt |
| Coach IA : écarts au plan, leçons à valider | oui | prêt ; texte par les règles sans clé Anthropic, rédigé par l'IA avec |
| Garde-fou prop firm : limites, taille de position | oui (FTMO 100K, Topstep 50K) | prêt ; profils « à vérifier » |
| Analyse ICT : FVG, liquidité, carte de décision | oui, sur prix simulés | prêt ; prix réels avec MT5 |
| Mentor : réponses sourcées | oui | prêt ; les vidéos de la formation restent à ajouter |
| Administration : paiements, membres, alertes Telegram | oui | prêt |
| Import des relevés TopstepX / Tradovate | non | à faire (il faut un export d'exemple) |
| Nom de domaine, HTTPS, mise en ligne | non | à faire |
| Paiement Wave automatique, copytrading réel | non | hors MVP (Wave Business ; cadre légal) |

---

## 2. Lancer la démo

Il faut **Python 3.11 ou plus récent** (https://www.python.org/downloads/, case « Add python.exe to
PATH »). Pas besoin de MetaTrader 5.

**Windows**, dans le dossier du projet (Shift + clic droit → « Ouvrir dans le terminal ») :

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # une seule fois, répondez O
.\deploy\windows\demo.ps1
```

**Mac / Linux** :

```bash
python3 -m venv .venv && .venv/bin/pip install -e ".[web,saas,research]"
.venv/bin/python -m hedgefund.web demo
```

La fenêtre affiche les identifiants (aussi copiés dans `var/demo/IDENTIFIANTS-DEMO.txt`) :

- **l'opérateur** `demo` : `/console` puis `/admin/` ;
- **Awa (démo)**, offre Quant Elite : deux comptes (FTMO 100K, Topstep 50K), une quarantaine de
  trades fictifs sur sept semaines, avec les erreurs que le Coach sait repérer (surtrading, trade de
  revanche, lot doublé après une perte, trades hors killzone, sorties précoces) ;
- **Moussa (démo)**, offre gratuite : un paiement Wave déclaré, en attente de validation.

Les mots de passe sont tirés au hasard à la création : il n'existe toujours aucun compte par défaut.

Ouvrez ensuite **http://127.0.0.1:8000**. `Ctrl+C` arrête la démo ; la relancer reprend les mêmes
données. `.\deploy\windows\demo.ps1 -Reset` repart de zéro, avec de nouveaux mots de passe.

**Coach et Mentor rédigés par l'IA (facultatif)** : copiez `deploy\windows\env.example.ps1` en
`.env.ps1` à la racine du projet et renseignez `ANTHROPIC_API_KEY` (jamais dans le dépôt ni dans une
conversation). Sans clé, tout
fonctionne avec des textes rédigés par les règles, sur les mêmes chiffres.

---

## 3. Le déroulé (15 minutes)

Dites-le dès l'ouverture : **« Tout ce que vous allez voir est fictif : les comptes, les trades et
les prix. Ce sont les outils que je vous montre, pas des résultats. »** Le bandeau jaune le rappelle.

1. **Le site** (1 min). Accueil, formation ICT, offres et paiement Wave.
2. **L'inscription, en direct** (3 min). « Commencer gratuitement » : créez un compte devant le client
   (une adresse du type `client.demo@example.com`). Montrez la jauge du mot de passe, puis l'accueil
   guidé : prop firm **Topstep**, taille **50K**. Les règles de la firme s'affichent (avec « À
   vérifier »). Au plan de risque, bougez le curseur : les montants se recalculent, et un
   avertissement apparaît si la limite du jour dépasse celle de la firme.
3. **Le paiement et l'alerte** (2 min, si Telegram est réglé : voir §5). Avec ce nouveau compte :
   Offres → Starter → Payer avec Wave → saisir un faux identifiant de transaction. Le téléphone
   reçoit l'alerte Telegram. Dans `/admin/` → Paiements, cliquez sur **Valider** : l'accès s'active.
4. **Le tableau de bord d'Awa** (2 min). Déconnectez-vous, connectez-vous avec Awa. Performance sur
   30 jours, comportements repérés, résultats par killzone : le client voit tout de suite quelles
   séances rapportent et lesquelles coûtent.
5. **Le Coach** (2 min). Coach → période **30 jours** → Lancer la revue. Les étapes défilent, puis
   le verdict : chiffres, écarts au plan, leçons proposées. Acceptez-en une. Message clé : **les
   chiffres sont calculés par le moteur, l'IA ne fait que les expliquer ; rien n'est inventé.**
6. **Le garde-fou** (2 min). Risque → compte FTMO 100K : marge du jour, plancher, objectif. Passez
   au compte Topstep 50K, puis dans le calculateur : `MNQ`, entrée 20000, stop 19975 → nombre de
   contrats autorisé, plafond de la firme compris.
7. **L'analyse ICT et le Mentor** (2 min). Analyse ICT → Analyser (sur prix simulés en démo).
   Mentor → « Qu'est-ce qu'un fair value gap ? » : réponse avec ses sources.
8. **La suite** (1 min). Ce qui reste avant la mise en ligne (§7), et les prochaines étapes.

---

## 4. Ce qu'il faut dire, et ne pas dire

- Les chiffres de la démo ne sont **jamais** des résultats : ce sont des données d'exemple.
- **Aucune promesse de gain**, aucun signal. Le SaaS aide à respecter un plan et des règles.
- Le SaaS est **en lecture seule** sur les comptes de trading : il ne passe aucun ordre. Les robots
  tournent dans la console, derrière trois verrous, en démo d'abord.
- Les règles des prop firms sont **à vérifier** sur leur règlement officiel avant la mise en ligne.
- Les coûts d'IA sont plafonnés par offre (de 0,5 $ à 30 $ par membre et par mois, `config/saas.yaml`).

---

## 5. La veille de la présentation

- Relancez une démo neuve : `.\deploy\windows\demo.ps1 -Reset`, et notez les identifiants.
- Faites le déroulé une fois, en entier, sur la machine de la présentation.
- **Alerte Telegram** (pour l'étape 3) : `/console` avec l'opérateur `demo`, puis `/admin/` →
  Réglages → Alertes : jeton du bot (@BotFather), « Trouver mon identifiant », « Envoyer un test ».
- Navigateur : zoom à 90 %, autres onglets fermés, notifications coupées.
- Plan B : gardez des captures d'écran de chaque étape, en cas de souci de machine.

---

## 6. Présenter à distance

- **Le plus simple** : lancez la démo sur votre PC et partagez l'écran (Meet, Zoom, WhatsApp).
- **Le client clique lui-même** (sur votre VPS Windows) : `.\deploy\windows\demo.ps1 -Reseau`, puis
  ouvrez le port dans le pare-feu (PowerShell **administrateur**) :
  ```powershell
  New-NetFirewallRule -DisplayName "Demo 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
  ```
  Le client ouvre `http://ADRESSE-IP-DU-VPS:8000`. Sans nom de domaine, la connexion n'est pas
  chiffrée (http) : **uniquement les comptes de démo**, jamais un vrai mot de passe. Refermez le
  port après : `Remove-NetFirewallRule -DisplayName "Demo 8000"`.

---

## 7. Du MVP à la mise en ligne

1. Nom de domaine et HTTPS (Caddy, `deploy/Caddyfile.example`) sur le VPS.
2. Compte opérateur réel (`python -m hedgefund.web create-user`), alertes Telegram et e-mail.
3. Relecture des profils de prop firm sur les règlements officiels (`config/prop_firms.yaml`).
4. Vidéos de la formation dans `/admin/` → Académie.
5. Clé Anthropic et budget mensuel ; relecture des pages légales.
6. Bêta privée avec 5 à 10 traders, puis ouverture.
