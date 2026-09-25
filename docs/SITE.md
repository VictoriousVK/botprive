# Site Liberté Financière : guide des cofondateurs

La plateforme sert maintenant deux espaces sur la même adresse :

| Adresse | Pour qui | Contenu |
|---|---|---|
| `/` | le public et les membres | site Liberté Financière : accueil, robots, copytrading, académie, offres, espace membre |
| `/compte/` | les membres | inscription, connexion, abonnement, paiement Wave, historique des paiements |
| `/admin/` | les opérateurs (vous) | validation des paiements, membres, cours vidéo, stratégies de copytrading, prospects |
| `/console` | les opérateurs (vous) | console de trading **Alpha Edge** (bots, MT5, arrêt d'urgence), inchangée sur le fond |

Les membres ont leurs **propres comptes** (e-mail + mot de passe, 12 caractères minimum). Ils
n'ont jamais accès à la console ni à l'administration. Les opérateurs restent créés
uniquement depuis le serveur (`python -m hedgefund.web create-user`), et se connectent
d'abord à `/console` avant d'ouvrir `/admin/`.

> **Règles non négociables** (déjà appliquées par le code et les textes du site) : aucune
> performance, témoignage ou partenaire inventé ; aucune promesse de gain ; les résultats
> affichés viennent du journal de la plateforme avec leur source (simulation, papier, MT5) ;
> la copie sur compte réel reste fermée jusqu'à l'avis d'un avocat.

---

## 1. La marque

- **Liberté Financière** est la marque principale, en grand (emblème animé sur l'accueil).
- Le monogramme **VF** de Victor Faye apparaît en miniature : dans l'en-tête, la signature
  des fondateurs, la fiche fondateur et le pied de page.
- **Khalifa Diop** apparaît avec ses initiales (KD) tant qu'il n'a pas de logo personnel.
- **Alpha Edge** est le nom de l'espace de trading (console, robots).

Les deux logos ont été redessinés en vectoriel à partir des images reçues (trop petites pour
un affichage en grand) : `apps/web/src/components/brand.tsx` et `apps/web/public/brand/`.
Quand vous aurez les fichiers sources du graphiste (SVG ou PNG de plus de 1 000 px),
remplacez-les à ces deux endroits.

Textes modifiables sans toucher au code : **`config/site.yaml`** (slogan, présentation des
fondateurs, offres et prix, robots affichés, parcours prévus, liens communauté, bandeau de
cotations). Redémarrez la plateforme après modification.

## 2. Paiement Wave

Deux modes, choisis automatiquement :

### Mode manuel (utilisable tout de suite)

1. Dans `config/site.yaml`, renseignez `billing.wave.manual_number` (votre numéro Wave
   marchand) et/ou `billing.wave.manual_link` (lien ou QR de paiement Wave Business).
2. Le membre choisit une offre, reçoit le montant, le numéro et une référence (`pay_…`), paie
   dans Wave, puis colle l'**ID de la transaction** affiché par Wave.
3. Dans **`/admin/` → Paiements → À vérifier**, retrouvez la transaction dans votre
   application Wave Business (même montant, même ID), puis **Valider**. L'accès est activé
   immédiatement, pour la durée payée. Une même transaction ne peut pas être déclarée deux fois.

### Mode automatique (API Wave Checkout)

Il faut un compte **Wave Business** avec accès à l'API Checkout, et un site en **HTTPS**.

1. Dans le portail Wave Business, créez une clé API (droits « Checkout ») et un webhook
   pointant vers `https://votredomaine.com/api/webhooks/wave`, avec les événements de
   paiement de session (`checkout.session.completed`, etc.). Notez le secret du webhook.
2. Dans `.env.ps1` :
   ```powershell
   $env:LF_PUBLIC_URL = "https://votredomaine.com"
   $env:LF_WAVE_API_KEY = "votre-cle-api-wave"
   $env:LF_WAVE_WEBHOOK_SECRET = "secret-du-webhook"
   ```
3. Redémarrez. Le membre est alors redirigé vers Wave, puis revient sur `/compte/`, où
   le paiement est vérifié.

Sécurité : un paiement n'est crédité qu'après **relecture de la session auprès de l'API
Wave** (statut « succeeded », même montant, devise XOF, même référence). Ni le retour du
navigateur ni le contenu du webhook ne suffisent. Le webhook est refusé sans signature
valide (`Wave-Signature`, HMAC-SHA256, 5 minutes de tolérance) ou sans le jeton du secret.
**Vérifiez dans le portail Wave le format exact de signature de votre webhook** avant la mise
en production : une erreur de réglage empêche l'activation automatique mais ne peut jamais
créditer un faux paiement (le membre peut toujours actualiser sa page, ce qui relit Wave).

Principe des abonnements : Wave n'a pas de prélèvement automatique, donc chaque paiement
**prolonge** l'accès (1, 3 ou 12 mois, dont 2 offerts sur 12). Un renouvellement de la même
offre s'ajoute à la date de fin actuelle. Vous pouvez aussi **attribuer** un accès sans
paiement (bêta-testeurs, cofondateurs) dans `/admin/` → Membres → Attribuer ; c'est tracé
dans le journal.

## 3. Académie : ajouter vos vidéos (même de 40 minutes)

Les vidéos ne sont **pas stockées sur la plateforme** : une vidéo de 40 minutes pèse souvent
plus de 1 Go, et doit être diffusée en qualité adaptative (téléphone, 3G/4G). Utilisez un
hébergeur vidéo :

| Hébergeur | Pourquoi | Ce que vous collez dans l'admin |
|---|---|---|
| **Bunny Stream** (recommandé pour démarrer) | peu coûteux, lecteur rapide, restriction par domaine | lien « Embed » : `https://iframe.mediadelivery.net/embed/<bibliothèque>/<vidéo>` |
| Cloudflare Stream | simple, facturé à la minute | `https://customer-<code>.cloudflarestream.com/<id>/iframe` |
| Mux | très bonne qualité, analytics | `https://player.mux.com/<playback-id>` |
| Vimeo (offre payante) | vidéos privées | `https://vimeo.com/<id>/<hash>` |
| YouTube (non répertoriée) | gratuit, mais publicité et partage faciles | lien de la vidéo |

Étapes :

1. Téléversez chaque **partie** sur l'hébergeur (une vidéo par partie).
2. Dans l'hébergeur, **restreignez la lecture à votre domaine** (« allowed domains » /
   « domain restriction ») : sans cela, un lien pourrait être partagé.
3. `/admin/` → **Académie** → **Nouveau cours** : titre, adresse (ex. `methode-ict`), niveau,
   accès (Gratuit, Membres, Modules avancés), statut :
   - **Brouillon** : invisible ;
   - **En préparation** : visible avec la mention « En préparation », sans vidéo ;
   - **Publié** : visible, parties jouables selon l'offre du membre.
4. **Ajouter une partie** : titre, lien de la vidéo, durée (`40:00`, `1:05:30` ou un nombre
   de minutes), résumé, **chapitres** (un par ligne : `12:30 Le Silver Bullet`), et « Partie
   gratuite » pour offrir un extrait. Réordonnez avec les flèches.

Le membre voit la liste des parties, les chapitres cliquables, et reprend la lecture où il
s'est arrêté (automatique pour les fichiers vidéo, bouton « Marquer comme vue » pour les
lecteurs intégrés). Les trois parcours prévus (débutant, gestion du risque, ICT) s'affichent
« en préparation » tant qu'aucun cours publié ne porte la même adresse ; changez-les dans
`config/site.yaml`.

