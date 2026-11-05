Add-Type -AssemblyName System.Windows.Forms
$primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
Write-Host "Primary screen device name: $($primaryScreen.DeviceName)"

$dm = New-Object TestDevModeW+DEVMODEW
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
$retEnum = [TestDevModeW]::EnumDisplaySettingsW($primaryScreen.DeviceName, [TestDevModeW]::ENUM_CURRENT_SETTINGS, [ref]$dm)
Write-Host "EnumDisplaySettingsW ret=$retEnum, freq=$($dm.dmDisplayFrequency), width=$($dm.dmPelsWidth), height=$($dm.dmPelsHeight)"

# Test with null vs device name
$dmNull = New-Object TestDevModeW+DEVMODEW
$dmNull.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dmNull)
$retEnumNull = [TestDevModeW]::EnumDisplaySettingsW([string]::Empty, [TestDevModeW]::ENUM_CURRENT_SETTINGS, [ref]$dmNull)
Write-Host "EnumDisplaySettingsW empty string ret=$retEnumNull, freq=$($dmNull.dmDisplayFrequency)"
