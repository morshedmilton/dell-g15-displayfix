Write-Host "=== SEARCHING CONSOLE.LOG FOR PERFORMANCE / TUNING ==="
$c = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log"
if (Test-Path $c) {
    Select-String -Path $c -Pattern "performance|tune|tuning|nvoc|overclock" -CaseSensitive:$false |
        ForEach-Object { $_.Line }
}
$cb = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log.bak"
if (Test-Path $cb) {
    Write-Host "`n=== IN CONSOLE.LOG.BAK ==="
    Select-String -Path $cb -Pattern "performance|tune|tuning|nvoc|overclock" -CaseSensitive:$false |
        ForEach-Object { $_.Line }
}
