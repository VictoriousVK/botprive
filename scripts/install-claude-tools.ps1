# Installe les skills de design pour Claude Code dans ce projet (.claude/skills/).
# A lancer une fois, depuis le dossier du projet, dans PowerShell :
#   .\scripts\install-claude-tools.ps1
# Necessite Node.js 22 (https://nodejs.org). Playwright et Sentry sont deja declares dans .mcp.json.

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "1/4  taste-skill : design-taste-frontend (eviter l'effet 'site fait par une IA')"
npx -y skills add leonxlnx/taste-skill --skill design-taste-frontend --agent claude-code

Write-Host "2/4  taste-skill : redesign-existing-projects (ameliorer les pages existantes)"
npx -y skills add leonxlnx/taste-skill --skill redesign-existing-projects --agent claude-code

Write-Host "3/4  taste-skill : image-to-code (maquette / capture -> code)"
npx -y skills add leonxlnx/taste-skill --skill image-to-code --agent claude-code

Write-Host "4/4  Vercel : web-design-guidelines (audit UI/UX et accessibilite)"
npx -y skills add vercel-labs/agent-skills --skill web-design-guidelines --agent claude-code

Write-Host ""
Write-Host "Termine. Ouvrez Claude Code dans ce dossier : il proposera d'activer Playwright et Sentry (.mcp.json)."
Write-Host "Pour Sentry, tapez /mcp dans Claude Code puis connectez votre compte."
