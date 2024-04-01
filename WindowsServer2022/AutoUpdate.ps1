# Installer le module PSWindowsUpdate si nécessaire
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)){
    Install-PackageProvider -Name NuGet -MinimunVersion 2.8.5.201 -Force
    Install-Module -Name PSWindowsUpdate -Force
}

# Importer le module PSWindowsUpdate
Import-Module PSWindowsUpdate

# Autoriser les scripts PowerShell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Rechercher les mises à jour disponibles
Write-Host "Recherche des mises à jours disponibles"
$updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot

# Afficher les mises à jour trouvées
if ($updates.Count -gt 0){
    Write-Host "Listes des mises jours disponibles :"
    $updates | Select-Object -Property Title, KB, Size | Format-Table -AutoSize
} else {
    Whrite-Host "Aucune mise à jour disponible."
}

# Installer les mises à jours
if ($updates.Count -gt 0){
    Write-Host "Installation des mises à jours..."
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot
} else {
    Write-host "Aucne mise à jour à installer."
}