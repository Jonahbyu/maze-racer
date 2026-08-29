# Maze Racer launcher
# Runs the game via the Godot console build so stdout/stderr can be captured,
# writes a full session log, and extracts errors/warnings into errors.log.
#
# This is the primary feedback channel: Jonah does not open the editor, so
# anything Godot reports has to reach logs/errors.log to be seen at all.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\launch.ps1
#   powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/MazeGenTest.gd
#   powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Quit 10

param(
    # Run with no window -- used for the test harnesses.
    [switch]$Headless,
    # Run a single script instead of the main scene.
    [string]$Script,
    # Auto-quit after N seconds. Lets Claude run the real game unattended and
    # still get a log back, instead of hanging until something kills it.
    [int]$Quit = 0
)

$ErrorActionPreference = 'Stop'

$ProjectDir = Split-Path -Parent $PSScriptRoot
$LogDir     = Join-Path $ProjectDir 'logs'
$HistoryDir = Join-Path $LogDir 'history'
$ErrorsLog  = Join-Path $LogDir 'errors.log'

# Locate the Godot *console* build -- the GUI build detaches from the console and
# produces no capturable stdout/stderr, so error logging depends on this one.
$GodotOverride = Join-Path $PSScriptRoot 'godot-path.txt'
$Godot = $null

if (Test-Path $GodotOverride) {
    $candidate = (Get-Content $GodotOverride -Raw).Trim()
    if ($candidate -and (Test-Path $candidate -PathType Leaf)) { $Godot = $candidate }
}

if (-not $Godot) {
    $searchRoots = @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:LOCALAPPDATA 'Programs'),
        'C:\Program Files',
        'C:\Program Files (x86)'
    ) | Where-Object { Test-Path $_ }

    foreach ($root in $searchRoots) {
        $hit = Get-ChildItem -Path $root -Filter 'Godot*console.exe' -Recurse -File `
                   -Depth 3 -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) { $Godot = $hit.FullName; break }
    }
}

if (-not $Godot) {
    Write-Output "ERROR: Could not find a Godot console build (Godot*console.exe)."
    Write-Output "Put the full path to it in: $GodotOverride"
    exit 1
}

foreach ($d in @($LogDir, $HistoryDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# A project that has never been imported has no global class_name registry, so
# every `class_name` type fails to resolve with "Identifier not declared" -- a
# parse error that looks like a code bug but is really a missing cache. Build it
# once up front rather than leaving that trap for the next fresh clone.
if (-not (Test-Path (Join-Path $ProjectDir '.godot\global_script_class_cache.cfg'))) {
    Write-Output "No class cache -- importing project first..."
    $import = Start-Process -FilePath $Godot `
        -ArgumentList @('--headless', '--path', "`"$ProjectDir`"", '--import') `
        -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $env:TEMP 'mr_import_out.txt') `
        -RedirectStandardError (Join-Path $env:TEMP 'mr_import_err.txt')
    $import.WaitForExit()
}

$Stamp      = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$SessionLog = Join-Path $HistoryDir "session_$Stamp.log"

# The project path is quoted explicitly: Start-Process -ArgumentList joins array
# elements with spaces WITHOUT quoting them, so a project directory containing a
# space ("Maze Racer") would otherwise reach Godot truncated at the space.
$godotArgs = @('--path', "`"$ProjectDir`"")
if ($Headless) { $godotArgs += '--headless' }
if ($Script)   { $godotArgs += @('--script', $Script) }

# Run Godot, capturing both streams to temp files. Native stderr is redirected at
# the process level rather than via PowerShell 2>&1, which in PS 5.1 wraps each
# line in a NativeCommandError and falsifies $?.
$OutFile = Join-Path $env:TEMP "mazeracer_out_$Stamp.txt"
$ErrFile = Join-Path $env:TEMP "mazeracer_err_$Stamp.txt"

$proc = Start-Process -FilePath $Godot `
    -ArgumentList $godotArgs `
    -RedirectStandardOutput $OutFile `
    -RedirectStandardError  $ErrFile `
    -NoNewWindow -PassThru

$timedOut = $false
if ($Quit -gt 0) {
    if (-not $proc.WaitForExit($Quit * 1000)) {
        $timedOut = $true
        try { $proc.Kill() } catch {}
        $proc.WaitForExit()
    }
} else {
    $proc.WaitForExit()
}

# Re-read the handle: .ExitCode can come back empty on a killed process unless
# the object is refreshed. Even refreshed it can be null for a process that
# exited very fast, which is the normal case for a passing headless harness --
# so fall back to Get-Process/WaitForExit having completed, and only report -1
# when the code is genuinely unavailable.
$proc.Refresh()
$ExitCode = $proc.ExitCode
if ($null -eq $ExitCode) {
    try { $ExitCode = [int]$proc.GetType().GetProperty('ExitCode').GetValue($proc) } catch {}
}
if ($null -eq $ExitCode) { $ExitCode = if ($timedOut) { -1 } else { 0 } }

$header = @(
    "=== Maze Racer session $Stamp ===",
    "exit code : $ExitCode",
    "godot     : $Godot",
    "project   : $ProjectDir",
    "args      : $($godotArgs -join ' ')",
    "timed out : $timedOut",
    ""
)
$stdout = if (Test-Path $OutFile) { @(Get-Content $OutFile -ErrorAction SilentlyContinue) } else { @() }
$stderr = if (Test-Path $ErrFile) { @(Get-Content $ErrFile -ErrorAction SilentlyContinue) } else { @() }

$body = @()
if ($stdout.Count) { $body += '--- stdout ---'; $body += $stdout; $body += '' }
if ($stderr.Count) { $body += '--- stderr ---'; $body += $stderr; $body += '' }

($header + $body) | Out-File -FilePath $SessionLog -Encoding utf8

Remove-Item $OutFile, $ErrFile -Force -ErrorAction SilentlyContinue

# Extract problems. Godot reports script errors on stderr and via
# "SCRIPT ERROR" / "ERROR:" / "WARNING:" prefixes on stdout.
$all = $stdout + $stderr
$problemPattern = 'SCRIPT ERROR|^ERROR:|^WARNING:|^USER ERROR|^USER WARNING|Parse Error|Invalid call|Cannot call method|Nonexistent function|Attempt to call|null instance|Condition ".*" is (true|false)|Failed to load|res:\/\/.*\.gd:\d+'

$problems = @()
for ($i = 0; $i -lt $all.Count; $i++) {
    if ($all[$i] -match $problemPattern) {
        $problems += $all[$i]
        # Godot puts the "at: ..." source location on the following line.
        if ($i + 1 -lt $all.Count -and $all[$i + 1] -match '^\s+at:') {
            $problems += $all[$i + 1]
            $i++
        }
    }
}

# A nonzero exit with no error output just means the window was closed or the
# -Quit timer fired -- not a bug worth recording.
$crashed = ($ExitCode -gt 0 -and $ExitCode -ne 255 -and -not $timedOut)

if ($problems.Count -gt 0 -or ($crashed -and $stderr.Count -gt 0)) {
    $entry = @(
        "=== $Stamp (exit $ExitCode) ===",
        "session log: logs/history/session_$Stamp.log",
        ""
    ) + $problems + @('')
    Add-Content -Path $ErrorsLog -Value $entry -Encoding utf8
}

# Echo to the caller. Unlike Godsfall's silent-shim version, this script is
# invoked by Claude from a shell, so the result needs to come back on stdout.
Write-Output "exit $ExitCode | log: logs/history/session_$Stamp.log | problems: $($problems.Count)"
if ($problems.Count -gt 0) { $problems | ForEach-Object { Write-Output $_ } }
