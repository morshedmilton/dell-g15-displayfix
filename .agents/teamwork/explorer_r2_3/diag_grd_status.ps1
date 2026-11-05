Write-Host "=== GRD DOWNLOAD.JSON ==="
if (Test-Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd\download.json") {
    Get-Content "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd\download.json"
}

Write-Host "`n=== GRD POSTPROCESSING.JSON ==="
if (Test-Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd\postprocessing.json") {
    Get-Content "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd\postprocessing.json"
}

Write-Host "`n=== OTHER STATUS FILES IN UPDATEFRAMEWORK ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status" -Recurse -File |
    ForEach-Object {
        Write-Host "--- File: $($_.FullName) ---"
        Get-Content $_.FullName
    }

Write-Host "`n=== OTA-ARTIFACTS GRD CONTENTS ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts\grd" -Recurse |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
