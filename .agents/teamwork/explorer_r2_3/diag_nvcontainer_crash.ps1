Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; StartTime=(Get-Date).AddDays(-3)} |
    Where-Object { $_.Message -match "nvcontainer" } |
    ForEach-Object {
        Write-Host "Time: $($_.TimeCreated)"
        Write-Host $_.Message
        Write-Host "-------------------------------------"
    }
