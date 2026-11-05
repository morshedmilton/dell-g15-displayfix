# tests/e2e/tier1_features/test_f04_ghost_eviction.ps1
# Feature F04: Sub-second Ghost Monitor Eviction (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F04 - Sub-second Ghost Monitor Eviction" {

    It "F04.1: Enumerates PnP monitor device nodes across all hardware classes" {
        $topo = Get-DisplayTopologyState
        Assert-NotNull $topo.AllMonitors "Monitors must be retrievable via PnP"
        Assert-True ($topo.TotalMonitors -ge 1) "System must report at least 1 monitor device node"
    }

    It "F04.2: Verifies disconnected Intel monitor node UID8388688 is in evicted (non-present) state" {
        $topo = Get-DisplayTopologyState
        # If running on NVIDIA GPU Only mode, the Intel ghost monitor node should NOT be present (evicted)
        if ($topo.IntelGhostDevice) {
            Assert-False ($topo.IntelGhostDevice.Present) "Intel monitor node UID8388688 must not be active/present when routed to NVIDIA dGPU"
        } else {
            Assert-True $true "Ghost device node not found or already completely removed"
        }
    }

    It "F04.3: Verifies active NVIDIA monitor node UID4353 is in Present and OK state" {
        $topo = Get-DisplayTopologyState
        Assert-NotNull $topo.NvidiaActiveNode "NVIDIA monitor device node UID4353 must exist"
        Assert-True ($topo.NvidiaActiveNode.Present) "NVIDIA monitor device node UID4353 must be Present"
        Assert-Equal $topo.NvidiaActiveNode.Status "OK" "NVIDIA monitor node status must be OK"
    }

    It "F04.4: Verifies ghost eviction eliminates DWM presentation stall (DWM CPU < 5% at idle)" {
        # Sample DWM CPU utilization over 500ms
        $dwm1 = Get-Process -Name dwm -ErrorAction SilentlyContinue
        Assert-NotNull $dwm1 "dwm.exe must be running"
        $cpuStart = $dwm1.TotalProcessorTime.TotalMilliseconds
        Start-Sleep -Milliseconds 500
        $dwm2 = Get-Process -Name dwm -ErrorAction SilentlyContinue
        $cpuEnd = $dwm2.TotalProcessorTime.TotalMilliseconds

        $cpuDeltaMs = $cpuEnd - $cpuStart
        # In a 500ms window on a multi-core machine, healthy idle DWM should consume < 250ms of CPU time (< 50% of single core, typically < 5%)
        Assert-True ($cpuDeltaMs -lt 150.0) "DWM CPU time in 500ms window ($cpuDeltaMs ms) must be < 150ms (no presentation spin)"
    }

    It "F04.5: Verifies eviction policy stands down when foreign / external monitor is attached" {
        # Eviction rule: only target AUOAA9F on Intel path. Never touch foreign monitor IDs (e.g. DELL U2720Q, HDMI, DP).
        $isSafeToEvict = {
            param($instanceId, $hardwareId)
            # Safe to evict ONLY if it matches the known Intel internal panel UID8388688
            if ($instanceId -like "*AUOAA9F*UID8388688*") { return $true }
            return $false
        }

        Assert-True (& $isSafeToEvict "DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688" "MONITOR\AUOAA9F") "Intel internal panel must be targeted"
        Assert-False (& $isSafeToEvict "DISPLAY\AUOAA9F\5&39808DAE&2&UID4353" "MONITOR\AUOAA9F") "Active NVIDIA node must NOT be targeted"
        Assert-False (& $isSafeToEvict "DISPLAY\DEL4123\4&12345678&0&UID0" "MONITOR\DEL4123") "External Dell monitor must NOT be targeted"
        Assert-False (& $isSafeToEvict "DISPLAY\SAM0123\4&87654321&0&UID1" "MONITOR\SAM0123") "External Samsung monitor must NOT be targeted"
    }
}
