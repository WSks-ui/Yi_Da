param(
    [string]$DevEcoHome = $env:YIDA_DEVECO_HOME,
    [string]$Target = '127.0.0.1:5555'
)
$ErrorActionPreference = 'Stop'
if (-not $DevEcoHome) { $DevEcoHome = 'D:\DevEco Studio 2\DevEco Studio' }
$root = Split-Path -Parent $PSScriptRoot
$hdc = Join-Path $DevEcoHome 'sdk\default\openharmony\toolchains\hdc.exe'
Push-Location $root
try {
    & "$PSScriptRoot\build.ps1" -DevEcoHome $DevEcoHome -Task app
    & "$PSScriptRoot\build.ps1" -DevEcoHome $DevEcoHome -Task test
    foreach ($targetName in @('default', 'ohosTest')) {
        $hap = "entry\build\default\outputs\$targetName\entry-$targetName-unsigned.hap"
        $signed = "entry\build\default\outputs\$targetName\entry-$targetName-signed.hap"
        # 配好签名后优先安装对应的较新签名包，不能意外使用旧签名产物。
        if ((Test-Path -LiteralPath $signed) -and
            (Get-Item -LiteralPath $signed).LastWriteTimeUtc -ge (Get-Item -LiteralPath $hap).LastWriteTimeUtc) {
            $hap = $signed
        }
        $output = & $hdc -t $Target install $hap
        $output | Write-Output
        if (($output -join "`n") -notmatch 'install bundle successfully') { throw '安装失败；真机需要先配置签名。' }
    }
    $output = & $hdc -t $Target shell aa test -b com.chr.Yi_Da -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 120
    $output | Tee-Object -FilePath '.hvigor\runtime-tests.log'
    # aa test 的退出码和 TestFinished-ResultCode 不能代表用例全部成功。
    $report = $output -join "`n"
    if ($report -notmatch 'Tests run: (\d+), Failure: 0, Error: 0, Pass: (\d+), Ignore: 0' -or
        $Matches[1] -ne $Matches[2]) { throw '运行时测试未全通过，请查看 .hvigor/runtime-tests.log。' }
} finally { Pop-Location }
