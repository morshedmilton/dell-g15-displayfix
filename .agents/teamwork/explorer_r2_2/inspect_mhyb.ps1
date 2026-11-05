$sub = Get-Item 'HKLM:\HARDWARE\ACPI\SSDA\DELL\NvdTable\*' | Select-Object -First 1
$bytes = (Get-ItemProperty $sub.PSPath).'00000000'

# Search for MHYB in bytes
$pattern = [System.Text.Encoding]::ASCII.GetBytes("MHYB")
for ($i = 0; $i -lt $bytes.Length - 4; $i++) {
    $match = $true
    for ($j = 0; $j -lt 4; $j++) {
        if ($bytes[$i + $j] -ne $pattern[$j]) { $match = $false; break }
    }
    if ($match) {
        Write-Host "Found MHYB at offset $i"
        $start = [Math]::Max(0, $i - 32)
        $len = [Math]::Min($bytes.Length - $start, 96)
        $slice = $bytes[$start..($start + $len - 1)]
        $hex = ($slice | ForEach-Object { $_.ToString("X2") }) -join " "
        $chars = ($slice | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } }) -join ""
        Write-Host "Hex: $hex"
        Write-Host "Ascii: $chars"
    }
}
