$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js"
$content = Get-Content $jsPath -Raw
$idx = $content.IndexOf("cancelledGpuBusy")
if ($idx -ge 0) {
    $start = [Math]::Max(0, $idx - 300)
    $len = [Math]::Min(800, $content.Length - $start)
    Write-Host "=== CANCELLEDGPUBUSY CONTEXT ==="
    Write-Host $content.Substring($start, $len)
}
