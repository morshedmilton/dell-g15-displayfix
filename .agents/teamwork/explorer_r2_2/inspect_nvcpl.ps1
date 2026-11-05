$path = "C:\Program Files\WindowsApps\NVIDIACorp.NVIDIAControlPanel_8.1.969.0_x64__56jybvy8sckqj\nvcplui.exe"
$bytes = [System.IO.File]::ReadAllBytes($path)
$str = [System.Text.Encoding]::Unicode.GetString($bytes)
$matches = [System.Text.RegularExpressions.Regex]::Matches($str, 'Manage Display Mode|[A-Za-z ]{0,30}Optimus[A-Za-z ]{0,30}|Automatic Select|NVIDIA GPU only')
$matches | ForEach-Object { $_.Value } | Sort-Object -Unique
