$tables = 'SSD1','SSD2','SSD3','SSD4','SSD5','SSD6','SSD7','SSD8','SSD9','SSDA','SSDB','SSDC','SSDD','SSDE','SSDT'
foreach ($t in $tables) {
    if (Test-Path "HKLM:\HARDWARE\ACPI\$t") {
        Get-ChildItem "HKLM:\HARDWARE\ACPI\$t" | ForEach-Object {
            $oem = $_.PSChildName
            Get-ChildItem $_.PSPath | ForEach-Object {
                [PSCustomObject]@{
                    Table = $t
                    OemId = $oem
                    TableId = $_.PSChildName
                }
            }
        }
    }
}
