$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js"
$content = Get-Content $jsPath -Raw
$idx = $content.IndexOf("registerPowerStatusNotifications")
if ($idx -ge 0) {
    $start = [Math]::Max(0, $idx - 150)
    $len = [Math]::Min(1000, $content.Length - $start)
    Write-Host "=== REGISTERPOWERSTATUSNOTIFICATIONS ==="
    Write-Host $content.Substring($start, $len)
}
