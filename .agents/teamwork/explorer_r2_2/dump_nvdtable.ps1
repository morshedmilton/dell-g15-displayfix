$sub = Get-Item 'HKLM:\HARDWARE\ACPI\SSDA\DELL\NvdTable\*' | Select-Object -First 1
$bytes = (Get-ItemProperty $sub.PSPath).'00000000'
Write-Host "NvdTable Length: $($bytes.Length) bytes"

# Extract ASCII strings of 4+ characters
$str = [System.Text.Encoding]::ASCII.GetString($bytes)
$matches = [System.Text.RegularExpressions.Regex]::Matches($str, '[A-Za-z0-9_]{4,}')
Write-Host "Total matches: $($matches.Count)"
$unique = $matches | ForEach-Object { $_.Value } | Sort-Object -Unique
$unique | Where-Object { $_ -match 'NV|DDS|MUX|DISP|DGPU|IGPU|OPT|HYB|SWIT|GPU' } | Format-Table -AutoSize
