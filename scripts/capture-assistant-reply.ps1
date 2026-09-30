# Capture the real waiting, typing and completed reply using official hdc/uitest.
# Open Dada first. This script only asks a shortcut; it never adopts or saves a look.
# Times start when the input command returns, not when the app receives its event.
# Keep this file ASCII-only for Windows PowerShell 5.1.
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\dada-chat'),
    [string]$LabelHex = '6B63 5F0F 4E00 70B9'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\device-lib.ps1"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$label = -join ($LabelHex.Split(' ') | ForEach-Object { [char][Convert]::ToInt32($_, 16) })
# A previous user message may repeat the label; use the lowest matching shortcut.
$button = Find-LowestByText -Label $label
if ($null -eq $button) { throw 'Open Dada and make the selected shortcut visible first.' }
$records = New-Object Collections.ArrayList
$inputRequestedAt = Get-Date -Format o
$inputClock = [Diagnostics.Stopwatch]::StartNew()
Invoke-Hdc -HdcArgs @('shell', "uitest uiInput click $($button.X) $($button.Y + $script:WindowOffsetY)") | Out-Null
$inputElapsed = $inputClock.ElapsedMilliseconds
$inputCompletedAt = Get-Date -Format o
$clock = [Diagnostics.Stopwatch]::StartNew()
foreach ($shot in @(
    @{ Name = 'reply-wait'; At = 50 },
    @{ Name = 'reply-typing'; At = 1250 },
    @{ Name = 'reply-done'; At = 4000 }
)) {
    $delay = $shot.At - $clock.ElapsedMilliseconds
    if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }
    $requested = $clock.ElapsedMilliseconds
    $remote = '/data/local/tmp/reply-' + (Get-Date -Format 'HHmmssfff') + '.png'
    Invoke-Hdc -HdcArgs @('shell', ('uitest screenCap -p ' + $remote)) | Out-Null
    $completed = $clock.ElapsedMilliseconds
    Invoke-Hdc -HdcArgs @('file', 'recv', $remote, (Join-Path $OutDir ($shot.Name + '.png'))) | Out-Null
    Invoke-Hdc -HdcArgs @('shell', ('rm -f ' + $remote)) | Out-Null
    [void]$records.Add(@{ file = $shot.Name + '.png'; targetMs = $shot.At;
        requestedMs = $requested; completedMs = $completed })
    Write-Host ($shot.Name + ': capture requested at ' + $requested + ' ms')
}
[IO.File]::WriteAllText((Join-Path $OutDir 'reply-timing.json'),
    (@{ inputRequestedAt = $inputRequestedAt; inputCompletedAt = $inputCompletedAt;
        inputElapsedMs = $inputElapsed; reference = 'input-command-completed'; shots = $records } |
        ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
& "$PSScriptRoot\dump-ui.ps1" -OutFile (Join-Path $OutDir 'reply-done.json') | Out-Null
