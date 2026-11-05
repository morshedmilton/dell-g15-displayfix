$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\988.e82ce2767f3e9951.js"
if (Test-Path $jsPath) {
    $content = Get-Content $jsPath -Raw
    $idx = $content.IndexOf("GetPostProcessingStatus")
    if ($idx -ge 0) {
        $start = [Math]::Max(0, $idx - 200)
        $len = [Math]::Min(1500, $content.Length - $start)
        Write-Host "=== GETPOSTPROCESSINGSTATUS CONTEXT ==="
        Write-Host $content.Substring($start, $len)
    }

    $idx2 = $content.IndexOf("getPostProcessedInstallerLocation")
    if ($idx2 -ge 0) {
        $start = [Math]::Max(0, $idx2 - 200)
        $len = [Math]::Min(1500, $content.Length - $start)
        Write-Host "`n=== GETPOSTPROCESSEDINSTALLERLOCATION CONTEXT ==="
        Write-Host $content.Substring($start, $len)
    }
}
