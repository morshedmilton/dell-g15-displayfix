Write-Host "=== SEARCHING NVIDIA APP WWW JAVASCRIPT FOR DRIVER DOWNLOAD STATES ==="
$wwwDir = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www"
if (Test-Path $wwwDir) {
    # Search for postprocessing or download states in js bundles
    Get-ChildItem -Path $wwwDir -Filter "*.js" | ForEach-Object {
        $m = Select-String -Path $_.FullName -Pattern "postprocessing|downloadState|isDownloading|extracting|installing" -CaseSensitive:$false
        if ($m) {
            Write-Host "File: $($_.Name) has $($m.Count) matches"
        }
    }
} else {
    Write-Host "www dir not found at $wwwDir"
}
