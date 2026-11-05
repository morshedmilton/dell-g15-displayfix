# tests/e2e/common/TestFramework.ps1
# High-performance, zero-dependency test assertion framework for Dell G15 DisplayFix E2E tests

$commonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:ProjectRoot = (Get-Item (Join-Path $commonDir '..\..\..')).FullName

if (-not (Get-Variable -Name 'GlobalTestContext' -Scope Global -ErrorAction SilentlyContinue)) {
    $global:GlobalTestContext = @{
        Suites = [System.Collections.Generic.List[PSObject]]::new()
        CurrentSuite = $null
        CurrentTier = 'Unassigned'
        JsonMode = $false
        VerboseMode = $false
        TotalPassed = 0
        TotalFailed = 0
        TotalSkipped = 0
        ProjectRoot = $global:ProjectRoot
    }
}

function Set-TestTier {
    param([string]$Tier)
    $global:GlobalTestContext.CurrentTier = $Tier
}

function Describe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Fixture
    )

    $suiteObj = [PSCustomObject]@{
        Suite      = $Name
        Tier       = $global:GlobalTestContext.CurrentTier
        File       = $MyInvocation.ScriptName
        Tests      = [System.Collections.Generic.List[PSObject]]::new()
        Passed     = 0
        Failed     = 0
        Skipped    = 0
        DurationMs = 0
    }

    $prevSuite = $global:GlobalTestContext.CurrentSuite
    $global:GlobalTestContext.CurrentSuite = $suiteObj
    $global:GlobalTestContext.Suites.Add($suiteObj)

    if (-not $global:GlobalTestContext.JsonMode) {
        Write-Host ""
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host " SUITE: $Name [$($suiteObj.Tier)]" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor Cyan
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Fixture
    }
    catch {
        Write-Host "  [SUITE ERROR] Unhandled exception in suite fixture: $_" -ForegroundColor Red
        if ($global:GlobalTestContext.VerboseMode) {
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
        }
    }
    finally {
        $sw.Stop()
        $suiteObj.DurationMs = [int]$sw.ElapsedMilliseconds
        $global:GlobalTestContext.CurrentSuite = $prevSuite
    }
}

function It {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestBlock
    )

    $currentSuite = $global:GlobalTestContext.CurrentSuite
    $testResult = [PSCustomObject]@{
        Name         = $Name
        Status       = 'PASS'
        DurationMs   = 0
        ErrorMessage = $null
        StackTrace   = $null
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $TestBlock
        $sw.Stop()
        $testResult.DurationMs = [int]$sw.ElapsedMilliseconds
        $testResult.Status = 'PASS'
        $global:GlobalTestContext.TotalPassed++
        if ($currentSuite) { $currentSuite.Passed++ }

        if (-not $global:GlobalTestContext.JsonMode) {
            Write-Host "  [PASS] $Name ($($testResult.DurationMs)ms)" -ForegroundColor Green
        }
    }
    catch [System.Management.Automation.MethodInvocationException], [System.Exception] {
        $sw.Stop()
        $testResult.DurationMs = [int]$sw.ElapsedMilliseconds
        $testResult.Status = 'FAIL'
        $testResult.ErrorMessage = $_.Exception.Message
        $testResult.StackTrace = $_.ScriptStackTrace
        $global:GlobalTestContext.TotalFailed++
        if ($currentSuite) { $currentSuite.Failed++ }

        if (-not $global:GlobalTestContext.JsonMode) {
            Write-Host "  [FAIL] $Name ($($testResult.DurationMs)ms)" -ForegroundColor Red
            Write-Host "         Reason: $($_.Exception.Message)" -ForegroundColor DarkRed
            if ($global:GlobalTestContext.VerboseMode) {
                Write-Host "         $($_.ScriptStackTrace)" -ForegroundColor DarkGray
            }
        }
    }

    if ($currentSuite) {
        $currentSuite.Tests.Add($testResult)
    }
}

function Skip-Test {
    param([string]$Reason)
    $currentSuite = $global:GlobalTestContext.CurrentSuite
    $testResult = [PSCustomObject]@{
        Name         = "SKIPPED"
        Status       = 'SKIP'
        DurationMs   = 0
        ErrorMessage = $Reason
        StackTrace   = $null
    }
    $global:GlobalTestContext.TotalSkipped++
    if ($currentSuite) {
        $currentSuite.Skipped++
        $currentSuite.Tests.Add($testResult)
    }
    if (-not $global:GlobalTestContext.JsonMode) {
        Write-Host "  [SKIP] $Reason" -ForegroundColor Yellow
    }
}

# --- Assertions ---

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [string]$Message = "Expected condition to be True, but was False"
    )
    if (-not $Condition) {
        throw [System.Exception]::new("Assert-True failed: $Message")
    }
}

function Assert-False {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [string]$Message = "Expected condition to be False, but was True"
    )
    if ($Condition) {
        throw [System.Exception]::new("Assert-False failed: $Message")
    }
}

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message = "Expected equality"
    )
    if ($Actual -ne $Expected) {
        throw [System.Exception]::new("Assert-Equal failed: $Message. Expected <$Expected> (type: $(if ($Expected) { $Expected.GetType().Name } else { 'null' })), Actual <$Actual> (type: $(if ($Actual) { $Actual.GetType().Name } else { 'null' }))")
    }
}

function Assert-NotEqual {
    param(
        $Actual,
        $Expected,
        [string]$Message = "Expected inequality"
    )
    if ($Actual -eq $Expected) {
        throw [System.Exception]::new("Assert-NotEqual failed: $Message. Both were <$Actual>")
    }
}

function Assert-InRange {
    param(
        [double]$Actual,
        [double]$Min,
        [double]$Max,
        [string]$Message = "Expected value to be within range"
    )
    if ($Actual -lt $Min -or $Actual -gt $Max) {
        throw [System.Exception]::new("Assert-InRange failed: $Message. Value <$Actual> is outside [$Min, $Max]")
    }
}

function Assert-Match {
    param(
        [string]$Actual,
        [string]$Pattern,
        [string]$Message = "Expected string to match regex"
    )
    if ($Actual -notmatch $Pattern) {
        throw [System.Exception]::new("Assert-Match failed: $Message. String <$Actual> does not match pattern <$Pattern>")
    }
}

function Assert-NotNull {
    param(
        $Actual,
        [string]$Message = "Expected value not to be null or empty"
    )
    if ($null -eq $Actual -or ($Actual -is [string] -and [string]::IsNullOrWhiteSpace($Actual))) {
        throw [System.Exception]::new("Assert-NotNull failed: $Message")
    }
}

function Assert-FileExists {
    param(
        [string]$Path,
        [string]$Message = "Expected file to exist"
    )
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw [System.Exception]::new("Assert-FileExists failed: $Message. Path not found: <$Path>")
    }
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Message = "Expected path to exist"
    )
    if (-not (Test-Path -Path $Path)) {
        throw [System.Exception]::new("Assert-PathExists failed: $Message. Path not found: <$Path>")
    }
}
