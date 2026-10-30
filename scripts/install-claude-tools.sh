#!/usr/bin/env bash
# Mac / Linux : installe les skills de design pour Claude Code dans ce projet (.claude/skills/).
set -euo pipefail
cd "$(dirname "$0")/.."
npx -y skills add leonxlnx/taste-skill --skill design-taste-frontend --agent claude-code
npx -y skills add leonxlnx/taste-skill --skill redesign-existing-projects --agent claude-code
npx -y skills add leonxlnx/taste-skill --skill image-to-code --agent claude-code
npx -y skills add vercel-labs/agent-skills --skill web-design-guidelines --agent claude-code
echo "Terminé. Playwright et Sentry sont déclarés dans .mcp.json (tapez /mcp dans Claude Code pour Sentry)."
