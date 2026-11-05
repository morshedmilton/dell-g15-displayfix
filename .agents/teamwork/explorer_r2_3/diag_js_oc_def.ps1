$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js"
$content = Get-Content $jsPath -Raw
$matches = [regex]::Matches($content, 'EnableBackgroundOcScan[":\w\s,]{1,200}')
foreach ($m in $matches) {
    Write-Host "=== MATCH ==="
    Write-Host $m.Value
}
