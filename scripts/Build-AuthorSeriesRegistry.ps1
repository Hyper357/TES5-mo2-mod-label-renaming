[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InventoryPath,

    [string]$OutputPath = '.\work\author-series-registry.csv',
    [string]$CachePath = '.\work\nexus-cache.csv',
    [string]$NexusApiKey,
    [switch]$SkipNexus,
    [int]$ThrottleMilliseconds = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8Csv {
    param([Parameter(Mandatory)] [object[]]$Data, [Parameter(Mandatory)] [string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("mod-registry-" + [guid]::NewGuid().ToString() + '.csv')
    try {
        $Data | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding utf8
        [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($temp), [Text.UTF8Encoding]::new($true))
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Get-VariantHint {
    param([string]$EnglishName)
    $hints = [System.Collections.Generic.List[string]]::new()
    $patterns = [ordered]@{
        '补丁' = '(?i)\bpatch(?:es)?\b|compatibility|integration|fix(?:es)?'
        '扩展' = '(?i)\baddon\b|\badd-on\b|extension|expansion'
        '分发' = '(?i)\bSPID\b|distribution|distributor'
        '材质' = '(?i)retexture|texture|material|PBR'
        '身体/体型' = '(?i)\b3BA\b|\bCBBE\b|\bHIMBO\b|\bBHUNP\b|\bUNP\b|\bUBE\b|Bodyslide|BodySlide|physics|HDT|SMP'
        '平台' = '(?i)\bAE\b|\bSE\b|\bVR\b|\bNG\b|1\.6\.\d+'
        '语音/翻译' = '(?i)voice|voiced|translation|translated|Chinese|Mandarin|English version'
        '资源/文件' = '(?i)\bassets?\b|resource|files?\b|library|framework'
        '变体' = '(?i)\bvariant\b|\bmale(?:s)?\b|\bfemale\b|\b[1-9]\b|\b[2-8]K\b'
    }
    foreach ($entry in $patterns.GetEnumerator()) {
        if ($EnglishName -match $entry.Value) { [void]$hints.Add($entry.Key) }
    }
    $hints -join '、'
}

function Get-SeriesCandidate {
    param([string]$EnglishName, [string]$Author, [string]$ExistingSeriesTag)
    if (-not [string]::IsNullOrWhiteSpace($ExistingSeriesTag)) { return $ExistingSeriesTag }
    if ($EnglishName -match '^(?i)([^-–—:]+?)\s+[-–—:]') { return $matches[1].Trim() }
    if ($Author -and $EnglishName -match ('^(?i)' + [regex]::Escape($Author))) { return $Author }
    return ''
}

if (-not (Test-Path -LiteralPath $InventoryPath -PathType Leaf)) { throw "Inventory 不存在：$InventoryPath" }
$inventory = @(Import-Csv -LiteralPath $InventoryPath)
$cache = @{}
if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
    foreach ($item in (Import-Csv -LiteralPath $CachePath)) { $cache[[string]$item.ModId] = $item }
}

$apiKeyValue = if ($NexusApiKey) { $NexusApiKey } elseif ($env:NEXUS_API_KEY) { $env:NEXUS_API_KEY } else { '' }
$uniqueIds = @($inventory | Where-Object { $_.ModId -and $_.ModId -ne '0' } | Select-Object -ExpandProperty ModId -Unique)

if (-not $SkipNexus -and $apiKeyValue -and $uniqueIds.Count -gt 0) {
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $client.DefaultRequestHeaders.Add('apikey', $apiKeyValue)
    $client.DefaultRequestHeaders.Add('Accept', 'application/json')
    try {
        foreach ($id in $uniqueIds) {
            if ($cache.ContainsKey([string]$id) -and $cache[[string]$id].Status -eq 'ok') { continue }
            try {
                $url = "https://api.nexusmods.com/v1/games/skyrimspecialedition/mods/$id.json"
                $data = $client.GetStringAsync($url).GetAwaiter().GetResult() | ConvertFrom-Json
                $cache[[string]$id] = [pscustomobject]@{ ModId = $id; Author = $data.author; Name = $data.name; Summary = $data.summary; Updated = $data.updated_time; Status = 'ok'; Error = '' }
            }
            catch {
                $cache[[string]$id] = [pscustomobject]@{ ModId = $id; Author = ''; Name = ''; Summary = ''; Updated = ''; Status = 'error'; Error = $_.Exception.Message }
            }
            if ($ThrottleMilliseconds -gt 0) { Start-Sleep -Milliseconds $ThrottleMilliseconds }
        }
    }
    finally { $client.Dispose() }
}

if ($cache.Count -gt 0) { Export-Utf8Csv -Data @($cache.Values | Sort-Object { [int]$_.ModId }) -Path $CachePath }

$registry = foreach ($row in $inventory) {
    $api = if ($row.ModId -and $cache.ContainsKey([string]$row.ModId)) { $cache[[string]$row.ModId] } else { $null }
    $author = if ($api) { $api.Author } else { '' }
    $title = if ($api -and $api.Name) { $api.Name } else { $row.EnglishName }
    $existingSeries = @($row.Tags -split '、' | Where-Object { $_ -match '^系列·' } | ForEach-Object { $_ -replace '^系列·', '' } | Select-Object -First 1) -join ''
    [pscustomobject]@{
        LineNumber = $row.LineNumber
        Enabled = $row.Enabled
        CurrentName = $row.CurrentName
        LocalName = $row.LocalName
        EnglishName = $row.EnglishName
        ModId = $row.ModId
        NexusUrl = $row.NexusUrl
        Author = $author
        OfficialNexusTitle = $title
        OfficialSummary = if ($api) { $api.Summary } else { '' }
        ExistingSeriesTag = $existingSeries
        SeriesCandidate = Get-SeriesCandidate $row.EnglishName $author $existingSeries
        VariantHint = Get-VariantHint $row.EnglishName
        ExistingTags = $row.Tags
        SourceType = $row.SourceType
        ReviewStatus = if ($api -and $api.Status -eq 'ok') { 'Nexus元数据已取得·需要页面核对' } elseif ($row.ModId) { 'Nexus元数据未取得·需要页面核对' } else { '本地/无NexusID·人工确认' }
        TitleMatch = if ($api -and $api.Name -eq $row.EnglishName) { '一致' } elseif ($api -and $api.Name) { '当前英文名与Nexus标题不同' } else { '' }
    }
}

Export-Utf8Csv -Data @($registry) -Path $OutputPath
Write-Output "Registry=$OutputPath"
Write-Output "Rows=$($registry.Count)"
Write-Output "NexusIds=$(@($registry | Where-Object { $_.ModId -and $_.ModId -ne '0' } | Select-Object -ExpandProperty ModId -Unique).Count)"
Write-Output "MetadataRows=$(@($registry | Where-Object { $_.Author }).Count)"
