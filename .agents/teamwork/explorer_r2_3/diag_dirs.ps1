Write-Host "=== PROGRAMDATA NVIDIA DIRS ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation" -ErrorAction SilentlyContinue | Select-Object Name, FullName, LastWriteTime

Write-Host "=== LOCALAPPDATA NVIDIA DIRS ==="
Get-ChildItem -Path "$env:LOCALAPPDATA\NVIDIA Corporation" -ErrorAction SilentlyContinue | Select-Object Name, FullName, LastWriteTime

Write-Host "=== APPDATA NVIDIA DIRS ==="
Get-ChildItem -Path "$env:APPDATA\NVIDIA Corporation" -ErrorAction SilentlyContinue | Select-Object Name, FullName, LastWriteTime

Write-Host "=== CHECK DOWNLOADER DIR ==="
if (Test-Path "C:\ProgramData\NVIDIA Corporation\Downloader") {
    Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\Downloader" -Recurse | Select-Object FullName, Length, LastWriteTime
} else {
    Write-Host "Downloader dir not found at C:\ProgramData\NVIDIA Corporation\Downloader"
}

Write-Host "=== CHECK NVIDIA APP PROGRAMDATA ==="
if (Test-Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App") {
    Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App" -Recurse -Depth 3 | Select-Object FullName, Length, LastWriteTime
}

Write-Host "=== CHECK NVIDIA APP LOCALAPPDATA ==="
if (Test-Path "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App") {
    Get-ChildItem -Path "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App" -Recurse -Depth 2 | Select-Object FullName, Length, LastWriteTime
}
