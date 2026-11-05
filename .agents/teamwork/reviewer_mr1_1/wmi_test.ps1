$outputFile = Join-Path $PSScriptRoot 'wmi_test_result.txt'
try {
    $inst = Get-CimInstance -Namespace root\wmi -ClassName NvWmiBrightness -ErrorAction Stop
    $res = Invoke-CimMethod -InputObject $inst -MethodName NvGetSetBrightnessLevel -Arguments @{ inArg = 1; Level = 58 } -ErrorAction Stop
    $readBack = Invoke-CimMethod -InputObject $inst -MethodName NvGetSetBrightnessLevel -Arguments @{ inArg = 0; Level = 0 } -ErrorAction Stop
    $info = @"
SUCCESS: CimMethod succeeded
Result: $($res.Result)
ReadBack Result: $($readBack.Result)
ReadBack Level: $($readBack.Level)
"@
    Set-Content -Path $outputFile -Value $info
} catch {
    Set-Content -Path $outputFile -Value "ERROR: $_`n$($_.ScriptStackTrace)"
}
