param(
    [string]$DevEcoHome = $env:YIDA_DEVECO_HOME,
    [ValidateSet('sync', 'app', 'test')]
    [string]$Task = 'app'
)
$ErrorActionPreference = 'Stop'
if (-not $DevEcoHome) { $DevEcoHome = 'D:\DevEco Studio 2\DevEco Studio' }
$root = Split-Path -Parent $PSScriptRoot
$sdk = Get-Content -LiteralPath (Join-Path $DevEcoHome 'sdk\default\sdk-pkg.json') -Raw | ConvertFrom-Json
if ($sdk.data.platformVersion -ne '26.0.0') {
    throw '需要配套 API 26.0.0 SDK；本脚本不会降级工程。'
}
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
# Codex 进程的 PATH 可能缺少 System32，es2abc 仍需要 cmd.exe。
$env:ComSpec = Join-Path $env:SystemRoot 'System32\cmd.exe'
$env:PATH = "$(Join-Path $env:SystemRoot 'System32');$(Join-Path $DevEcoHome 'tools\node');$(Join-Path $DevEcoHome 'tools\ohpm\bin');$env:PATH"
$node = Join-Path $DevEcoHome 'tools\node\node.exe'
$hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
Push-Location $root
try {
    New-Item -ItemType Directory -Force -Path '.hvigor' | Out-Null
    if ($Task -eq 'sync') {
        & $node (Join-Path $DevEcoHome 'tools\ohpm\bin\pm-cli.js') install
        if ($LASTEXITCODE -ne 0) { throw 'ohpm install 失败' }
        & $node $hvigor --sync -p product=default --no-daemon 2>&1 | Tee-Object -FilePath '.hvigor\sync.log'
    } else {
        $target = if ($Task -eq 'test') { 'entry@ohosTest' } else { 'entry@default' }
        & $node $hvigor --mode module -p product=default -p "module=$target" -p buildMode=debug assembleHap --no-daemon 2>&1 |
            Tee-Object -FilePath ".hvigor\$Task-build.log"
    }
    if ($LASTEXITCODE -ne 0) { throw "Hvigor 失败：$LASTEXITCODE" }
} finally {
    Pop-Location
}
