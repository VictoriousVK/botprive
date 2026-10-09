# Alpha Edge — films de présentation (motion design)

Module **isolé** du reste du dépôt : il ne modifie ni le site, ni l'API, ni la console. Il filme le
produit réel en mode démonstration, puis monte trois films avec [Remotion](https://www.remotion.dev)
(React, rendu image par image, export MP4).

| Film | Composition | Format | Durée |
|---|---|---|---|
| Présentation et démonstration complète | `AlphaEdgeFilm` | 1920 × 1080, 30 i/s | ≈ 4 min 50 |
| Version courte promotionnelle | `AlphaEdgePromo` | 1920 × 1080, 30 i/s | ≈ 45 s |
| Version verticale (TikTok, Reels, Shorts) | `AlphaEdgeVertical` | 1080 × 1920, 30 i/s | ≈ 48 s |

Chaque film existe aussi sans sous-titres incrustés (`…Clean`), pour une diffusion avec le fichier
SRT ou avec une voix off.

---

## 1. Ce qu'il faut

- **Node.js 20 ou plus récent** (`node --version`).
- **Python 3.11+ et le projet installé** (pour les captures : `pip install -e ".[web,saas,research]"`
  à la racine du dépôt, ou le `.venv` créé par `deploy\windows\install.ps1`).
- Environ 2 Go d'espace libre.

```bash
cd apps/motion
npm install
npx playwright install chromium      # navigateur des captures (une fois)
```

Remotion télécharge lui-même son navigateur de rendu au premier rendu. Sur une machine hors ligne :
`REMOTION_BROWSER_EXECUTABLE=/chemin/vers/chrome-headless-shell` et
`CAPTURE_CHROMIUM=/chemin/vers/chrome`.

> **Licence Remotion** : Remotion est gratuit pour les particuliers, les entreprises de 3 personnes
> au plus et les associations ; au-delà, une licence entreprise est requise
> (https://www.remotion.dev/license). À vérifier avant un usage commercial à plus grande échelle.

---

## 2. Produire les films, dans l'ordre

```bash
npm run capture        # 1. filme le produit réel (≈ 6 min) → public/captures/
npm run audio          # 2. musique et effets sonores (≈ 1 min 15) → public/audio/
npm run subtitles      # 3. sous-titres SRT et script de voix off → subtitles/, VOIX-OFF.fr.md
npm run render:all     # 4. les trois MP4 → out/
npm run qc             # 5. contrôle des MP4 et planches d'images → out/qc/
npm run share -- out/alpha-edge-film-1080p.mp4   # 6. copie légère à envoyer (28 Mo au plus)
```

La copie légère (`…-leger.mp4`) garde la 1080p et tient sous une taille donnée (`--max 15` pour
15 Mo), pour un envoi par message ou e-mail ; le fichier complet reste la version à projeter.

Rendu d'un seul film : `npm run render:film`, `render:promo` ou `render:vertical`. Options, après
`--` : `--clean` (sans sous-titres incrustés), `--4k` (film et version courte en 3840 × 2160),
`--concurrency 2` (machine modeste), `--frames 0-299` (un extrait, pour tester).

Durée de rendu indicative sur un processeur à 4 cœurs, sans carte graphique : voir le rapport
(`RAPPORT.md`, section « Contrôle qualité »).

**Rendu en plusieurs fois** (machine modeste, ou machine qui doit servir entre-temps) :
`node scripts/render.mjs film --segments 2900` rend le film par morceaux de 2 900 images dans
`out/parts/`. Une coupure n'est pas grave : relancer la même commande reprend au morceau suivant
(`--max-parts 1` pour n'en rendre qu'un à la fois). Quand tous les morceaux sont là, ils sont mis
bout à bout sans réencodage, puis la bande son complète (musique, effets, voix off si présente) est
mixée par `scripts/mix.ts` et ajoutée. Les morceaux d'un ancien rendu se suppriment avec le dossier
`out/parts/<film>/` (à faire après tout changement du film).

Les vidéos sortent en H.264, couleurs BT.709 en plage vidéo standard (`yuv420p`), lisibles
partout (téléphones, WhatsApp, YouTube, PowerPoint).

**Prévisualiser et ajuster** : `npm run studio` ouvre l'éditeur de Remotion dans le navigateur
(lecture, avance image par image, choix de la composition). Les modifications des fichiers de
contenu s'affichent aussitôt.

**Images de contrôle** sans tout rendre : `node scripts/stills.mjs AlphaEdgeFilm 120 1359 4678`
(numéros d'image) ou `node scripts/stills.mjs AlphaEdgeFilm --every 10` → `out/stills/`.

---

## 3. Les captures : le produit réel, jamais redessiné

`npm run capture` lance la plateforme en **mode démonstration** (`python -m hedgefund.web demo`,
dossier `apps/motion/.cache/demo`, prix simulés, comptes et trades fictifs, bandeau « Démonstration »
sur chaque page), parcourt les écrans avec un navigateur automatisé (ordinateur 1440 × 900 et
téléphone 390 × 844, haute définition) et enregistre :

- `public/captures/<écran>.jpg` : les captures ;
- `public/captures/manifest.json` : pour chaque écran, sa taille et la position des zones que le film
  montre (« perf », « guard », « calc »…), mesurées dans la page réelle.

Les films ne montrent que ces captures : quand l'interface change, il suffit de relancer
`npm run capture`, et les cadres, zooms et clics se recalent sur les nouvelles positions. Une seule
section à refaire : `npm run capture -- console` (sections : `public`, `signup`, `trader`,
`prospect`, `admin`, `phone`).

Les vraies données ne sont jamais touchées : le mode démonstration n'utilise ni la base réelle, ni le
dossier `var/` réel, ni Wave, ni le trading réel.

---

## 4. Modifier les films sans toucher au code

Tout se règle dans `src/content/` :

| Fichier | Contenu |
|---|---|
| `film.ts`, `promo.ts`, `vertical.ts` | les scènes, leurs durées, transitions, sous-titres, mouvements de caméra, clics, annotations |
| `brand.ts` | nom, slogans, adresse du site, contact, mention légale, teinte du logo |
| `../theme.ts` | couleurs, polices, courbes d'animation |

Une scène « visite » (`kind: "tour"`) se décrit par étapes, en secondes depuis le début de la scène :

```ts
{ at: 0,   shot: "dashboard", view: "top" },                        // afficher une capture
{ at: 8.0, view: { target: "perf", pad: 36 } },                      // cadrer une zone (caméra)
{ at: 8.2, focus: "perf", note: { kicker: "PERFORMANCE",            // l'encadrer et l'expliquer
    title: "Les 30 derniers jours", text: "Calculée sur vos trades." } },
{ at: 9.6, cursor: "submit", click: true },                          // déplacer le curseur, cliquer
{ at: 4.1, sfx: "type" },                                            // un effet sonore
```

`target`, `focus` et `cursor` acceptent un nom de zone du manifeste ou un rectangle
`{ x, y, w, h }` en pixels de la page. Les sous-titres (`captions`) sont le texte de la voix off ;
`npm run subtitles` vérifie qu'aucune réplique ne déborde sur la scène suivante et signale celles
qui seraient trop rapides à dire (plus de 15,5 caractères par seconde).

Après une modification : `npm run subtitles`, puis `npm run audio` si des durées ont changé (la
musique suit le découpage), puis le rendu.

---

## 5. Voix off

Le script complet, minuté, est dans `VOIX-OFF.fr.md` (régénéré par `npm run subtitles`). Pour
ajouter une voix :

1. enregistrer (ou générer avec un service de synthèse vocale) un fichier par film, calé sur le
   début du film, au format WAV 44,1 kHz ;
2. le déposer sous `public/audio/voice-film.wav`, `voice-promo.wav` ou `voice-vertical.wav` ;
3. relancer le rendu (de préférence la version `--clean` : la voix porte le texte, le SRT
   l'accompagne).

La musique baisse automatiquement sous chaque réplique dès qu'un fichier de voix est présent.
Aucune clé ni service externe n'est nécessaire pour produire les films sans voix.

---

## 6. Son

`npm run audio` **synthétise** la musique (nappes, basse, pulsation électronique, arpèges,
réverbération) et les effets (clic, balayage, impact, scintillement, frappe, notification) à partir
de formules : aucun échantillon ni enregistrement tiers, donc aucun droit à acquérir. La musique
suit le découpage de chaque film (intro sombre qui monte, pulsation pendant les démonstrations,
accord final sous la signature). Pour une musique de compositeur : remplacer
`public/audio/music-<film>.wav` par un fichier de même durée.

---

## 7. Organisation

```
apps/motion/
  scripts/      capture.mjs (captures), audio.ts (son), subtitles.ts (SRT, script),
                render.mjs (MP4), stills.mjs (images de contrôle), qc.mjs (contrôle des MP4)
  src/
    content/    les films en données : scènes, textes, durées, marque
    scenes/     intro, problème, chapitre, visite du produit, explication ICT, alerte, signature
    components/ fond et grain, logo, cadres (fenêtre, téléphone), curseur, sous-titres, graphiques
    compositions/  enchaînement des scènes, transitions, sous-titres, pistes audio
    data/       formes de marché illustratives (jamais présentées comme des données)
    lib/        captures (manifeste), caméra et curseur, timeline
  public/       polices (OFL), emblème ; captures/ et audio/ sont générés
  subtitles/    SRT générés
  VOIX-OFF.fr.md, RAPPORT.md
```
