$cheminCsv = "C:\Users\Administrateur\Documents\OrdinateursAD.Csv"

Import-Module ActiveDirectory

$ordinateursCsv = Import-Csv -Path $cheminCsv

foreach ($ordinateur in $ordinateursCsv) {
    $ordinateurExistant = Get-ADComputer -Filter "Name -eq '$($ordinateur.NomOrdinateur)'"

    if ($ordinateurExistant -eq $null){
        try{
            New-ADComputer -Name $ordinateur.NomOrdinateur -Path $ordinateur.Path
            Write-Host "Ordinateur agouté : $($ordinateurs.NomOrdinateur)"
        } catch {
            Write-Host "Erreur lors de l'ajout de l'ordinateur : $($ordinateur.NomOrdinateur). Détails de l'erreur : $($_.Exception.Message)"
        ｝
    } else {
        write-Host "L'ordinateur existe déjà : $($ordinateur.NomOrdinateur)"
    }
}
    
Write-Host "Liste de tous les ordinateurs dans l'AD :"
Get-ADComputer -Filter * -Property * | Format-Table Name, DistinguishedName -Autosize