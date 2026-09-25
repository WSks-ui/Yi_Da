# Shared helpers for driving the Yi_Da demo on a connected HarmonyOS device.
# Dot-source from another script:  . "$PSScriptRoot\device-lib.ps1"
#
# Keep this file strictly ASCII-only: Windows PowerShell 5.1 reads .ps1 files with the ANSI
# code page, so non-ASCII characters corrupt the parse. Chinese labels are built from code
# points here, and layout dumps are read back with an explicit UTF-8 encoding.

$script:HdcExe = 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$script:BundleName = 'com.chr.Yi_Da'
$script:SnapshotPath = "/data/app/el2/100/base/$($script:BundleName)/haps/entry/files/wardrobe_demo_v1.json"

if (-not (Test-Path $script:HdcExe)) { throw "hdc.exe not found: $($script:HdcExe)" }

function Invoke-Hdc {
    param([string[]]$HdcArgs)
    # hdc prints progress on stderr; only the exit code decides success here.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:HdcExe @HdcArgs 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) { throw "hdc call failed: $($HdcArgs -join ' ')" }
    return $output
}

function Swipe {
    param([int]$X1, [int]$Y1, [int]$X2, [int]$Y2, [int]$WaitMs = 800)
    Invoke-Hdc -HdcArgs @('shell', "uitest uiInput swipe $X1 $Y1 $X2 $Y2 600") | Out-Null
    Start-Sleep -Milliseconds $WaitMs
}

function Press-Back {
    Invoke-Hdc -HdcArgs @('shell', 'uitest uiInput keyEvent Back') | Out-Null
    Start-Sleep -Milliseconds 600
}

function Get-Bounds {
    param([string]$Bounds)
    if ($Bounds -notmatch '^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$') { return $null }
    return @{
        Left = [int]$Matches[1]; Top = [int]$Matches[2]
        Right = [int]$Matches[3]; Bottom = [int]$Matches[4]
        X = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
        Y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
        Text = ''
    }
}

# The layout dump is UTF-8; reading it any other way turns Chinese labels into garbage.
# The transfer is retried with a fresh file name on failure, because a missed receive would
# otherwise leave no file to parse and hide the real error.
function Get-Layout {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $stamp = (Get-Date -Format 'HHmmssfff') + "-$attempt"
        $remote = "/data/local/tmp/yida-$stamp.json"
        $local = Join-Path $env:TEMP "yida-layout-$stamp.json"
        if (Test-Path $local) { Remove-Item $local -Force }
        Invoke-Hdc -HdcArgs @('shell', "uitest dumpLayout -a -p $remote") | Out-Null
        try { Invoke-Hdc -HdcArgs @('file', 'recv', $remote, $local) | Out-Null } catch { continue }
        Invoke-Hdc -HdcArgs @('shell', "rm -f $remote") | Out-Null
        if (-not (Test-Path $local)) { continue }
        $raw = [System.IO.File]::ReadAllText($local, [System.Text.Encoding]::UTF8)
        $end = $raw.LastIndexOf('}')
        if ($end -lt 0) { continue }
        return $raw.Substring(0, $end + 1) | ConvertFrom-Json
    }
    throw 'layout dump could not be read after three attempts'
}

# Find the first visible node whose text contains a fragment, optionally filtered by node type.
# Use -Exact when a substring match could hit a longer label, such as a summary line that
# repeats the same words as the control you actually want.
function Find-Node {
    param($Node, [string]$Match, [string]$Type = '', [switch]$Exact)
    $a = $Node.attributes
    if ($null -ne $a -and $a.visible -eq 'true') {
        $text = [string]$a.originalText
        $hit = if ($Exact) { $text -eq $Match } else { $text -like "*$Match*" }
        if ($hit -and ($Type -eq '' -or $a.type -eq $Type)) {
            $b = Get-Bounds -Bounds $a.bounds
            if ($null -ne $b) { $b.Text = $text; return $b }
        }
    }
    foreach ($child in $Node.children) {
        $found = Find-Node -Node $child -Match $Match -Type $Type -Exact:$Exact
        if ($null -ne $found) { return $found }
    }
    return $null
}

# Find the first visible node of a given type, e.g. Slider.
function Find-ByType {
    param($Node, [string]$Type)
    $a = $Node.attributes
    if ($null -ne $a -and $a.visible -eq 'true' -and $a.type -eq $Type) {
        $b = Get-Bounds -Bounds $a.bounds
        if ($null -ne $b) { $b.Text = $a.originalText; return $b }
    }
    foreach ($child in $Node.children) {
        $found = Find-ByType -Node $child -Type $Type
        if ($null -ne $found) { return $found }
    }
    return $null
}

# Collect every visible node whose text equals the label.
function Find-AllByText {
    param($Node, [string]$Label, [System.Collections.ArrayList]$Into)
    $a = $Node.attributes
    if ($null -ne $a -and $a.visible -eq 'true' -and $a.originalText -eq $Label) {
        $b = Get-Bounds -Bounds $a.bounds
        if ($null -ne $b) { $b.Text = $a.originalText; [void]$Into.Add($b) }
    }
    foreach ($child in $Node.children) { Find-AllByText -Node $child -Label $Label -Into $Into }
}

# Pick the bottom-most node with this label. Question text can repeat a button's wording, and the
# real control always sits below the content it belongs to.
function Find-LowestByText {
    param([string]$Label)
    $nodes = New-Object System.Collections.ArrayList
    Find-AllByText -Node (Get-Layout) -Label $Label -Into $nodes
    if ($nodes.Count -eq 0) { return $null }
    return $nodes | Sort-Object -Property Y -Descending | Select-Object -First 1
}

