[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InventoryPath,

    [Parameter(Mandatory)]
    [string]$RegistryPath,

    [string]$OutputPath = '.\work\rename-map-draft.csv',

    [string]$Separator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8Csv {
    param([Parameter(Mandatory)] [object[]]$Data, [Parameter(Mandatory)] [string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("mod-draft-" + [guid]::NewGuid().ToString() + '.csv')
    try {
        $Data | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding utf8
        [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($temp), [Text.UTF8Encoding]::new($true))
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

if (-not (Test-Path -LiteralPath $InventoryPath -PathType Leaf)) { throw "Inventory 不存在：$InventoryPath" }
if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) { throw "Registry 不存在：$RegistryPath" }

$inventory = @(Import-Csv -LiteralPath $InventoryPath)
$registry = @{}
foreach ($row in (Import-Csv -LiteralPath $RegistryPath)) { $registry[[string]$row.CurrentName] = $row }

if ($Separator) {
    $sepRow = @($inventory | Where-Object { $_.IsSeparator -eq 'True' -and [string]$_.CurrentName -like ('*' + $Separator + '*') } | Select-Object -First 1)
    if ($sepRow.Count -eq 0) { throw "未找到分隔区：$Separator" }
    $sepLine = [int]$sepRow[0].LineNumber
    $inventory = @($inventory | Where-Object { [int]$_.LineNumber -lt $sepLine })
    Write-Output "Scoped=分隔区 $Separator（$($sepRow[0].CurrentName)，以上条目 $($inventory.Count) 条）"
}

$drafts = [System.Collections.Generic.List[object]]::new()
$alreadyNamed = 0
$needsWork = 0

foreach ($inv in $inventory) {
    $reg = $null
    if ($registry.ContainsKey([string]$inv.CurrentName)) { $reg = $registry[[string]$inv.CurrentName] }

    $local = [string]$inv.LocalName
    $tags = [string]$inv.Tags
    if (($local -match '[一-鿿]') -and $tags) {
        $alreadyNamed++
        [void]$drafts.Add([pscustomobject]@{
            OldName = $inv.CurrentName
            NewName = $inv.CurrentName
            Reason = '已有中文名和标签，未改动'
            Confidence = '高'
            SourceUrl = [string]$inv.NexusUrl
            ReviewNote = '已命名'
            Status = '已命名·未改'
        })
        continue
    }

    $needsWork++
    $english = [string]($inv.EnglishName)
    if ($reg -and [string]$reg.OfficialNexusTitle) { $english = [string]$reg.OfficialNexusTitle }
    $anchor = ''
    if ($reg -and [string]$reg.SeriesCandidate) { $anchor = [string]$reg.SeriesCandidate }

    $tagList = [System.Collections.Generic.List[string]]::new()
    if ($tags) { foreach ($t in ($tags -split '、')) { if (-not $tagList.Contains($t)) { [void]$tagList.Add($t) } } }
    if ($anchor -and -not ($tagList | Where-Object { $_ -eq ('系列·' + $anchor) })) { [void]$tagList.Add('系列·' + $anchor) }
    if ($reg -and [string]$reg.Author -and -not ($tagList | Where-Object { $_ -eq ('作者·' + [string]$reg.Author) })) { [void]$tagList.Add('作者·' + [string]$reg.Author) }

    $tagPart = if ($tagList.Count -gt 0) { ' — ' + (($tagList | ForEach-Object { '【' + $_ + '】' }) -join '') } else { '' }
    $newName = if ($anchor) { "$anchor·中文功能名 — $english$tagPart" } else { "中文功能名 — $english$tagPart" }

    [void]$drafts.Add([pscustomobject]@{
        OldName = $inv.CurrentName
        NewName = $newName
        Reason = '自动初稿：官方标题/作者/系列来自登记表，中文功能名待人工核对填写'
        Confidence = '低'
        SourceUrl = if ($reg) { [string]$reg.NexusUrl } else { [string]$inv.NexusUrl }
        ReviewNote = '初稿'
        Status = '待补中文名'
    })
}

Export-Utf8Csv -Data @($drafts) -Path $OutputPath
Write-Output "Draft=$OutputPath"
Write-Output "Rows=$($drafts.Count)"
Write-Output "AlreadyNamed=$alreadyNamed"
Write-Output "NeedsWork=$needsWork"
