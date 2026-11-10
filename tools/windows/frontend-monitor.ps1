# Watches swift-frontend processes during a CI build on Windows (docs/ci-windows-runner.md).
#
#   Start-Process pwsh -ArgumentList '-NoProfile','-File','tools\windows\frontend-monitor.ps1','-Out',"$env:RUNNER_TEMP\frontends" -WindowStyle Hidden
#
# Every -IntervalMs it records the system commit charge and limit; for every swift-frontend
# it keeps a handle (so the exit code survives the process) and its peak private bytes
# (commit) and working set. When a frontend exits it appends one line to frontends.csv:
# kind (emit-module or compile), module, exit code (hex), peaks, duration. samples.csv has
# the system commit over time. The monitor runs until the job ends (the runner kills it).
param(
    [string]$Out = "$env:RUNNER_TEMP\frontends",
    [int]$IntervalMs = 250
)
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$exits = Join-Path $Out 'frontends.csv'
$samples = Join-Path $Out 'samples.csv'
'pid,kind,module,exit,peakPrivateMB,peakWorkingSetMB,seconds,systemCommitAtPeakMB' | Set-Content $exits
'time,commitMB,commitLimitMB,availableMB,frontends,frontendPrivateMB' | Set-Content $samples
$committed = [System.Diagnostics.PerformanceCounter]::new('Memory', 'Committed Bytes')
$limit = [System.Diagnostics.PerformanceCounter]::new('Memory', 'Commit Limit')
$avail = [System.Diagnostics.PerformanceCounter]::new('Memory', 'Available MBytes')
$tracked = @{}
$lastSample = [DateTime]::MinValue
while ($true) {
    $commitMB = [math]::Round($committed.NextValue() / 1MB)
    foreach ($p in [System.Diagnostics.Process]::GetProcessesByName('swift-frontend')) {
        $t = $tracked[$p.Id]
        if (-not $t) {
            try { $null = $p.Handle } catch { continue }   # the handle keeps ExitCode readable
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).CommandLine
            $kind = if ($cmd -match ' -c ' -or $cmd -match ' -c$') { 'compile' } elseif ($cmd -match '-emit-module') { 'emit-module' } else { 'other' }
            $module = if ($cmd -match '-module-name\s+"?([^\s"]+)') { $Matches[1] } else { '?' }
            $t = @{ P = $p; Kind = $kind; Module = $module; Start = Get-Date; Priv = 0; WS = 0; CommitAtPeak = 0 }
            $tracked[$p.Id] = $t
        }
        try {
            $p.Refresh()
            if ($p.PrivateMemorySize64 -gt $t.Priv) { $t.Priv = $p.PrivateMemorySize64; $t.CommitAtPeak = $commitMB }
            if ($p.PeakWorkingSet64 -gt $t.WS) { $t.WS = $p.PeakWorkingSet64 }
        } catch {}
    }
    foreach ($id in @($tracked.Keys)) {
        $t = $tracked[$id]
        if ($t.P.HasExited) {
            $code = '0x{0:X8}' -f $t.P.ExitCode
            $secs = [math]::Round(((Get-Date) - $t.Start).TotalSeconds, 1)
            "$id,$($t.Kind),$($t.Module),$code,$([math]::Round($t.Priv / 1MB)),$([math]::Round($t.WS / 1MB)),$secs,$($t.CommitAtPeak)" | Add-Content $exits
            $tracked.Remove($id)
        }
    }
    if (((Get-Date) - $lastSample).TotalSeconds -ge 1) {
        $lastSample = Get-Date
        $live = @($tracked.Values)
        $priv = ($live | ForEach-Object { $_.P.PrivateMemorySize64 } | Measure-Object -Sum).Sum
        "$($lastSample.ToString('HH:mm:ss')),$commitMB,$([math]::Round($limit.NextValue() / 1MB)),$($avail.NextValue()),$($live.Count),$([math]::Round($priv / 1MB))" | Add-Content $samples
    }
    Start-Sleep -Milliseconds $IntervalMs
}
