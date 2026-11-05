Add-Type -AssemblyName System.Windows.Forms
$primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen

$dm = New-Object TestDevModeW+DEVMODEW
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
$retEnum = [TestDevModeW]::EnumDisplaySettingsW($primaryScreen.DeviceName, [TestDevModeW]::ENUM_CURRENT_SETTINGS, [ref]$dm)

$dm.dmFields = [TestDevModeW]::DM_DISPLAYFREQUENCY
$dm.dmDisplayFrequency = 360
$retTest = [TestDevModeW]::ChangeDisplaySettingsExW($primaryScreen.DeviceName, [ref]$dm, [IntPtr]::Zero, [TestDevModeW]::CDS_TEST, [IntPtr]::Zero)
Write-Host "ChangeDisplaySettingsExW with DeviceName (CDS_TEST): ret=$retTest"
