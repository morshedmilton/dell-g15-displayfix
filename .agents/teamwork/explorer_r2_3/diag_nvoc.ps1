Write-Host "=== SEARCHING FOR NVOC IN CXNATIVE LOGS ==="
$files = Get-ChildItem -Path "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App" -Filter "CxNative*.log" -Recurse
foreach ($f in $files) {
    Write-Host "`n--- File: $($f.FullName) ---"
    Select-String -Path $f.FullName -Pattern "NvOc" | Select-Object -First 50 | ForEach-Object { $_.Line }
}

Write-Host "=== SEARCHING FOR NVOC IN CONSOLE.LOG ==="
$c = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log"
if (Test-Path $c) {
    Select-String -Path $c -Pattern "NvOc|tuning|tune|overclock|oc" -CaseSensitive:$false | Select-Object -First 50 | ForEach-Object { $_.Line }
}
