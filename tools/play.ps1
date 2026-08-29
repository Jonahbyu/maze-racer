# Maze Racer -- player launcher.
#
# Started by MazeRacer.vbs from the desktop shortcut. Unlike launch.ps1 (the
# development launcher), this one is built for actually playing:
#
#   - uses the GUI Godot build, so no console window sits behind the game
#   - brings the window to the FOREGROUND and gives it keyboard focus
#
# That last part is the whole reason this file exists. A game started detached
# comes up unfocused and behind other windows, so arrow keys go to whatever had
# focus before and the game looks like it is running but ignoring all input.

$ErrorActionPreference = 'Stop'

$ProjectDir = Split-Path -Parent $PSScriptRoot
$LogDir     = Join-Path $ProjectDir 'logs'
$ErrorsLog  = Join-Path $LogDir 'errors.log'

# Prefer the GUI build for playing; fall back to the console build, and finally
# to a search, so a moved Godot install does not silently break the shortcut.
$GodotOverride = Join-Path $PSScriptRoot 'godot-path.txt'
$Godot = $null

if (Test-Path $GodotOverride) {
    $candidate = (Get-Content $GodotOverride -Raw).Trim()
    if ($candidate -and (Test-Path $candidate -PathType Leaf)) {
        # godot-path.txt points at the console build; the GUI build sits beside
        # it with "_console" removed.
        $gui = $candidate -replace '_console\.exe$', '.exe'
        if (Test-Path $gui -PathType Leaf) { $Godot = $gui } else { $Godot = $candidate }
    }
}

if (-not $Godot) {
    $searchRoots = @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:LOCALAPPDATA 'Programs'),
        'C:\Program Files',
        'C:\Program Files (x86)'
    ) | Where-Object { Test-Path $_ }

    foreach ($root in $searchRoots) {
        $hit = Get-ChildItem -Path $root -Filter 'Godot*.exe' -Recurse -File `
                   -Depth 3 -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '*console*' } |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) { $Godot = $hit.FullName; break }
    }
}

if (-not $Godot) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Could not find Godot.`n`nPut the full path to it in:`n$GodotOverride",
        "Maze Racer", 'OK', 'Error') | Out-Null
    exit 1
}

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# A project that has never been imported has no class_name registry, so every
# typed script fails to parse. Build it once rather than showing the player a
# wall of errors.
if (-not (Test-Path (Join-Path $ProjectDir '.godot\global_script_class_cache.cfg'))) {
    $import = Start-Process -FilePath $Godot `
        -ArgumentList @('--headless', '--path', "`"$ProjectDir`"", '--import') `
        -NoNewWindow -PassThru -Wait
}

$proc = Start-Process -FilePath $Godot `
    -ArgumentList @('--path', "`"$ProjectDir`"") `
    -PassThru

# Bring the game to the front and give it keyboard focus.
#
# Windows will not let an arbitrary background process steal foreground, so
# SetForegroundWindow alone is unreliable here. AttachThreadInput ties this
# script's input queue to the foreground window's thread for the moment of the
# call, which is what makes the focus change actually stick.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Foreground {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint id);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    public static void Focus(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return;
        ShowWindow(hWnd, 9);           // SW_RESTORE
        uint pid;
        uint target  = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        uint current = GetCurrentThreadId();
        AttachThreadInput(current, target, true);
        BringWindowToTop(hWnd);
        SetForegroundWindow(hWnd);
        AttachThreadInput(current, target, false);
    }
}
'@

# The main window does not exist the instant the process starts, so poll for it
# rather than sleeping a fixed guess.
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 250
    $proc.Refresh()
    if ($proc.HasExited) { break }
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
        [Foreground]::Focus($proc.MainWindowHandle)
        break
    }
}

$proc.WaitForExit()
