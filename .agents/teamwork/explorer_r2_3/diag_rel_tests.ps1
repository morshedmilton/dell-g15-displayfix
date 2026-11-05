$root = (Get-Location).Path
Write-Host "=== SCRIPTS FILES ==="
Get-ChildItem -Path "scripts" -Recurse -File | ForEach-Object {
    Write-Host ($_.FullName.Substring($root.Length + 1))
}

Write-Host "`n=== TESTS FILES ==="
Get-ChildItem -Path "tests" -Recurse -File | ForEach-Object {
    Write-Host ($_.FullName.Substring($root.Length + 1))
}
