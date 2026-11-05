Get-ChildItem 'HKLM:\HARDWARE\ACPI' -Recurse | Select-Object Name | Select-String -Pattern 'DSDT|SSDT|MSDM|NVOP|DGPU|IGPU|MUX'
