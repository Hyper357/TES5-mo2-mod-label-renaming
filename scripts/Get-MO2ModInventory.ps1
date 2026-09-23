[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ModsPath,

    [Parameter(Mandatory)]
    [string]$ProfilePath,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8Csv {
    param(
        [Parameter(Mandatory)] [object[]]$Data,
        [Parameter(Mandatory)] [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("mod-inventory-" + [guid]::NewGuid().ToString() + '.csv')
    try {
        $Data | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding utf8
        $text = [IO.File]::ReadAllText($temp)
        [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($true))
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Get-IniValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $match = [regex]::Match([IO.File]::ReadAllText($Path), '(?m)^' + [regex]::Escape($Key) + '=(.*)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ''
}

function Parse-DisplayName {
    param([string]$Name)
    $tags = @([regex]::Matches($Name, '【([^】]+)】') | ForEach-Object { $_.Groups[1].Value })
    $stem = [regex]::Replace($Name, '\s+—\s+【[^】]+】.*$', '')
    $separator = ' — '
    $index = $stem.IndexOf($separator, [StringComparison]::Ordinal)
    if ($index -ge 0) {
        $local = $stem.Substring(0, $index).Trim()
        $english = $stem.Substring($index + $separator.Length).Trim()
    }
    else {
        $local = ''
        $english = $stem.Trim()
    }
    [pscustomobject]@{
        LocalName = $local
        EnglishName = $english
        Tags = ($tags -join '、')
    }
}

$modlistPath = Join-Path $ProfilePath 'modlist.txt'
if (-not (Test-Path -LiteralPath $ModsPath -PathType Container)) { throw "ModsPath 不存在：$ModsPath" }
if (-not (Test-Path -LiteralPath $ProfilePath -PathType Container)) { throw "ProfilePath 不存在：$ProfilePath" }
if (-not (Test-Path -LiteralPath $modlistPath -PathType Leaf)) { throw "缺少 modlist.txt：$modlistPath" }

$rows = [System.Collections.Generic.List[object]]::new()
$lineNumber = 0
foreach ($line in [IO.File]::ReadAllLines($modlistPath)) {
    $lineNumber++
    if ($line -notmatch '^[+-]') { continue }

    $prefix = $line.Substring(0, 1)
    $name = $line.Substring(1)
    $parsed = Parse-DisplayName $name
    $folderPath = Join-Path $ModsPath $name
    $metaPath = Join-Path $folderPath 'meta.ini'
    $modId = Get-IniValue $metaPath 'modid'
    $version = Get-IniValue $metaPath 'version'
    $installationFile = Get-IniValue $metaPath 'installationFile'
    $isSeparator = $name -match '_separator$'
    $folderExists = Test-Path -LiteralPath $folderPath -PathType Container
    $status = if ($isSeparator) { 'separator' } elseif (-not $folderExists) { 'missing-folder' } elseif (-not $modId) { 'local-or-no-meta' } else { 'ok' }

    [void]$rows.Add([pscustomobject]@{
        LineNumber = $lineNumber
        Enabled = ($prefix -eq '+')
        Prefix = $prefix
        CurrentName = $name
        LocalName = $parsed.LocalName
        EnglishName = $parsed.EnglishName
        Tags = $parsed.Tags
        IsSeparator = $isSeparator
        FolderExists = $folderExists
        FolderPath = $folderPath
        ModId = $modId
        Version = $version
        InstallationFile = $installationFile
        NexusUrl = if ($modId -and $modId -ne '0') { "https://www.nexusmods.com/skyrimspecialedition/mods/$modId" } else { '' }
        SourceType = if ($modId -and $modId -ne '0') { 'Nexus' } else { 'LocalOrUnknown' }
        Status = $status
    })
}

if ($OutputPath) {
    Export-Utf8Csv -Data @($rows) -Path $OutputPath
    Write-Output "Inventory=$OutputPath"
    Write-Output "Rows=$($rows.Count)"
    Write-Output "MissingFolders=$(@($rows | Where-Object { -not $_.FolderExists }).Count)"
}
else {
    $rows
}
