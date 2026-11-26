<#
.SYNOPSIS
Checks that a zip from `swift package bundle --zip` runs on a machine without Swift.

.DESCRIPTION
What the tester will do, done here first (ADR-0046/ADR-0055): verify the .sha256 sidecar,
unzip into a fresh folder under %TEMP% (outside any build tree), launch the executable
with PATH cut to the Windows directories and LOCALAPPDATA pointed at a scratch folder,
and require it to be alive after -Seconds. Exit 1 with the reason otherwise: an exit code
of 0xC0000135 (-1073741515) is a DLL the folder lacks; a Crashes folder under the scratch
LOCALAPPDATA, or a new crash report under the real one, means the crash reporter fired.
The port's crash reporter reads the LOCALAPPDATA variable, so its reports land in the
scratch folder; an app that resolves Application Support through the known-folder API
(corelibs FileManager does) writes to the real profile regardless, so pass the app's own
override in -Env to keep a verify run out of it (Sibyl: SIBYL_APP_SUPPORT).

.PARAMETER Env
Extra environment variables for the run, e.g. @{ SIBYL_APP_SUPPORT = "C:\scratch" }.

.EXAMPLE
pwsh tools\windows\verify-bundle.ps1 -Zip .build\bundle\MyApp-1.0-windows-x86_64.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Zip,
    [string]$Exe,
    [int]$Seconds = 10,
    [hashtable]$Env = @{},
    [switch]$KeepExtracted
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$zipPath = (Resolve-Path $Zip).Path
$zipName = Split-Path $zipPath -Leaf
$hash = (Get-FileHash -Algorithm SHA256 $zipPath).Hash.ToLowerInvariant()
Write-Host "SHA-256: $hash  $zipName"
if (Test-Path "$zipPath.sha256") {
    $expected = ((Get-Content "$zipPath.sha256" -Raw) -split '\s+')[0].ToLowerInvariant()
    if ($expected -ne $hash) { Write-Error "the .sha256 sidecar says $expected"; exit 1 }
    Write-Host "the .sha256 sidecar matches"
}

$work = Join-Path $env:TEMP ("appkitcross-verify-" + [IO.Path]::GetFileNameWithoutExtension($zipName) + "-" + (Get-Random))
New-Item -ItemType Directory -Force $work | Out-Null
$extracted = Join-Path $work "unzipped"
New-Item -ItemType Directory -Force $extracted | Out-Null
# Windows' own bsdtar: a tar found on PATH may be Git's GNU tar, which reads D:\ as a host.
& (Join-Path $env:SystemRoot "System32\tar.exe") -xf $zipPath -C $extracted
if ($LASTEXITCODE -ne 0) { Write-Error "tar failed to extract $zipName ($LASTEXITCODE)"; exit 1 }

