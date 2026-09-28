# Démonstration : la plateforme complète sur des données fictives, pour la présenter à un client.
# Rien de réel : prix simulés, comptes et trades fictifs, aucun ordre, aucun paiement. Les données
# de démonstration vivent dans var\demo, à part des vraies données.
#
# Usage :  .\deploy\windows\demo.ps1             première fois : installe, crée les comptes de démo
#          .\deploy\windows\demo.ps1 -Reset      repart de zéro (nouveaux comptes, nouveaux mots de passe)
#          .\deploy\windows\demo.ps1 -Reseau     accessible depuis un autre appareil (VPS, téléphone)
param([switch]$Reset, [switch]$Reseau, [int]$Port = 8000)
Set-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not (Test-Path .\.venv\Scripts\python.exe)) {
    Write-Host "Première installation (2 à 5 minutes)..."
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { Write-Host "Python introuvable : installez Python 3.11+ (case « Add python.exe to PATH »)."; exit 1 }
}
$py = ".\.venv\Scripts\python.exe"
& $py -m pip install --quiet --disable-pip-version-check -e ".[web,saas,research]"
# La clé Anthropic de .env.ps1, si elle existe, rend le Coach et le Mentor rédigés par l'IA.
if (Test-Path .env.ps1) { . .\.env.ps1 }
$listen = if ($Reseau) { "0.0.0.0" } else { "127.0.0.1" }
$cmd = @("-m", "hedgefund.web", "demo", "--host", $listen, "--port", $Port)
if ($Reset) { $cmd += "--reset" }
Write-Host "Ouvrez http://127.0.0.1:$Port dans votre navigateur. Ctrl+C pour arrêter."
& $py @cmd