# Find a checkbox by its label. Tapping the text beside a checkbox does not toggle it, so the
# checkbox itself has to be located and tapped.
function Find-Checkbox {
    param([string]$Label)
    $nodes = New-Object System.Collections.ArrayList
    Find-AllCheckboxes -Node (Get-Layout) -Label $Label -Into $nodes
    if ($nodes.Count -eq 0) { return $null }
    return $nodes[0]
}

function Find-AllCheckboxes {
    param($Node, [string]$Label, [System.Collections.ArrayList]$Into)
    $a = $Node.attributes
    if ($null -ne $a -and $a.visible -eq 'true' -and $a.type -eq 'Checkbox' -and $a.originalText -eq $Label) {
        $b = Get-Bounds -Bounds $a.bounds
        if ($null -ne $b) { [void]$Into.Add($b) }
    }
    foreach ($child in $Node.children) { Find-AllCheckboxes -Node $child -Label $Label -Into $Into }
}

# Collect every visible Text node whose label equals the given string.
function Get-TextNodes {
    param($Node, [string]$Label, [System.Collections.ArrayList]$Into)
    $a = $Node.attributes
    if ($null -ne $a -and $a.visible -eq 'true' -and $a.type -eq 'Text' -and $a.originalText -eq $Label) {
        $b = Get-Bounds -Bounds $a.bounds
        if ($null -ne $b) { [void]$Into.Add($b) }
    }
    foreach ($child in $Node.children) { Get-TextNodes -Node $child -Label $Label -Into $Into }
}

# Coordinates from uitest dumpLayout are in the app-window space, while uiInput taps in screen
# space. On this device the difference measured 68px (the dump's window origin sits above the
# tappable area), so taps add that offset; Tap-Until re-checks and falls back to zero.
$script:WindowOffsetY = 0

function Tap {
    param([int]$X, [int]$Y, [int]$WaitMs = 700)
    Invoke-Hdc -HdcArgs @('shell', "uitest uiInput click $X $($Y + $script:WindowOffsetY)") | Out-Null
    Start-Sleep -Milliseconds $WaitMs
}

# Tap a control until the expected text shows up. Returns $false when neither origin works.
function Tap-Until {
    param([int]$X, [int]$Y, [string]$Expect, [int]$WaitMs = 900, [int]$Attempts = 2)
    foreach ($offset in @($script:WindowOffsetY, 0)) {
        for ($i = 0; $i -lt $Attempts; $i++) {
            Invoke-Hdc -HdcArgs @('shell', "uitest uiInput click $X $($Y + $offset)") | Out-Null
            Start-Sleep -Milliseconds $WaitMs
            if ($null -ne (Find-Node -Node (Get-Layout) -Match $Expect)) {
                $script:WindowOffsetY = $offset
                return $true
            }
        }
    }
    return $false
}

# Set the temperature with a single click on the slider track, then confirm the slider reports
# the requested value. A click lands near the requested spot rather than exactly on it, and the
# extremes of the track are unreliable, so this is best used for mid-range temperatures.
# The 5C "missing top" boundary is covered by the domain checks instead of by a screenshot.
function Set-SliderTemperature {
    param([int]$Celsius, [int]$Tolerance = 1, [int]$Rounds = 4)
    for ($i = 0; $i -lt $Rounds; $i++) {
        $slider = Find-ByType -Node (Get-Layout) -Type 'Slider'
        if ($null -eq $slider) { return $false }
        $current = [int][double]$slider.Text
        if ([Math]::Abs($current - $Celsius) -le $Tolerance) { return $true }
        $x = [int]($slider.Left + ($Celsius - 5) / 30 * ($slider.Right - $slider.Left))
        Invoke-Hdc -HdcArgs @('shell', "uitest uiInput click $x $($slider.Y + $script:WindowOffsetY)") | Out-Null
        Start-Sleep -Milliseconds 700
    }
    return $false
}

# Read the persisted snapshot written by the app. Returns $null when it does not exist yet.
function Get-Snapshot {
    $local = Join-Path $env:TEMP ("yida-snapshot-" + (Get-Date -Format 'HHmmssfff') + ".json")
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $script:HdcExe file recv $script:SnapshotPath $local 2>$null | Out-Null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0 -or -not (Test-Path $local)) { return $null }
    return [System.IO.File]::ReadAllText($local, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

# Replacing the snapshot makes the next launch start from exactly the intended state.
# It also exercises the app's own restore path, which a UI tap would not cover.
function Set-Snapshot {
    param($Snapshot)
    $local = Join-Path $env:TEMP ("yida-set-" + (Get-Date -Format 'HHmmssfff') + ".json")
    $json = $Snapshot | ConvertTo-Json -Depth 12 -Compress
    [System.IO.File]::WriteAllText($local, $json, (New-Object System.Text.UTF8Encoding($false)))
    Invoke-Hdc -HdcArgs @('file', 'send', $local, $script:SnapshotPath) | Out-Null
}

# The temperature slider exposes its numeric value, so no text parsing is needed.
function Get-ShownTemperature {
    $slider = Find-ByType -Node (Get-Layout) -Type 'Slider'
    if ($null -eq $slider) { return $null }
    return [double]$slider.Text
}

# Poll until the Today page reports the expected temperature. The app restores its snapshot
# asynchronously on launch, so a single read can still catch the previous state.
function Wait-Temperature {
    param([int]$Celsius, [int]$Attempts = 10, [int]$IntervalMs = 500)
    for ($i = 0; $i -lt $Attempts; $i++) {
        $shown = Get-ShownTemperature
        if ($null -ne $shown -and [int]$shown -eq $Celsius) { return $true }
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $false
}
