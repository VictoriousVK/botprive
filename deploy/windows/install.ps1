# Installation de la plateforme HedgeFund sur Windows (PC ou VPS Windows avec MetaTrader 5).
# Exécuter dans PowerShell, depuis le dossier du projet :   .\deploy\windows\install.ps1
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python introuvable. Installez Python 3.11+ depuis python.org en cochant 'Add python.exe to PATH'."
}
python --version

if (-not (Test-Path .venv)) { python -m venv .venv }
& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -e ".[web,mt5,research]"

if (-not (Test-Path .env.ps1)) {
    Copy-Item deploy\windows\env.example.ps1 .env.ps1
    Write-Host "Fichier .env.ps1 créé : ouvrez-le et complétez vos réglages (identifiants MT5 optionnels)."
}
Write-Host ""
Write-Host "Étape suivante : créez votre compte administrateur :"
Write-Host "   .\.venv\Scripts\python.exe -m hedgefund.web create-user --username VOTRE_NOM"
Write-Host "Puis démarrez :   .\deploy\windows\start.ps1"
