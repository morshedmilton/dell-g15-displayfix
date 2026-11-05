$dllPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\Plugins\oc\_OverClockingNvc.dll"
if (Test-Path $dllPath) {
    # Search for error messages or log strings in the binary
    $bytes = [System.IO.File]::ReadAllBytes($dllPath)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $matches = [regex]::Matches($text, "([A-Za-z0-9_]{3,30}(?:Failed|Error|Lock|Timeout|Scanner|Status|Power|Limit)[A-Za-z0-9_]{0,30})")
    Write-Host "Sample matches in _OverClockingNvc.dll:"
    $matches | Select-Object -Unique -First 30 | ForEach-Object { $_.Value }
}
