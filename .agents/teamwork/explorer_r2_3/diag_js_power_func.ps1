$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js"
$content = Get-Content $jsPath -Raw
$matches = [regex]::Matches($content, "registerPowerStatusNotifications\([^)]*\)\s*\{[^}]{1,400}\}")
foreach ($m in $matches) {
    Write-Host "=== MATCH ==="
    Write-Host $m.Value
}