Pour des fichiers `.mp4` hébergés ailleurs (CDN), déclarez le domaine :
`$env:LF_MEDIA_HOSTS = "videos.votredomaine.com"`.

## 4. Robots

Le catalogue du site affiche les robots de `config/site.yaml` : **ICT Ultimate Pro v6.20** et
**ICT Ultimate Pro v6** (bêta), et une carte **« Nouveau robot haute performance — en
développement »** avec inscription à la liste d'attente. Quand le nouveau robot sera prêt :

1. ajoutez sa stratégie dans le moteur (comme les deux EA ICT, voir `docs/PLATFORM.md` §5 bis) ;
2. faites-le tourner plusieurs mois sur un compte démo **suivi par un vérificateur
   indépendant** (Myfxbook ou FXBlue) ;
3. dans `config/site.yaml`, renseignez `template:` et passez `status:` de `development` à
   `beta` puis `available`. Les inscrits de la liste d'attente sont dans `/admin/` → Prospects.

## 5. Copytrading

Ce qui fonctionne dès maintenant (**démo**) :

1. Dans la console, créez et démarrez le bot qui sert de source (par exemple ICT Pro v6.20 sur
   l'or, en mode Papier ou MT5 démo).
2. `/admin/` → **Copytrading** → nouvelle stratégie : nom, trader (Khalifa Diop, Victor Faye),
   **bot source**, capital de référence, niveau de risque, statut **Ouvert à la copie**.
3. Le membre choisit la stratégie, règle son **capital**, son **multiplicateur** (0,1 à 3) et sa
   **perte maximale** (5 % à 50 %), accepte l'avertissement, et suit le résultat en temps réel.
   La copie s'arrête seule au seuil de perte ; il peut l'arrêter à tout moment.

Tous les chiffres viennent du journal (résultat du bot à chaque instant), avec leur source ;
en mode simulation, le site l'écrit clairement (« prix simulés »).

Ce qui reste fermé : la **copie d'ordres sur le compte MT5 du membre**. En zone UEMOA, gérer ou
répliquer des ordres pour des clients relève d'activités réglementées (gestion pour compte de
tiers, conseil en investissement, AMF-UMOA). Il faut d'abord l'avis d'un avocat, puis un
connecteur MT5 côté membre. `LF_COPYTRADING=off` masque le copytrading ; `live` n'est accepté
qu'avec `LF_COPYTRADING_LEGAL_OK=1`, et la copie réelle n'est de toute façon pas encore codée.

