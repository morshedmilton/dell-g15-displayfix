Write-Host "=== CHECKING SETUP.EXE IN POST-PROCESSING ==="
$setupPath = "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts\grd\post-processing\449b11b95561d3a9ac74e4a18a7eb2cb\setup.exe"
if (Test-Path $setupPath) {
    Get-Item $setupPath | Select-Object FullName, Length, LastWriteTime
} else {
    Write-Host "setup.exe DOES NOT EXIST at $setupPath!"
}

Write-Host "=== CHECKING 449B... FOLDER IN POST-PROCESSING ==="
$postProcDir = "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts\grd\post-processing\449b11b95561d3a9ac74e4a18a7eb2cb"
if (Test-Path $postProcDir) {
    Get-ChildItem -Path $postProcDir -Recurse | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
} else {
    Write-Host "Folder does not exist: $postProcDir"
}

Write-Host "=== CHECKING 449B... FOLDER IN OTA-ARTIFACTS\GRD ==="
$grdDir = "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts\grd\449b11b95561d3a9ac74e4a18a7eb2cb"
if (Test-Path $grdDir) {
    Get-ChildItem -Path $grdDir -Recurse | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
} else {
    Write-Host "Folder does not exist: $grdDir"
}
