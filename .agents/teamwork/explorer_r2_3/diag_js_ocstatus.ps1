$jsFiles = @(
    "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js",
    "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\427.e013fdf4eb0640ba.js"
)
foreach ($f in $jsFiles) {
    $content = Get-Content $f -Raw
    $idx = $content.IndexOf("ocStatus")
    while ($idx -ge 0) {
        $start = [Math]::Max(0, $idx - 100)
        $len = [Math]::Min(300, $content.Length - $start)
        Write-Host "=== MATCH in $([System.IO.Path]::GetFileName($f)) at $idx ==="
        Write-Host $content.Substring($start, $len)
        $idx = $content.IndexOf("ocStatus", $idx + 1)
    }
}
