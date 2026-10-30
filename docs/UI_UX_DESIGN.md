# UI/UX Design (v0.4)

> Principes, système de design et plan d'amélioration du site. La référence courte pour les
> agents IA est [`DESIGN.md`](../DESIGN.md) à la racine ; ce document l'explique et donne le
> plan de travail.

## 1. Objectifs d'expérience

1. **Confiance** : un visiteur doit comprendre en 10 secondes qui est derrière (Victor Faye,
   Khalifa Diop), ce qui est vendu, combien ça coûte en FCFA, et que rien n'est promis.
2. **Mobile d'abord** : la majorité des visiteurs arrivent depuis WhatsApp/Telegram sur un
   téléphone Android, parfois avec une connexion lente.
3. **Un parcours court jusqu'au paiement Wave** : offre → compte → payer, sans détour.
4. **Apprendre, pas seulement acheter** : académie, coach IA et lives sont au cœur de la
   valeur ; ils doivent être faciles à retrouver dans l'espace membre.

## 2. Principes

| Principe | Concrètement |
|---|---|
| Clarté avant effets | une idée par section, un bouton principal par écran |
| Données honnêtes | toute courbe indique sa source (simulation, papier, MT5) |
| Français simple | phrases courtes, vouvoiement, pas d'anglicismes inutiles (« killzone » oui car c'est le vocabulaire ICT) |
| Prix en FCFA d'abord | montant Wave en FCFA, équivalent en $ en second |
| États prévus | chargement, vide, erreur, non connecté, droit manquant (voir APP_FLOW §9) |
| Léger | images optimisées, pas de vidéo en fond, scripts tiers chargés à la demande |

## 3. Système de design

Résumé de [`DESIGN.md`](../DESIGN.md) :

- **Palette** : fonds encre (`#03050a` → `#172538`), bleu marque `#2a8fea` pour l'action, vert
  `#4be08a` / rouge `#ef5354` pour les données, or `#d4b374` en accent.
- **Typos** : Montserrat (titres), Inter (texte), JetBrains Mono (chiffres, eyebrows).
- **Composants** : `.btn-*`, `.card`, `.chip-*`, `.field/.input`, `.table`, `Notice`,
  `Spinner`, `Empty`, `Stat`, `Reveal`, `Markdown`.
- **Grille** : `.container-x` 76 rem ; colonnes Tailwind (`md:grid-cols-2`, `lg:grid-cols-3`).
- **Points de rupture** : 390 px (mobile de référence), 640, 768, 1024, 1360 px.

## 4. Écrans livrés en v0.4

| Écran | Points de design |
|---|---|
| Inscription | piège anti-robot invisible ; Turnstile sombre en français si activé ; bouton désactivé tant que la vérification n'est pas faite |
| « Confirmez votre adresse e-mail » | icône enveloppe, adresse en clair, délai de 48 h, conseil spams, renvoi du lien, retour à la connexion |
| Connexion | lien « Mot de passe oublié ? » aligné à droite du libellé ; si e-mail non confirmé : erreur + bouton de renvoi |
| `/compte/verifier/` | trois états : en cours, confirmé (redirection automatique), lien non valide (chemin de sortie) |
| `/compte/mot-de-passe/` | deux champs, contrôle d'égalité, message de succès qui rappelle la fermeture des sessions |
| `/coach/` | conversation + colonne « Base de référence » ; questions de départ ; sources en puces sous chaque réponse ; badge or « Hors base » ; compteur de quota en mono ; rappel « pédagogique uniquement » |
| E-mails | fond encre, carte, un seul bouton bleu, lien en clair en secours, texte brut équivalent |
| Admin | puce or « E-mail non confirmé » + bouton « Confirmer l'e-mail » ; onglet Coach IA |

## 5. Audit et plan d'amélioration

Priorités : **P0** avant la prochaine campagne · **P1** ce trimestre · **P2** ensuite.

| # | Écran | Problème / opportunité | Proposition | P |
|---|---|---|---|---|
| U1 | Accueil | Les preuves de sérieux arrivent tard | Remonter le bloc fondateurs + « ce que nous ne promettons pas » juste après le héros | P0 |
| U2 | Tarifs | Comparaison des 3 abonnements difficile sur mobile | Cartes empilées avec bascule 1/3/12 mois collante, différence clé en premier | P0 |
| U3 | Espace membre | L'accès aux contenus achetés est noyé | Section « Continuer » : dernier cours, prochain live, coach | P1 |
| U4 | Coach | Pas d'historique entre deux visites | Conserver la dernière conversation (stockage local) | P2 |
| U5 | Académie | Pas d'indication de progression globale | Barre de progression par cours, badge « terminé » | P1 |
| U6 | Formulaires | Messages d'erreur parfois techniques | Relire tous les messages du serveur en français simple | P1 |
| U7 | Global | Pas de page « Contact / support » | Page avec WhatsApp, e-mail, FAQ paiement | P1 |
| U8 | Global | Vitesse sur 3G | Mesurer avec Lighthouse mobile, viser LCP < 2,5 s | P1 |
| U9 | Robots | Résultats encore simulés | Afficher clairement « simulation » jusqu'aux résultats MT5 vérifiés | P0 |
| U10 | E-mails | Pas d'e-mail de bienvenue ni de reçu de paiement | Ajouter ces deux modèles | P1 |

## 6. Méthode de travail design avec Claude Code

1. Installer les outils (voir [CLAUDE_CODE_OUTILS.md](CLAUDE_CODE_OUTILS.md)) : taste-skill,
   web-design-guidelines (Vercel), image-to-code, Playwright, et garder `DESIGN.md` à jour.
2. Pour une maquette : envoyer une capture ou une image de référence à Claude Code avec la
   skill **image-to-code**, en précisant « respecte DESIGN.md ».
3. Pour un écran existant : demander d'abord un audit avec **web-design-guidelines** et
   **design-taste-frontend**, puis appliquer les corrections une par une.
4. Vérifier avec **Playwright** : captures à 390 px et 1 360 px, console sans erreur.
5. `npm run lint`, `npm run publish-site`, `pytest -q`, puis commit.

Exemple de demande :

> « Lis DESIGN.md et docs/UI_UX_DESIGN.md. Applique U2 (page /tarifs/). Utilise les skills
> design-taste-frontend et web-design-guidelines. Vérifie avec Playwright à 390 et 1360 px,
> montre-moi les captures avant/après, puis lance npm run lint et pytest. »

## 7. Contenus et ton

- Vouvoiement, phrases courtes, verbes d'action sur les boutons (« Payer 46 000 FCFA avec
  Wave », « Renvoyer le lien »).
- Toujours rappeler le risque près d'un chiffre de performance.
- Termes ICT en anglais quand c'est le vocabulaire de la méthode (order block, FVG,
  killzone), expliqués à la première occurrence.
