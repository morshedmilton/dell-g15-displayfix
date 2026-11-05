$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\988.e82ce2767f3e9951.js"
$content = Get-Content $jsPath -Raw
$matches = [regex]::Matches($content, "(var\s+\w+|\w+)\s*=\s*\{\s*None:\s*0[^}]*\}")
foreach ($m in $matches) {
    Write-Host "Enum: $($m.Value)"
}

# Also search for PostProcessing or Download enum
$matches2 = [regex]::Matches($content, "\b(Completed|InProgress|Failed|Pending|Downloading)\b.{0,50}")
foreach ($m in $matches2 | Select-Object -First 10) {
    Write-Host "Match: $($m.Value)"
}