$folders = @(Get-ChildItem $extracted -Directory)
if ($folders.Count -ne 1) { Write-Error "expected one top-level folder in the zip, found $($folders.Count)"; exit 1 }
$folder = $folders[0].FullName
if (-not $Exe) {
    $exes = @(Get-ChildItem $folder -Filter *.exe)
    if ($exes.Count -ne 1) { Write-Error "expected one .exe in $folder, found $($exes.Count); pass -Exe"; exit 1 }
    $Exe = $exes[0].Name
}
$exePath = Join-Path $folder $Exe
if (-not (Test-Path $exePath)) { Write-Error "no $Exe in $folder"; exit 1 }
foreach ($required in @("swiftCore.dll", "Foundation.dll")) {
    if (-not (Test-Path (Join-Path $folder $required))) { Write-Error "$required is not in the folder; it will not start without the Swift runtime"; exit 1 }
}
$links = @(Get-ChildItem $folder -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
if ($links.Count) { Write-Error "the zip holds links, which do not survive a tester's unzip: $($links.Name -join ', ')"; exit 1 }
Write-Host "Unzipped to $folder ($(@(Get-ChildItem $folder -File).Count) files at the top level)"

# The tester's machine: no toolchain on PATH, a LOCALAPPDATA of its own so app support
# and crash reports are visible and leave the real profile alone.
$scratchLocal = Join-Path $work "localappdata"
New-Item -ItemType Directory -Force $scratchLocal | Out-Null
$savedPath = $env:PATH; $savedLocal = $env:LOCALAPPDATA
$realLocal = $env:LOCALAPPDATA
$started = Get-Date
$saved = @{}
foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$Env[$k]) }
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
$env:LOCALAPPDATA = $scratchLocal
try {
    $stderr = Join-Path $work "stderr.txt"
    $stdout = Join-Path $work "stdout.txt"
    $p = Start-Process -FilePath $exePath -WorkingDirectory $folder -PassThru -RedirectStandardError $stderr -RedirectStandardOutput $stdout
    Start-Sleep -Seconds $Seconds
    $alive = -not $p.HasExited
    if (-not $alive) {
        $code = $p.ExitCode
        Write-Host "--- stderr ---"; if (Test-Path $stderr) { Get-Content $stderr -TotalCount 60 }
        Write-Error ("{0} exited after less than {1} s with 0x{2:X8} ({2}){3}" -f $Exe, $Seconds, $code, $(if ($code -eq -1073741515) { ": a DLL is missing from the folder" } else { "" }))
        exit 1
    }
    Stop-Process -Id $p.Id -Force
    Write-Host "$Exe ran for $Seconds s without the toolchain on PATH (stderr redirected)"
    # Then as Explorer starts it: no redirects, so a GUI-subsystem process has no stdio
    # handles at all. The first Sibyl tester build ran with stderr redirected and trapped
    # on its first log line when double-clicked (ADR-0055).
    $plain = Start-Process -FilePath $exePath -WorkingDirectory $folder -PassThru
    Start-Sleep -Seconds $Seconds
    if ($plain.HasExited) {
        $code = $plain.ExitCode
        Write-Error ("{0} started without redirected stdio (a double-click) exited within {1} s with 0x{2:X8} ({2}){3}" -f $Exe, $Seconds, $code, $(if ($code -eq -1073741795) { ": a Swift trap, often a write to a stdio handle the process does not have" } else { "" }))
        exit 1
    }
    Stop-Process -Id $plain.Id -Force
    Write-Host "$Exe ran for $Seconds s started the way a double-click starts it (no stdio)"
} finally {
    $env:PATH = $savedPath; $env:LOCALAPPDATA = $savedLocal
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
}
Write-Host "--- first stderr lines ---"
if (Test-Path $stderr) { Get-Content $stderr -TotalCount 25 }
Write-Host "--- written under the scratch LOCALAPPDATA (crash reports land here; app support only if the app reads the variable) ---"
$written = @(Get-ChildItem -Recurse $scratchLocal -ErrorAction SilentlyContinue | Where-Object { $_.FullName.Substring($scratchLocal.Length + 1) -notmatch '^Microsoft(\\|$)' })
if ($written.Count) { $written | ForEach-Object { Write-Host ("  " + $_.FullName.Substring($scratchLocal.Length + 1)) } } else { Write-Host "  (nothing)" }
$crashes = @(Get-ChildItem -Recurse -Directory -Filter Crashes $scratchLocal -ErrorAction SilentlyContinue)
# An app that puts the reports elsewhere (APPKITWIN_CRASH_DIR, or a reporter of its own under
# the real profile): any crash report newer than the launch counts too.
if ($realLocal -and (Test-Path $realLocal)) {
    $crashes += @(Get-ChildItem -Directory $realLocal -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem -Directory -Filter Crashes $_.FullName -ErrorAction SilentlyContinue } |
        Where-Object { @(Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $started }).Count -gt 0 })
}
if ($crashes.Count) {
    foreach ($c in $crashes) { Get-ChildItem $c.FullName -Filter *.txt | Where-Object { $_.LastWriteTime -ge $started } | ForEach-Object { Write-Host "--- $($_.FullName) ---"; Get-Content $_.FullName -TotalCount 40 } }
    Write-Error "the crash reporter wrote a report during the run"; exit 1
}
if (-not $KeepExtracted) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue } else { Write-Host "Kept $work" }
Write-Host "OK: $zipName runs on its own"
exit 0
