param(
    [ValidateSet('dump', 'click', 'input', 'back', 'start', 'stop', 'screen')]
    [string]$Action = 'dump',
    [string]$Id = '',
    [string]$Text = '',
    [string]$Type = '',
    [string]$Value = '',
    [string]$Label = 'screen',
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoHome = 'D:\DevEco Studio 2\DevEco Studio'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$hdc = Join-Path $DevEcoHome 'sdk\default\openharmony\toolchains\hdc.exe'
$outputDir = Join-Path $root '.hvigor\ui'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
switch ($Action) {
    'start' { & $hdc -t $Target shell aa start -a EntryAbility -b com.chr.Yi_Da; return }
    'stop' { & $hdc -t $Target shell aa force-stop com.chr.Yi_Da; return }
    'back' { & $hdc -t $Target shell uitest uiInput keyEvent Back; return }
    'screen' {
        if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw '截图标签只能是字母、数字、横线和下划线。' }
        & $hdc -t $Target shell uitest screenCap -p /data/local/tmp/yida-ui.png | Out-Null
        $file = Join-Path $outputDir "$Label.png"
        & $hdc -t $Target file recv /data/local/tmp/yida-ui.png $file | Out-Null
        Write-Output $file
        return
    }
}
& $hdc -t $Target shell uitest dumpLayout -p /data/local/tmp/yida-ui.json | Out-Null
$layoutPath = Join-Path $outputDir 'layout.json'
& $hdc -t $Target file recv /data/local/tmp/yida-ui.json $layoutPath | Out-Null
$layout = Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
function Read-Nodes($node) {
    if ($node.attributes.visible -eq 'true') { $node.attributes }
    foreach ($child in $node.children) { Read-Nodes $child }
}
$nodes = @(Read-Nodes $layout)
if ($Action -eq 'dump') {
    $nodes | Where-Object { $_.text -or $_.id } | Select-Object text,id,type,bounds,enabled
    return
}
$found = @($nodes | Where-Object {
    ((($Id -and $_.id -eq $Id) -or (-not $Id -and $Text -and $_.text -eq $Text))) -and
    (-not $Type -or $_.type -eq $Type)
})
if ($found.Count -ne 1) { throw "需要唯一可见节点，找到 $($found.Count) 个。请检查最新布局。" }
$node = $found[0]
if ($node.enabled -eq 'false') { throw '目标控件当前不可用。' }
if ($node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw '目标节点边界无效。' }
$x = [int]( ([int]$Matches[1] + [int]$Matches[3]) / 2 )
$y = [int]( ([int]$Matches[2] + [int]$Matches[4]) / 2 )
if ($Action -eq 'click') {
    & $hdc -t $Target shell uitest uiInput click $x $y
} else {
    if ($Value -notmatch '^[a-zA-Z0-9_-]+$') { throw 'CLI 输入只用于无敏感内容的 ASCII 测试名称。' }
    & $hdc -t $Target shell uitest uiInput inputText $x $y $Value
}
