$files = @(
    "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\427.e013fdf4eb0640ba.js",
    "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js"
)
foreach ($f in $files) {
    if (Test-Path $f) {
        $content = Get-Content $f -Raw
        $idx = $content.IndexOf("isDcPowerMode")
        while ($idx -ge 0) {
            $start = [Math]::Max(0, $idx - 150)
            $len = [Math]::Min(500, $content.Length - $start)
            Write-Host "=== MATCH in $([System.IO.Path]::GetFileName($f)) at $idx ==="
            Write-Host $content.Substring($start, $len)
            $idx = $content.IndexOf("isDcPowerMode", $idx + 1)
        }
    }
}
