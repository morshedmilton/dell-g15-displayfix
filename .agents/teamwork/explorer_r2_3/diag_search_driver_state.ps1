$mainJs = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js"
if (Test-Path $mainJs) {
    # Search around driver download state
    $content = Get-Content $mainJs -Raw
    $indices = @()
    $keyword = "postprocessing"
    $idx = $content.IndexOf($keyword)
    while ($idx -ge 0) {
        $start = [Math]::Max(0, $idx - 200)
        $len = [Math]::Min(500, $content.Length - $start)
        Write-Host "--- Match near $idx ---"
        Write-Host $content.Substring($start, $len)
        $idx = $content.IndexOf($keyword, $idx + 1)
    }
}
