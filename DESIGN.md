# DESIGN.md : Liberté Financière

Système de design de référence pour tout agent IA (Claude Code, skills de design) qui modifie
`apps/web`. Lire avant d'écrire du CSS ou un composant. Les tokens sont définis dans
`apps/web/src/app/globals.css` (`@theme`) : **utiliser ces tokens, jamais de nouvelles
couleurs en dur**.

## 1. Caractère

« Terminal de trading sérieux, fait en Afrique. » Sombre, précis, chiffré, calme. Confiance
avant excitation. Pas de néon, pas de fusées, pas de lingots qui tombent, pas de « devenez
riche ». Les chiffres sont des données, pas des promesses.

## 2. Couleurs

| Rôle | Token | Valeur | Usage |
|---|---|---|---|
| Fond page | `ink-950` | `#03050a` | `body` |
| Fond secondaire | `ink-900` / `ink-850` | `#060a12` / `#09101b` | bandeau, pied de page, zones |
| Surface carte | `ink-800` | `#0c1522` | `.card` |
| Bordure | blanc 10 % | `rgb(255 255 255 / .1)` | cartes, champs |
| Texte | `fg` | `#e9eef6` | corps |
| Texte secondaire | `muted` | `#93a1b5` | descriptions |
| Texte tertiaire | `faint` | `#5d6a7e` | légendes, mentions |
| Marque (action) | `brand-400/500/600` | `#4fb0ff` / `#2a8fea` / `#1668c9` | boutons primaires, liens, focus |
| Hausse / succès | `up-400` | `#4be08a` | gains, validé |
| Baisse / erreur | `down-500` | `#ef5354` | pertes, erreurs |
| Accent Victor Faye | `gold-400` | `#d4b374` | rare : mentions premium, avertissements doux |
| Wave | `#1dc8ff` | — | uniquement le bouton de paiement Wave |

Règles : une seule couleur d'action (bleu marque). Vert et rouge réservés aux données de
marché et aux statuts. L'or reste un accent (moins de 5 % de la surface).

## 3. Typographie

| Usage | Police | Réglages |
|---|---|---|
| Titres | Montserrat 700–800 (`--font-display`) | `letter-spacing: -0.015em`, `line-height: 1.1`, `.h-section` = clamp(1.7rem → 2.6rem) |
| Corps | Inter Variable (`--font-sans`) | 15–16 px, `line-height` 1.6 |
| Chiffres, prix, codes, eyebrows | JetBrains Mono (`--font-mono`, classe `.num`) | chiffres tabulaires |

Hiérarchie par page : un `eyebrow` en mono majuscules, un `h1.h-section`, un paragraphe
`text-muted` de 2 lignes maximum, puis le contenu.

## 4. Espacements, rayons, ombres

- Conteneur : `.container-x` (max 76 rem, gouttière 16 px mobile / 24 px ≥ 640 px).
- Rythme vertical des sections : `py-14` à `py-24`. Entre éléments : multiples de 4 px.
- Rayons : cartes `1.1rem` (`--radius-card`), boutons `.8rem`, petits boutons `.65rem`,
  puces `999px`.
- Ombre : seulement `--shadow-glow` au survol des cartes cliquables et sur `.btn-primary`.

## 5. Composants (classes existantes)

| Composant | Classe / fichier | Règle |
|---|---|---|
| Bouton principal | `.btn .btn-primary` | une seule action principale par écran |
| Bouton secondaire | `.btn .btn-ghost` | actions secondaires |
| Petit bouton | `+ .btn-sm` | tableaux, barres d'outils |
| Paiement | `.btn .btn-wave` | uniquement « Payer avec Wave » |
| Carte | `.card` (+ `.card-hover` si cliquable) | contenu groupé |
| Puce | `.chip` + `.chip-blue/green/gold/red` | statuts, étiquettes |
| Champ | `.field > span` + `.input` | libellé au-dessus, jamais de placeholder seul |
| Tableau | `.table` dans `.scroll-x` | largeur min. pour mobile |
| Messages | `<Notice kind="info/warn/error/ok">` (`components/ui.tsx`) | toute erreur API |
| Chargement | `<Spinner label="…">` | toujours un libellé |
| Vide | `<Empty title>` | phrase utile + action |
| Statistique | `<Stat label value>` | chiffres en mono |
| Apparition | `<Reveal>` | une fois, 0,6 s, décalage ≤ 18 px |
| Markdown sûr | `<Markdown text>` (`components/markdown.tsx`) | réponses du coach |

## 6. Mouvement

- Framer Motion, `MotionConfig reducedMotion="user"` déjà global.
- Durées 0,2–0,6 s, easing `[0.22, 1, 0.36, 1]`. Pas d'animation en boucle hors bandeau de
  cotations et point « live ».
- Pas de parallaxe, pas de texte qui défile lettre par lettre, pas de compteur qui « roule ».

## 7. Accessibilité

- Contraste AA minimum ; `faint` seulement pour du texte non essentiel.
- Focus visible (`:focus-visible` déjà défini), cibles tactiles ≥ 40 px.
- Chaque champ a un `<label>` ; chaque icône seule a un `aria-label`.
- Langue `fr`, dates en `fr-FR`, montants en FCFA avec espace insécable.

## 8. Ce qu'il ne faut pas faire (anti « site fait par une IA »)

- Dégradés violet-rose, fonds « aurora », verre dépoli partout, emojis dans les titres.
- Trois cartes identiques « Rapide / Sécurisé / Simple » avec une icône chacune.
- Titres creux (« Révolutionnez votre trading »), fausses statistiques, faux témoignages,
  logos de partenaires inventés.
- Centrer tous les textes ; mettre des ombres colorées sur tout ; arrondir à 24 px partout.
- Ajouter une nouvelle police, une nouvelle couleur ou une librairie UI (shadcn, MUI…) sans
  décision explicite.
- Placeholder gris comme seul libellé ; boutons « Cliquez ici ».
