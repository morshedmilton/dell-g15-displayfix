# Probe WMI and NvBrightness selftest
& "c:\ProgramData\DisplayFix\NvBrightness.exe" --selftest
$selftestPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "nvbrightness-selftest.txt")
if (Test-Path $selftestPath) {
    Write-Host "--- NvBrightness --selftest output:"
    Get-Content $selftestPath
}

Write-Host "`n--- Querying root\wmi classes:"
Get-CimClass -Namespace 'root\wmi' | Where-Object CimClassName -match 'Nv|Bright|Monitor' | Select-Object CimClassName

Write-Host "`n--- Querying Win32_VideoController:"
Get-CimInstance Win32_VideoController | Select-Object Caption, Status, PNPDeviceID

Write-Host "`n--- Querying NvWmi:"
Get-CimInstance -Namespace 'root\wmi' -ClassName 'NvWmiBrightness' -ErrorAction Continue | Format-List
