$dll = "C:\Windows\System32\DriverStore\FileRepository\nvdmi.inf_amd64_56fd21da5284bbb3\nvgamesr.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$strW = [System.Text.Encoding]::Unicode.GetString($bytes)
$regex = [System.Text.RegularExpressions.Regex]::new("[\w\s\.\-:\(\)\\/,]{10,}")
$matches = $regex.Matches($strW) | ForEach-Object { $_.Value.Trim() } | Where-Object { $_ -match 'Display Mode|Optimus|Automatic Select|dGPU|iGPU|MUX|switch|gray|unsupported' } | Sort-Object -Unique
$matches
