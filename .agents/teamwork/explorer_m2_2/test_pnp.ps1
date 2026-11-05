Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class TestPInvoke
{
    [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CM_Locate_DevNodeW(out uint pdnDevInst, string pDeviceID, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Get_DevNode_Status(out uint pulStatus, out uint pulProblemNumber, uint dnDevInst, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Get_Parent(out uint pdnDevInst, uint dnDevInst, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CM_Get_Device_IDW(uint dnDevInst, StringBuilder Buffer, uint BufferLen, uint ulFlags);
}
"@

$devInst = [uint32]0
$rc = [TestPInvoke]::CM_Locate_DevNodeW([ref]$devInst, "DISPLAY\AUOAA9F\5&39808DAE&2&UID4353", 0)
Write-Host "Locate NVIDIA node: rc=$rc, devInst=$devInst"
if ($rc -eq 0) {
    $status = [uint32]0; $prob = [uint32]0
    $rcStatus = [TestPInvoke]::CM_Get_DevNode_Status([ref]$status, [ref]$prob, $devInst, 0)
    Write-Host ("Status: rc={0}, status=0x{1:X8}, prob={2}" -f $rcStatus, $status, $prob)

    $parentInst = [uint32]0
    $rcParent = [TestPInvoke]::CM_Get_Parent([ref]$parentInst, $devInst, 0)
    Write-Host "Parent: rc=$rcParent, parentInst=$parentInst"
    if ($rcParent -eq 0) {
        $sb = New-Object System.Text.StringBuilder 512
        [TestPInvoke]::CM_Get_Device_IDW($parentInst, $sb, $sb.Capacity, 0) | Out-Null
        Write-Host "Parent ID: $($sb.ToString())"
    }
}

$devInstGhost = [uint32]0
# Locate normal flag (0x00)
$rcGhost0 = [TestPInvoke]::CM_Locate_DevNodeW([ref]$devInstGhost, "DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688", 0)
Write-Host "Locate Intel ghost node (normal): rc=$rcGhost0, devInst=$devInstGhost"
# Locate phantom flag (0x01)
$rcGhost1 = [TestPInvoke]::CM_Locate_DevNodeW([ref]$devInstGhost, "DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688", 1)
Write-Host "Locate Intel ghost node (phantom): rc=$rcGhost1, devInst=$devInstGhost"
if ($rcGhost1 -eq 0) {
    $status = [uint32]0; $prob = [uint32]0
    $rcStatus = [TestPInvoke]::CM_Get_DevNode_Status([ref]$status, [ref]$prob, $devInstGhost, 0)
    Write-Host ("Ghost Status: rc={0}, status=0x{1:X8}, prob={2}" -f $rcStatus, $status, $prob)
}
