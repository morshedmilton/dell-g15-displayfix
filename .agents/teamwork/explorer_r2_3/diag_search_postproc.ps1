$files = Get-ChildItem -Path "C:\Program Files\NVIDIA Corporation\NVIDIA App\www" -Filter "*.js"
foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw
    $idx = $content.IndexOf("postprocessing", [System.StringComparison]::OrdinalIgnoreCase)
    if ($idx -ge 0) {
        Write-Host "File: $($f.Name) Match at $idx"
        $start = [Math]::Max(0, $idx - 100)
        $len = [Math]::Min(300, $content.Length - $start)
        Write-Host $content.Substring($start, $len)
    }
}
