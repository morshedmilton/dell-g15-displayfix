$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\988.e82ce2767f3e9951.js"
$content = Get-Content $jsPath -Raw
$idx = $content.IndexOf("postProcessingStatusEnum")
if ($idx -ge 0) {
    $start = [Math]::Max(0, $idx - 300)
    $len = [Math]::Min(1200, $content.Length - $start)
    Write-Host $content.Substring($start, $len)
}
