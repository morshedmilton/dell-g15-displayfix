# tests/e2e/tier1_features/test_nvidia_app_remediation.ps1
# Milestone MR3: NVIDIA App UpdateFramework State & Remediation Verification

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')

Describe "MR3 - NVIDIA App Remediation & UpdateFramework" {

    $basePath = 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework'
    $repoRoot = $global:ProjectRoot

    It "MR3.1: ota-artifacts directory exists" {
        $p = Join-Path $basePath 'ota-artifacts'
        Assert-True (Test-Path $p) "ota-artifacts path must exist"
    }

    It "MR3.2: ota-artifacts is empty (no stuck driver downloads)" {
        $otaPath = Join-Path $basePath 'ota-artifacts'
        $count = (Get-ChildItem $otaPath -Recurse -ErrorAction SilentlyContinue).Count
        Assert-Equal $count 0 "ota-artifacts must be completely empty"
    }

    It "MR3.3: ota-artifacts/grd post-processing directory has no pending tasks" {
        $pp = Join-Path $basePath 'ota-artifacts\grd\post-processing'
        if (Test-Path $pp) {
            $count = (Get-ChildItem $pp -Recurse -ErrorAction SilentlyContinue).Count
            Assert-Equal $count 0 "grd post-processing folder must have 0 items"
        } else {
            Assert-True $true "No pending post-processing directory exists"
        }
    }

    It "MR3.4: grd status directory exists" {
        $grdStatus = Join-Path $basePath 'status\grd'
        Assert-True (Test-Path $grdStatus) "status\grd directory must exist"
    }

    It "MR3.5: grd/download.json is idle (empty array)" {
        $f = Join-Path $basePath 'status\grd\download.json'
        Assert-True (Test-Path $f) "download.json must exist"
        $c = (Get-Content $f -Raw -ErrorAction SilentlyContinue).Trim()
        Assert-Equal $c '[]' "download.json content must be '[]'"
    }

    It "MR3.6: grd/postprocessing.json is idle (empty array)" {
        $f = Join-Path $basePath 'status\grd\postprocessing.json'
        Assert-True (Test-Path $f) "postprocessing.json must exist"
        $c = (Get-Content $f -Raw -ErrorAction SilentlyContinue).Trim()
        Assert-Equal $c '[]' "postprocessing.json content must be '[]'"
    }

    It "MR3.7: grd status files have no stuck taskId 449b11b95561d3a9ac74e4a18a7eb2cb" {
        $dl = Get-Content (Join-Path $basePath 'status\grd\download.json') -Raw -ErrorAction SilentlyContinue
        $pp = Get-Content (Join-Path $basePath 'status\grd\postprocessing.json') -Raw -ErrorAction SilentlyContinue
        Assert-True ($dl -notmatch '449b11b9') "Stuck task id must not be in download.json"
        Assert-True ($pp -notmatch '449b11b9') "Stuck task id must not be in postprocessing.json"
    }

    It "MR3.8: nvapp autoupdate.json exists" {
        $autoUpdateFile = Join-Path $basePath 'status\nvapp\autoupdate.json'
        Assert-True (Test-Path $autoUpdateFile) "nvapp autoupdate.json must exist"
    }

    It "MR3.9: nvapp autoupdate.json updateState is 0 (idle)" {
        $autoUpdateFile = Join-Path $basePath 'status\nvapp\autoupdate.json'
        $raw = Get-Content $autoUpdateFile -Raw -ErrorAction SilentlyContinue
        $obj = $raw | ConvertFrom-Json
        $us  = if ($obj -is [array]) { $obj[0].updateState } else { $obj.updateState }
        Assert-Equal ([int]$us) 0 "updateState must be 0"
    }

    It "MR3.10: nvapp autoupdate.json currentPhase is 0 (idle)" {
        $autoUpdateFile = Join-Path $basePath 'status\nvapp\autoupdate.json'
        $raw = Get-Content $autoUpdateFile -Raw -ErrorAction SilentlyContinue
        $obj = $raw | ConvertFrom-Json
        $cp  = if ($obj -is [array]) { $obj[0].currentPhase } else { $obj.currentPhase }
        Assert-Equal ([int]$cp) 0 "currentPhase must be 0"
    }

    It "MR3.11: nvapp autoupdate.json componentName is 'nvapp'" {
        $autoUpdateFile = Join-Path $basePath 'status\nvapp\autoupdate.json'
        $raw = Get-Content $autoUpdateFile -Raw -ErrorAction SilentlyContinue
        $obj = $raw | ConvertFrom-Json
        $cn  = if ($obj -is [array]) { $obj[0].componentName } else { $obj.componentName }
        Assert-Equal ([string]$cn) 'nvapp' "componentName must be nvapp"
    }

    It "MR3.12: NVDisplay.ContainerLocalSystem service is Running" {
        $s = Get-Service 'NVDisplay.ContainerLocalSystem' -ErrorAction SilentlyContinue
        Assert-NotNull $s "NVDisplay.ContainerLocalSystem service must exist"
        Assert-Equal $s.Status.ToString() 'Running' "Service must be running"
    }

    It "MR3.13: NvContainerLocalSystem service is Running" {
        $s = Get-Service 'NvContainerLocalSystem' -ErrorAction SilentlyContinue
        Assert-NotNull $s "NvContainerLocalSystem service must exist"
        Assert-Equal $s.Status.ToString() 'Running' "Service must be running"
    }

    It "MR3.14: No crashed NVIDIA Display Container events in last 5 minutes" {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            Level     = 2
            StartTime = (Get-Date).AddMinutes(-5)
        } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'NVIDIA' -and $_.Message -match 'crash|fatal|container' }
        Assert-Equal (@($events).Count) 0 "Must have 0 container crash events"
    }

    It "MR3.15: remedy_nvidia_app.ps1 exists in scripts directory" {
        $remedyScript = Join-Path $repoRoot 'scripts\remedy_nvidia_app.ps1'
        Assert-True (Test-Path $remedyScript) "scripts\remedy_nvidia_app.ps1 must exist"
    }

    It "MR3.16: remedy_nvidia_app.ps1 -Verify exits with 0 (clean state confirmed)" {
        $remedyScript = Join-Path $repoRoot 'scripts\remedy_nvidia_app.ps1'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $remedyScript -Verify 2>&1 | Out-Null
        Assert-Equal $LASTEXITCODE 0 "remedy_nvidia_app.ps1 -Verify must exit 0"
    }

    It "MR3.17: fix_nvidia_app.ps1 exists in scripts\diagnostics directory" {
        $fixScript = Join-Path $repoRoot 'scripts\diagnostics\fix_nvidia_app.ps1'
        Assert-True (Test-Path $fixScript) "scripts\diagnostics\fix_nvidia_app.ps1 must exist"
    }

    It "MR3.18: fix_nvidia_app.ps1 -VerifyOnly exits with 0 (clean state confirmed)" {
        $fixScript = Join-Path $repoRoot 'scripts\diagnostics\fix_nvidia_app.ps1'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $fixScript -VerifyOnly 2>&1 | Out-Null
        Assert-Equal $LASTEXITCODE 0 "fix_nvidia_app.ps1 -VerifyOnly must exit 0"
    }

    It "MR3.19: FvSvc (FrameView SDK Service) is Running and StartupType is Automatic" {
        $fv = Get-Service -Name 'FvSvc' -ErrorAction SilentlyContinue
        Assert-NotNull $fv "FvSvc service must exist"
        Assert-Equal $fv.Status.ToString() 'Running' "FvSvc service must be Running"
        Assert-Equal $fv.StartType.ToString() 'Automatic' "FvSvc StartupType must be Automatic"
    }

    It "MR3.20: Downloader folder contains no orphaned lock or temporary files" {
        $dlDir = 'C:\ProgramData\NVIDIA Corporation\Downloader'
        if (Test-Path $dlDir) {
            $locks = Get-ChildItem -Path $dlDir -Include *.lock,*.tmp,*.part,*.aria2 -Recurse -File -ErrorAction SilentlyContinue
            Assert-Equal (@($locks).Count) 0 "Downloader must have 0 lock/temporary files"
        } else {
            Assert-True $true "Downloader directory is clean / not created"
        }
    }
}

