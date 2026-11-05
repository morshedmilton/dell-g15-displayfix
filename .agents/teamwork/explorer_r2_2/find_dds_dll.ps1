$repo = "C:\Windows\System32\DriverStore\FileRepository\nvdmi.inf_amd64_56fd21da5284bbb3"
$dlls = Get-ChildItem $repo -Filter "*.dll"
foreach ($file in $dlls) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
        $unicode = [System.Text.Encoding]::Unicode.GetString($bytes)
        if ($ascii -match "Manage Display Mode" -or $unicode -match "Manage Display Mode" -or $ascii -match "Dynamic Display Switch" -or $unicode -match "Dynamic Display Switch") {
            Write-Host "Matched: $($file.Name)"
        }
    } catch {}
}
