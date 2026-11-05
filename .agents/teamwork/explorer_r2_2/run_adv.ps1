$files = Get-ChildItem "tests\e2e\tier5_adversarial" -Filter "*.ps1"
foreach ($f in $files) {
    Write-Host "Running $($f.Name)..."
    & $f.FullName
}
