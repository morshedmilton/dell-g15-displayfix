Write-Host "=== SCRIPTS DIRECTORY ==="
Get-ChildItem -Path "scripts" -Recurse -File | Select-Object FullName, Length | Format-Table -AutoSize

Write-Host "=== TESTS DIRECTORY ==="
Get-ChildItem -Path "tests" -Recurse -File | Select-Object FullName, Length | Format-Table -AutoSize
