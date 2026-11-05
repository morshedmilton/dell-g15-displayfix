Write-Host "=== CONSOLE.LOG (LAST 50 LINES) ==="
$f = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log"
if (Test-Path $f) { Get-Content $f -Tail 50 }

Write-Host "`n=== DEBUG.LOG (LAST 50 LINES) ==="
$f = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\debug.log"
if (Test-Path $f) { Get-Content $f -Tail 50 }

Write-Host "`n=== NVDRIVERUPDATECHECK.LOG (LAST 50 LINES) ==="
$f = "C:\ProgramData\NVIDIA Corporation\NVIDIA App\NvDriverUpdateCheck.log"
if (Test-Path $f) { Get-Content $f -Tail 50 }

Write-Host "`n=== CXNATIVE_NVIDIA APP.LOG (LAST 50 LINES) ==="
$f = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\CxNative_NVIDIA App.log"
if (Test-Path $f) { Get-Content $f -Tail 50 }
