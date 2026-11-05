$dll = "C:\Windows\System32\DriverStore\FileRepository\nvdmi.inf_amd64_56fd21da5284bbb3\nvgames.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
$unicode = [System.Text.Encoding]::Unicode.GetString($bytes)

# Find occurrences of CDisplayMuxPropertyPage
$matchesA = [System.Text.RegularExpressions.Regex]::Matches($ascii, '(?s).{0,200}CDisplayMuxPropertyPage.{0,300}')
Write-Host "Found ASCII matches: $($matchesA.Count)"
foreach ($m in $matchesA | Select-Object -First 5) {
    Write-Host "--- ASCII Match ---"
    Write-Host ($m.Value -replace '[^\x20-\x7E\r\n]', '.')
}

$matchesW = [System.Text.RegularExpressions.Regex]::Matches($unicode, '(?s).{0,200}CDisplayMuxPropertyPage.{0,300}')
Write-Host "Found Unicode matches: $($matchesW.Count)"
foreach ($m in $matchesW | Select-Object -First 5) {
    Write-Host "--- Unicode Match ---"
    Write-Host ($m.Value -replace '[^\x20-\x7E\r\n]', '.')
}
