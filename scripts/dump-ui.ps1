# Dump the current on-device layout and print visible text plus clickable elements.
# Usage: .\scripts\dump-ui.ps1
#        .\scripts\dump-ui.ps1 -ClickableOnly
#
# Note: every capture uses a fresh remote file name, because overwriting a longer
# layout file with a shorter one on the device can leave a stale tail behind.
#
# Keep this file ASCII-only: Windows PowerShell 5.1 reads .ps1 files with the ANSI
# code page, so non-ASCII comments can be mis-decoded and break parsing.
[CmdletBinding()]
param(
    [string]$OutFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'yida-layout.json'),
    [switch]$ClickableOnly
)

$ErrorActionPreference = 'Stop'
$hdcExe = 'D:\DevEco Studio 2\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
if (-not (Test-Path $hdcExe)) { throw "hdc.exe not found: $hdcExe" }

$stamp = Get-Date -Format 'HHmmssfff'
$remote = "/data/local/tmp/yida-$stamp.json"
& $hdcExe shell "uitest dumpLayout -a -p $remote" 2>$null | Out-Null
& $hdcExe file recv $remote $OutFile 2>$null | Out-Null
& $hdcExe shell "rm -f $remote" 2>$null | Out-Null

$raw = Get-Content -LiteralPath $OutFile -Raw -Encoding UTF8
$start = $raw.IndexOf('{')
if ($start -lt 0) { throw "Layout file has no JSON: $OutFile" }
$depth = 0
$end = -1
for ($i = $start; $i -lt $raw.Length; $i++) {
    $c = $raw[$i]
    if ($c -eq '{') { $depth++ }
    elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
}
if ($end -lt 0) { throw "Layout JSON is incomplete: $OutFile" }
$tree = $raw.Substring($start, $end - $start + 1) | ConvertFrom-Json

function Show-Node($node) {
    $a = $node.attributes
    if ($null -eq $a) { return }
    $hasText = -not [string]::IsNullOrWhiteSpace($a.text)
    $isClickable = $a.clickable -eq 'true'
    if ($a.visible -eq 'true' -and (($hasText -and -not $ClickableOnly) -or $isClickable)) {
        $tag = if ($isClickable) { 'CLICK' } else { '     ' }
        '{0} | {1,-9} | {2} | {3}' -f $tag, $a.type, $a.bounds, $a.text
    }
    foreach ($child in $node.children) { Show-Node $child }
}

Show-Node $tree
