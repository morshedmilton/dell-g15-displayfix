Write-Host "=== LIST ALL FILES IN UPDATEFRAMEWORK ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework" -Recurse |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize

Write-Host "=== CHECK PROFILE CATALOG & REGISTRY ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\profile-catalog", "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\registry" -Recurse -File |
    ForEach-Object {
        Write-Host "--- $($_.FullName) ---"
        Get-Content $_.FullName
    }

Write-Host "=== CHECK ALL STATUS FILES CONTENT ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status" -Recurse -File |
    ForEach-Object {
        Write-Host "--- $($_.FullName) ---"
        Get-Content $_.FullName
    }
