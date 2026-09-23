[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProfilePath,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8Csv {
    param([Parameter(Mandatory)] [object[]]$Data, [Parameter(Mandatory)] [string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("mod-tags-" + [guid]::NewGuid().ToString() + '.csv')
    try {
        $Data | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding utf8
        [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($temp), [Text.UTF8Encoding]::new($true))
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

$modlistPath = Join-Path $ProfilePath 'modlist.txt'
if (-not (Test-Path -LiteralPath $modlistPath -PathType Leaf)) { throw "缺少 modlist.txt：$modlistPath" }

$tagCounts = @{}
$tagSamples = @{}
$tagged = 0
$total = 0

foreach ($line in [IO.File]::ReadAllLines($modlistPath)) {
    if ($line -notmatch '^[+-]') { continue }
    $total++
    $tags = @([regex]::Matches($line, '【([^】]+)】') | ForEach-Object { $_.Groups[1].Value })
    if ($tags.Count -gt 0) { $tagged++ }
    foreach ($tag in $tags) {
        if (-not $tagCounts.ContainsKey($tag)) { $tagCounts[$tag] = 0; $tagSamples[$tag] = [System.Collections.Generic.List[string]]::new() }
        $tagCounts[$tag]++
        if ($tagSamples[$tag].Count -lt 5) { [void]$tagSamples[$tag].Add($line.Substring(1)) }
    }
}

$rows = foreach ($tag in @($tagCounts.Keys | Sort-Object { -$tagCounts[$_] })) {
    [pscustomobject]@{
        Tag = $tag
        Count = $tagCounts[$tag]
        Samples = ($tagSamples[$tag] -join ' | ')
    }
}

if ($OutputPath) {
    Export-Utf8Csv -Data @($rows) -Path $OutputPath
    Write-Output "Tags=$OutputPath"
}
Write-Output "ModsTotal=$total"
Write-Output "ModsTagged=$tagged"
Write-Output "TaggedRate=$([math]::Round(100 * $tagged / [math]::Max(1, $total), 1))%"
Write-Output "UniqueTags=$($rows.Count)"
Write-Output ''
Write-Output 'Count  Tag'
$rows | Select-Object -First 60 | ForEach-Object { '{0,5}  {1}' -f $_.Count, $_.Tag }
