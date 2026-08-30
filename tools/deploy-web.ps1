# Builds the web export and publishes it to the gh-pages branch.
#
# The normal deploy path is CI: .github/workflows/deploy.yml builds and
# publishes on every push to main. This script is the fallback for when
# Actions is broken or unavailable, and it skips the harnesses that CI runs.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\deploy-web.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$godot = (Get-Content (Join-Path $root 'tools\godot-path.txt')).Trim()

# Build outside the project folder: OneDrive holds locks on synced
# directories, which makes an in-tree rm of build/ fail with "Device or
# resource busy" partway through.
$out = Join-Path $env:TEMP 'mazeweb-deploy'
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== exporting ==' -ForegroundColor Cyan
& $godot --headless --path $root --export-release 'Web' "$out\index.html"
if (-not (Test-Path "$out\index.html")) { throw 'export produced no index.html' }

# A threaded build needs SharedArrayBuffer, which needs COOP/COEP headers,
# which GitHub Pages cannot send. Catch it here, not as a blank canvas.
if (Select-String -Path "$out\index.js" -Pattern 'pthread' -Quiet) {
    throw 'threaded build detected -- set variant/thread_support=false'
}
Write-Host 'nothreads build confirmed' -ForegroundColor Green

New-Item -ItemType File -Path "$out\.nojekyll" -Force | Out-Null

Write-Host '== publishing to gh-pages ==' -ForegroundColor Cyan
$work = Join-Path $env:TEMP 'mazeweb-ghpages'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
git clone --depth 1 https://github.com/Jonahbyu/maze-racer.git $work 2>$null
if (-not (Test-Path $work)) { throw 'clone failed' }
Push-Location $work
git checkout --orphan gh-pages 2>$null
git rm -rqf . 2>$null
Pop-Location

Get-ChildItem -Path $work -Exclude '.git' -Force | Remove-Item -Recurse -Force
Copy-Item -Path "$out\*" -Destination $work -Recurse -Force

Push-Location $work
git add -A
if ((git status --porcelain).Length -eq 0) {
    Write-Host 'no changes to deploy' -ForegroundColor Yellow
} else {
    git commit -q -m "Deploy web build $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    git push -q -f origin gh-pages
    Write-Host 'pushed' -ForegroundColor Green
    # Pages serves whichever source build_type names; a push to gh-pages does
    # nothing while it is still set to 'workflow'.
    gh api -X PUT repos/Jonahbyu/maze-racer/pages -f 'build_type=legacy' -f 'source[branch]=gh-pages' -f 'source[path]=/' | Out-Null
    Write-Host 'Pages pointed at gh-pages (re-run CI to hand it back)' -ForegroundColor Yellow
}
Pop-Location

Write-Host ''
Write-Host 'Live at https://jonahbyu.github.io/maze-racer/' -ForegroundColor Cyan
Write-Host '(Pages takes ~1 min to rebuild.)'
