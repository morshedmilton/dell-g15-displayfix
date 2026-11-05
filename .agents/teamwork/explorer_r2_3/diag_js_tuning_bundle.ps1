$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\427.e013fdf4eb0640ba.js"
if (Test-Path $jsPath) {
    $content = Get-Content $jsPath -Raw
    $keywords = @("startOcScan", "stopOcScan", "toggleAutoTuning", "onToggle", "isDcPower", "autoTuningStatus", "FvSvc", "FrameView")
    foreach ($kw in $keywords) {
        $idx = $content.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase)
        if ($idx -ge 0) {
            $start = [Math]::Max(0, $idx - 150)
            $len = [Math]::Min(500, $content.Length - $start)
            Write-Host "=== MATCH: $kw ==="
            Write-Host $content.Substring($start, $len)
        }
    }
}
