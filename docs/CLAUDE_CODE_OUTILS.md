# Outils Claude Code : design, tests visuels, supervision

Cinq outils demandés, plus Sentry dans Claude Code. Tout s'installe **une fois**, dans le
dossier du projet.

| # | Outil | Type | À quoi il sert | Installation |
|---|---|---|---|---|
| 1 | **taste-skill** (Leonxlnx) | skill | éviter l'effet « SaaS vibe-codé » : règles de goût, typographie, espacements, anti-clichés | script ci-dessous |
| 2 | **Vercel web-design-guidelines** | skill | audit UI/UX et accessibilité d'une page selon les règles de Vercel | script ci-dessous |
| 3 | **awesome-design-md** (VoltAgent) | fichier `DESIGN.md` | donner à l'IA un système de design écrit | **déjà fait** : `DESIGN.md` à la racine |
| 4 | **image-to-code** (taste-skill) | skill | partir d'une image (maquette, capture d'un site que vous aimez) pour coder une page fidèle | script ci-dessous |
| 5 | **Playwright** | serveur MCP | Claude ouvre le site dans un vrai navigateur, clique, prend des captures, lit les erreurs | **déjà déclaré** dans `.mcp.json` |
| + | **Sentry** | serveur MCP | Claude lit vos erreurs Sentry et les corrige | **déjà déclaré** dans `.mcp.json` |

## Installation (Windows)

Prérequis : **Node.js 22** (https://nodejs.org) et Claude Code.

```powershell
cd C:\chemin\vers\LiberteFinanciere
.\scripts\install-claude-tools.ps1
```

Le script lance ces quatre commandes (vous pouvez aussi les taper vous-même) :

```powershell
npx -y skills add leonxlnx/taste-skill --skill design-taste-frontend --agent claude-code
npx -y skills add leonxlnx/taste-skill --skill redesign-existing-projects --agent claude-code
npx -y skills add leonxlnx/taste-skill --skill image-to-code --agent claude-code
npx -y skills add vercel-labs/agent-skills --skill web-design-guidelines --agent claude-code
```

Les skills arrivent dans `.claude/skills/` du projet. Committez ce dossier : Khalifa les aura
aussi. Pour les avoir dans **tous** vos projets, ajoutez `-g` à chaque commande.

Ensuite, ouvrez Claude Code dans le dossier : il détecte `.mcp.json` et demande s'il peut
activer **playwright** et **sentry**. Acceptez. Pour Sentry, tapez `/mcp`, choisissez
*sentry* et connectez votre compte (fenêtre du navigateur).

Si vous préférez ajouter Playwright à la main : `claude mcp add playwright npx @playwright/mcp@latest`.
Pour cibler directement votre projet Sentry :
`claude mcp add --transport http sentry https://mcp.sentry.dev/mcp/<organisation>/<projet>`.

## Vérifier que tout est là

Dans Claude Code :

- `/skills` (ou demandez « quelles skills as-tu ? ») : design-taste-frontend,
  redesign-existing-projects, image-to-code, web-design-guidelines.
- `/mcp` : playwright et sentry « connected ».

## Comment s'en servir (exemples à copier)

**Améliorer une page sans effet « IA » :**
> Lis DESIGN.md et docs/UI_UX_DESIGN.md. Avec les skills design-taste-frontend et
> redesign-existing-projects, propose 3 améliorations pour la page /tarifs/ sur mobile.
> Applique-les une par une, vérifie avec Playwright à 390 px et 1360 px, montre-moi les
> captures.

**Audit complet :**
> Utilise la skill web-design-guidelines pour auditer apps/web/src/app/compte/view.tsx.
> Classe les problèmes par gravité et corrige les 5 plus importants.

**Partir d'une image :**
> (glissez une capture dans Claude Code) Avec la skill image-to-code, reproduis cette mise en
> page pour la section « Fondateurs » de l'accueil, en respectant DESIGN.md (couleurs,
> polices, composants existants).

**Tester un parcours :**
> Lance la plateforme en mode simulation, puis avec Playwright fais une inscription complète
> (récupère le lien de confirmation dans le journal du serveur), connecte-toi et ouvre
> /coach/. Dis-moi s'il y a des erreurs dans la console.

**Corriger les erreurs remontées par Sentry :**
> Avec Sentry, liste les 5 erreurs non résolues les plus fréquentes de la dernière semaine.
> Pour chacune : explique la cause en français simple, corrige le code, ajoute un test, lance
> pytest.

## À propos d'awesome-design-md

Le dépôt VoltAgent/awesome-design-md rassemble des `DESIGN.md` tirés de vraies marques
(Kraken, Coinbase, Revolut, Stripe…). Il n'y a rien à installer : on place un `DESIGN.md` à
la racine et l'IA le suit. Le vôtre est **déjà écrit** pour Liberté Financière à partir de
vos couleurs et polices actuelles. Pour vous inspirer d'une marque (par exemple Kraken pour
un tableau de bord sombre et dense), téléchargez son `DESIGN.md` dans
`docs/design-references/` et demandez à Claude de **s'en inspirer sans changer votre
palette**.

## Prudence

Ces skills et serveurs viennent de tiers. Avant d'installer une nouvelle skill, regardez son
dépôt GitHub (étoiles, date, contenu du `SKILL.md`). Ne donnez jamais vos mots de passe ou
clés à une skill.

Sources : [taste-skill / image-to-code](https://claudemarketplaces.com/skills/leonxlnx/taste-skill/image-to-code),
[CLI skills (vercel-labs)](https://cdn.jsdelivr.net/npm/skills@1.5.22/README.md),
[awesome-design-md](https://github.com/voltagent/awesome-design-md),
[Playwright MCP pour Claude Code](https://playwright.dev/mcp/clients/claude-code),
[Sentry MCP](https://mcp.sentry.dev/).
