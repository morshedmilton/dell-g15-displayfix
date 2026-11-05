Write-Host "=== PLUGINS\OC DIR ==="
Get-ChildItem -Path "C:\Program Files\NVIDIA Corporation\NVIDIA App\Plugins\oc" -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "=== _OVERCLOCKINGNVC.JSON ==="
$json = "C:\Program Files\NVIDIA Corporation\NVIDIA App\Plugins\oc\_OverClockingNvc.json"
if (Test-Path $json) { Get-Content $json }

Write-Host "=== NVCONTAINER PLUGINS ==="
Get-ChildItem -Path "C:\Program Files\NVIDIA Corporation\NvContainer\Plugins" -Recurse -ErrorAction SilentlyContinue | Format-Table -AutoSize
