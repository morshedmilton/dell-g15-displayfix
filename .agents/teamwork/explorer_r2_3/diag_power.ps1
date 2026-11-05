Write-Host "=== POWER STATUS PROBE ==="
Get-CimInstance -ClassName BatteryStatus -Namespace root\wmi -ErrorAction SilentlyContinue | Format-List
Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Format-List BatteryStatus, PowerManagementStatus, Status, EstimatedChargeRemaining

Write-Host "=== NVOC POWER STATUS LOG DETAILS ==="
Select-String -Path "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\CxNative_NVIDIA App.log" -Pattern "Power" |
    ForEach-Object { $_.Line }
Select-String -Path "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log" -Pattern "Power" |
    ForEach-Object { $_.Line }
