$jsPath = "C:\Program Files\NVIDIA Corporation\NVIDIA App\www\main.4110f620ac1963df.js"
$content = Get-Content $jsPath -Raw
$idx = $content.IndexOf('EnableBackgroundOcScan:{')
if ($idx -ge 0) {
    Write-Host $content.Substring($idx, 400)
}
