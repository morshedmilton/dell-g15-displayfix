Write-Host "=== CRASH DUMPS IN PROGRAMDATA ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\CrashDumps" -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize

Write-Host "=== CRASH DUMPS IN LOCALAPPDATA CRASHDUMPS ==="
Get-ChildItem -Path "$env:LOCALAPPDATA\CrashDumps" -Filter "*nv*" -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
