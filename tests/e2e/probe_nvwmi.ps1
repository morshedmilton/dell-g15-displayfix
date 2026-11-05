# tests/e2e/probe_nvwmi.ps1
$inst = Get-CimInstance -Namespace 'root\wmi' -ClassName 'NvWmiBrightness'
$results = @()
foreach ($lvl in @(18, 50, 58, 63, 70, 95, 100)) {
    $writeRes = Invoke-CimMethod -InputObject $inst -MethodName 'NvGetSetBrightnessLevel' -Arguments @{ inArg = [uint32]1; Level = [uint32]$lvl }
    Start-Sleep -Milliseconds 150
    $readRes = Invoke-CimMethod -InputObject $inst -MethodName 'NvGetSetBrightnessLevel' -Arguments @{ inArg = [uint32]0; Level = [uint32]0 }
    $results += "Written: $lvl (WriteRet: $($writeRes.Result)) -> ReadBack: $($readRes.Result)"
}
# Restore 58
Invoke-CimMethod -InputObject $inst -MethodName 'NvGetSetBrightnessLevel' -Arguments @{ inArg = [uint32]1; Level = [uint32]58 } | Out-Null
$results | Out-File -Encoding utf8 C:\ProgramData\DisplayFix\logs\nvwmi_readback.txt
