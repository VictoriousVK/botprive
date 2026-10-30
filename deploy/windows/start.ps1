# Démarre la plateforme (et la redémarre automatiquement si elle s'arrête).
# Usage :  .\deploy\windows\start.ps1        (MT5 doit être ouvert, bouton "Algo Trading" activé)
Set-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (Test-Path .env.ps1) { . .\.env.ps1 }
$py = ".\.venv\Scripts\python.exe"
New-Item -ItemType Directory -Force -Path var | Out-Null
while ($true) {
    Write-Host "$(Get-Date -Format s) démarrage de la plateforme sur http://$($env:HF_HOST):$($env:HF_PORT)"
    & $py -m hedgefund.web serve --host $env:HF_HOST --port $env:HF_PORT 2>&1 | Tee-Object -FilePath var\platform.log -Append
    Write-Host "$(Get-Date -Format s) la plateforme s'est arrêtée ; redémarrage dans 10 s (Ctrl+C pour quitter)"
    Start-Sleep -Seconds 10
}
