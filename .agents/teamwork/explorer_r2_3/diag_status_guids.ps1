Write-Host "=== CHECK GUID FOLDERS IN STATUS ==="
$statusDirs = Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status" -Directory
foreach ($d in $statusDirs) {
    Write-Host "Directory: $($d.Name)"
    Get-ChildItem -Path $d.FullName | ForEach-Object {
        Write-Host "   File: $($_.Name), Size: $($_.Length), LastWrite: $($_.LastWriteTime)"
        if ($_.Length -lt 1000) {
            Get-Content $_.FullName | Write-Host
        }
    }
}
