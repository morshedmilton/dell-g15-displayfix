Add-Type -AssemblyName System.Windows.Forms
$primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen

$dm = New-Object TestDevModeW+DEVMODEW
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
$retEnum = [TestDevModeW]::EnumDisplaySettingsW($primaryScreen.DeviceName, [TestDevModeW]::ENUM_CURRENT_SETTINGS, [ref]$dm)

$dm | Format-List *
