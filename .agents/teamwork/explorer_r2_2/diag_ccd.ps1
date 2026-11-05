Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class CCDDiag
{
    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);
}
"@ -ErrorAction SilentlyContinue

[uint32]$p = 0
[uint32]$m = 0
$resActive = [CCDDiag]::GetDisplayConfigBufferSizes(2, [ref]$p, [ref]$m)
Write-Host "QDC_ONLY_ACTIVE_PATHS: Ret=$resActive, Paths=$p, Modes=$m"

[uint32]$pAll = 0
[uint32]$mAll = 0
$resAll = [CCDDiag]::GetDisplayConfigBufferSizes(1, [ref]$pAll, [ref]$mAll)
Write-Host "QDC_ALL_PATHS: Ret=$resAll, Paths=$pAll, Modes=$mAll"
