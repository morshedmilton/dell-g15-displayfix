Add-Type -AssemblyName System.Windows.Forms
$primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen

$dm = New-Object TestDevModeW+DEVMODEW
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
$retEnum = [TestDevModeW]::EnumDisplaySettingsW($primaryScreen.DeviceName, [TestDevModeW]::ENUM_CURRENT_SETTINGS, [ref]$dm)

Write-Host ("Initial dmFields: 0x{0:X8}" -f $dm.dmFields)
Write-Host "Initial width=$($dm.dmPelsWidth), height=$($dm.dmPelsHeight), freq=$($dm.dmDisplayFrequency), bpp=$($dm.dmBitsPerPel)"

# Do not overwrite dmFields, keep full valid DEVMODE and ensure DM_DISPLAYFREQUENCY is set
$dm.dmFields = $dm.dmFields -bor [TestDevModeW]::DM_DISPLAYFREQUENCY
$dm.dmDisplayFrequency = 360
$retTest = [TestDevModeW]::ChangeDisplaySettingsExW($primaryScreen.DeviceName, [ref]$dm, [IntPtr]::Zero, [TestDevModeW]::CDS_TEST, [IntPtr]::Zero)
Write-Host "ChangeDisplaySettingsExW with full DEVMODE (CDS_TEST): ret=$retTest"
