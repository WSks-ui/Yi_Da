[CmdletBinding()]
param([string]$DevEcoHome = 'D:\Software\DevEco Studio')

$ErrorActionPreference = 'Stop'
$previousJava = $env:JAVA_HOME
$previousSdk = $env:DEVECO_SDK_HOME
$projectPath = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectPath
try {
    $env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
    $nodePath = Join-Path $DevEcoHome 'tools\node\node.exe'
    $hvigorPath = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
    # hvigor prints its warnings on stderr; with ErrorActionPreference Stop, PowerShell would
    # turn those native-command warnings into a terminating error and abort a passing build.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $nodePath $hvigorPath --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
        $buildExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($buildExit -ne 0) { throw "Hvigor build failed with exit code $buildExit." }
} finally {
    $env:JAVA_HOME = $previousJava
    $env:DEVECO_SDK_HOME = $previousSdk
    Pop-Location
}