## 6. Mettre à jour le site (développeurs)

Le code du site est dans `apps/web` (Next.js, TypeScript, Tailwind CSS, Framer Motion). Le
résultat compilé est déjà inclus dans `hedgefund/web/site/` : **Node.js n'est pas nécessaire
pour faire tourner la plateforme.** Pour modifier le site :

```bash
cd apps/web
npm ci
npm run dev            # http://localhost:3000, l'API est relayée vers la plateforme sur :8000
npm run publish-site   # compile et copie le résultat dans hedgefund/web/site
```

La plateforme sert chaque page avec une politique de sécurité (CSP) qui n'autorise que les
scripts de la page (empreintes SHA-256), les polices et styles du site, et les lecteurs vidéo
de la liste ci-dessus. Un site republié est pris en compte sans redémarrage.

## 7. Réglages (variables d'environnement)

| Variable | Rôle | Défaut |
|---|---|---|
| `LF_PUBLIC_URL` | adresse publique en https, pour les retours Wave | vide |
| `LF_WAVE_API_KEY` | clé API Wave Checkout (active le mode automatique avec `LF_PUBLIC_URL`) | vide |
| `LF_WAVE_WEBHOOK_SECRET` | secret du webhook Wave | vide |
| `LF_REGISTRATION` | `0` pour fermer les inscriptions | `1` |
| `LF_COPYTRADING` | `off`, `demo` | `demo` |
| `LF_MEDIA_HOSTS` | domaines autorisés pour des fichiers `.mp4` | vide |
| `LF_SITE_CONFIG` | autre fichier que `config/site.yaml` | vide |

## 8. Avant l'ouverture publique

- Faire valider par un avocat : `/risques/` (avertissement, conditions, confidentialité), les
  offres, et le copytrading.
- Remplacer les prix par les vôtres dans `config/site.yaml` (ceux du blueprint sont des
  hypothèses).
- Mettre en ligne en HTTPS (Cloudflare Tunnel ou Caddy, voir `docs/PLATFORM.md` §6) avec
  `HF_PUBLIC_HOST` = votre domaine et `HF_TRUST_PROXY=1`.
- Ajouter un envoi d'e-mails (confirmation d'inscription, mot de passe oublié, rappel
  d'échéance) : pas encore inclus. En attendant, si un membre oublie son mot de passe, vous
  lui en définissez un nouveau depuis le serveur :
  `python -m hedgefund.web member-password --email membre@exemple.com`.
