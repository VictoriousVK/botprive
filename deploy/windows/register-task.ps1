# Lance automatiquement la plateforme à l'ouverture de session Windows (utile sur un VPS).
# Exécuter une fois dans PowerShell (en tant qu'utilisateur qui fait tourner MT5) :
#   .\deploy\windows\register-task.ps1
# MT5 et la plateforme doivent tourner dans la MÊME session utilisateur : sur un VPS, fermez la
# fenêtre Bureau à distance au lieu de vous déconnecter, pour que la session reste active.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$root\deploy\windows\start.ps1`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName "HedgeFundPlatform" -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Tâche 'HedgeFundPlatform' enregistrée : la plateforme démarrera à chaque ouverture de session."
