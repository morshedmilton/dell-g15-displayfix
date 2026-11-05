$dll = "C:\Windows\System32\DriverStore\FileRepository\nvdmi.inf_amd64_56fd21da5284bbb3\nvgames.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)

function Extract-Strings($b, [System.Text.Encoding]$enc, $minLen=4) {
    $str = $enc.GetString($b)
    $regex = [System.Text.RegularExpressions.Regex]::new("[\w\s\.\-:\(\)\\/]{$minLen,}")
    return $regex.Matches($str) | ForEach-Object { $_.Value.Trim() }
}

$strsA = Extract-Strings $bytes ([System.Text.Encoding]::ASCII)
$strsW = Extract-Strings $bytes ([System.Text.Encoding]::Unicode)
$all = $strsA + $strsW | Sort-Object -Unique

Write-Host "Total strings extracted: $($all.Count)"
$matched = $all | Where-Object { $_ -match 'Manage Display Mode|Optimus|Automatic Select|GPU only|DDS|Mux|Advanced Optimus|gray|disable' }
$matched | Select-Object -First 50
