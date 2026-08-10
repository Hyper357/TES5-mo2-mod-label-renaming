[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PreviewPath,
    [Parameter(Mandatory)] [string]$ModsPath,
    [Parameter(Mandatory)] [string]$ProfilePath,
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8NoBom {
    param([Parameter(Mandatory)] [object[]]$Data, [Parameter(Mandatory)] [string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("mod-apply-" + [guid]::NewGuid().ToString() + '.csv')
    try {
        $Data | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding utf8
        [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($temp), [Text.UTF8Encoding]::new($false))
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Get-Manifest {
    param([Parameter(Mandatory)] [string]$Root)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $base -File -Recurse -ErrorAction SilentlyContinue)) {
        [void]$result.Add([pscustomobject]@{
            RelativePath = $file.FullName.Substring($base.Length + 1)
            Length = $file.Length
        })
    }
    $result
}

function Replace-ExactModlistEntries {
    param([string]$Text, [object[]]$Map)
    $lineEnding = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $parts = $Text -split '\r\n|\n|\r', -1
    foreach ($item in $Map) {
        $replaced = 0
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -eq ('+' + $item.OldName)) { $parts[$i] = '+' + $item.NewName; $replaced++ }
            elseif ($parts[$i] -eq ('-' + $item.OldName)) { $parts[$i] = '-' + $item.NewName; $replaced++ }
        }
        if ($replaced -ne 1) { throw "modlist.txt 中无法精确替换：$($item.OldName)，匹配数 $replaced" }
    }
    [string]::Join($lineEnding, $parts)
}

if (-not (Test-Path -LiteralPath $PreviewPath -PathType Leaf)) { throw "Preview 不存在：$PreviewPath" }
if (Get-Process -Name ModOrganizer,ModOrganizer2,SkyrimSE,SkyrimSELauncher,SkyrimLauncher -ErrorAction SilentlyContinue) {
    throw '检测到 MO2 或 Skyrim 进程。请关闭后再应用。'
}

$profileModlist = Join-Path $ProfilePath 'modlist.txt'
if (-not (Test-Path -LiteralPath $profileModlist -PathType Leaf)) { throw "缺少 modlist.txt：$profileModlist" }
$preview = @(Import-Csv -LiteralPath $PreviewPath)
$map = @($preview | Where-Object { $_.Changed -eq 'True' -and $_.ReadyToApply -eq 'True' })
if ($map.Count -eq 0) { throw '预览中没有 ReadyToApply=True 的变更。' }

$targetSet = @{}
foreach ($item in $map) {
    if ([string]::IsNullOrWhiteSpace($item.OldName) -or [string]::IsNullOrWhiteSpace($item.NewName)) { throw '存在空的 OldName 或 NewName。' }
    if ($item.NewName -match '[<>:"/\\|?*]') { throw "目标名含Windows非法字符：$($item.NewName)" }
    $key = $item.NewName.ToLowerInvariant()
    if ($targetSet.ContainsKey($key)) { throw "目标名重复：$($item.NewName)" }
    $targetSet[$key] = $true
    if (-not (Test-Path -LiteralPath (Join-Path $ModsPath $item.OldName) -PathType Container)) { throw "源文件夹不存在：$($item.OldName)" }
    if (Test-Path -LiteralPath (Join-Path $ModsPath $item.NewName)) { throw "目标文件夹已存在：$($item.NewName)" }
}

$liveText = [IO.File]::ReadAllText($profileModlist)
$liveLines = [IO.File]::ReadAllLines($profileModlist)
foreach ($item in $map) {
    $hits = @($liveLines | Where-Object { $_ -eq ('+' + $item.OldName) -or $_ -eq ('-' + $item.OldName) })
    if ($hits.Count -ne 1) { throw "源名称在 modlist.txt 中不是恰好一条：$($item.OldName)" }
}

if (-not $BackupPath) {
    $backupRoot = Join-Path (Split-Path -Parent $ProfilePath) 'mod-label-renaming-backups'
    $BackupPath = Join-Path $backupRoot ('rename_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
$backupMods = Join-Path $BackupPath 'mods'
New-Item -ItemType Directory -Path $backupMods -Force | Out-Null
Copy-Item -LiteralPath $profileModlist -Destination (Join-Path $BackupPath 'modlist.txt') -Force
foreach ($configName in @('plugins.txt', 'loadorder.txt')) {
    $configPath = Join-Path $ProfilePath $configName
    if (Test-Path -LiteralPath $configPath -PathType Leaf) { Copy-Item -LiteralPath $configPath -Destination (Join-Path $BackupPath $configName) -Force }
}
Copy-Item -LiteralPath $PreviewPath -Destination (Join-Path $BackupPath 'preview.csv') -Force
$map | Export-Csv -LiteralPath (Join-Path $BackupPath 'rename-map.csv') -NoTypeInformation -Encoding utf8

$manifest = [System.Collections.Generic.List[object]]::new()
foreach ($item in $map) {
    $source = Join-Path $ModsPath $item.OldName
    $files = @(Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue)
    [void]$manifest.Add([pscustomobject]@{
        OldName = $item.OldName
        NewName = $item.NewName
        FileCount = $files.Count
        TotalBytes = (($files | Measure-Object -Property Length -Sum).Sum)
    })
    Copy-Item -LiteralPath $source -Destination $backupMods -Recurse -Force
}
Export-Utf8NoBom -Data @($manifest) -Path (Join-Path $BackupPath 'folder-manifest-before.csv')

$moved = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($item in $map) {
        Rename-Item -LiteralPath (Join-Path $ModsPath $item.OldName) -NewName $item.NewName -ErrorAction Stop
        [void]$moved.Add($item)
    }

    $rewritten = Replace-ExactModlistEntries -Text $liveText -Map $map
    $tempModlist = Join-Path $ProfilePath ('.modlist.rename.' + [guid]::NewGuid().ToString() + '.tmp')
    [IO.File]::WriteAllText($tempModlist, $rewritten, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempModlist -Destination $profileModlist -Force
}
catch {
    foreach ($item in @($moved | Select-Object -Reverse)) {
        $newPath = Join-Path $ModsPath $item.NewName
        $oldPath = Join-Path $ModsPath $item.OldName
        if ((Test-Path -LiteralPath $newPath) -and -not (Test-Path -LiteralPath $oldPath)) { Rename-Item -LiteralPath $newPath -NewName $item.OldName -ErrorAction SilentlyContinue }
    }
    Copy-Item -LiteralPath (Join-Path $BackupPath 'modlist.txt') -Destination $profileModlist -Force
    throw
}

$postLines = [IO.File]::ReadAllLines($profileModlist)
foreach ($item in $map) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModsPath $item.NewName) -PathType Container)) { throw "应用后缺少目标文件夹：$($item.NewName)" }
    if (Test-Path -LiteralPath (Join-Path $ModsPath $item.OldName)) { throw "应用后旧文件夹仍存在：$($item.OldName)" }
    if (@($postLines | Where-Object { $_ -eq ('+' + $item.OldName) -or $_ -eq ('-' + $item.OldName) }).Count -ne 0) { throw "应用后旧名称仍在 modlist：$($item.OldName)" }
    if (@($postLines | Where-Object { $_ -eq ('+' + $item.NewName) -or $_ -eq ('-' + $item.NewName) }).Count -ne 1) { throw "应用后新名称不唯一：$($item.NewName)" }
}

Write-Output "Applied=$($map.Count)"
Write-Output "Backup=$BackupPath"
Write-Output "PluginsLoadorder=backed-up-read-only"
