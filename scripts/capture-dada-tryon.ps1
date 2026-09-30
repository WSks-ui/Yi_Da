# Capture the real six-second try-on presentation using official hdc/uitest.
# Open the try-on page first. This script never saves a record or sends a share.
# All capture timestamps are measured relative to completion of the input command.
# The app's exact input-dispatch time is not inferred from host command latency.
# Keep this file ASCII-only for Windows PowerShell 5.1.
[CmdletBinding()]
param([string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\dada-demo'))

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\device-lib.ps1"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

function From-HexLabel([string]$Hex) {
    return -join ($Hex.Split(' ') | ForEach-Object { [char][Convert]::ToInt32($_, 16) })
}
$startLabel = From-HexLabel '8BA9 642D 642D 6F14 793A 8BD5 7A7F'
$replayLabel = From-HexLabel '91CD 64AD 6F14 793A'
$tree = Get-Layout
$button = Find-Node -Node $tree -Match $startLabel -Exact
if ($null -eq $button) { $button = Find-Node -Node $tree -Match $replayLabel -Exact }
if ($null -eq $button) { throw 'Open try-on and scroll until its start/replay button is visible.' }

$shots = @(
    @{ Name = 'tryon-prepare'; At = 500 },
    @{ Name = 'tryon-interact'; At = 2300 },
    @{ Name = 'tryon-present'; At = 4100 },
    @{ Name = 'tryon-reveal'; At = 5500 },
    @{ Name = 'tryon-result'; At = 6800 }
)
$records = New-Object System.Collections.ArrayList
$inputRequestedAt = Get-Date -Format o
$inputClock = [Diagnostics.Stopwatch]::StartNew()
Invoke-Hdc -HdcArgs @('shell', "uitest uiInput click $($button.X) $($button.Y + $script:WindowOffsetY)") | Out-Null
$inputElapsedMs = $inputClock.ElapsedMilliseconds
$inputCompletedAt = Get-Date -Format o
$clock = [Diagnostics.Stopwatch]::StartNew()
foreach ($shot in $shots) {
    $remaining = $shot.At - $clock.ElapsedMilliseconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
    $requestedAt = $clock.ElapsedMilliseconds
    $stamp = Get-Date -Format 'HHmmssfff'
    $remote = "/data/local/tmp/dada-$stamp.png"
    Invoke-Hdc -HdcArgs @('shell', "uitest screenCap -p $remote") | Out-Null
    $capturedAt = $clock.ElapsedMilliseconds
    $local = Join-Path $OutDir ($shot.Name + '.png')
    Invoke-Hdc -HdcArgs @('file', 'recv', $remote, $local) | Out-Null
    Invoke-Hdc -HdcArgs @('shell', "rm -f $remote") | Out-Null
    [void]$records.Add(@{ file = $shot.Name + '.png'; targetMs = $shot.At;
        requestedMs = $requestedAt; completedMs = $capturedAt })
    Write-Host ($shot.Name + ': capture requested at ' + $requestedAt + ' ms')
}
$metadata = @{ inputRequestedAt = $inputRequestedAt; inputCompletedAt = $inputCompletedAt;
    inputElapsedMs = $inputElapsedMs; reference = 'input-command-completed';
    device = 'hdc/uitest'; plannedDurationMs = 6000; shots = $records }
[IO.File]::WriteAllText((Join-Path $OutDir 'tryon-capture-timing.json'),
    ($metadata | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
& "$PSScriptRoot\dump-ui.ps1" -OutFile (Join-Path $OutDir 'tryon-result.json') | Out-Null
