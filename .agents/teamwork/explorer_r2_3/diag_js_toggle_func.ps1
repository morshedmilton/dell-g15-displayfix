$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\427.e013fdf4eb0640ba.js"
$content = Get-Content $jsPath -Raw
$matches = [regex]::Matches($content, '(\w*toggle\w*|autoTune\w*)\s*\([^)]*\)\s*\{[^}]{1,400}\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
foreach ($m in $matches | Select-Object -First 10) {
    Write-Host "=== FUNCTION MATCH ==="
    Write-Host $m.Value
}
