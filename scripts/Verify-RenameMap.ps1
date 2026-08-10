[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PreviewPath,
    [Parameter(Mandatory)] [string]$BackupPath,
    [Parameter(Mandatory)] [string]$ModsPath,
    [Parameter(Mandatory)] [string]$ProfilePath,
    [switch]$HashFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Manifest {
    param([Parameter(Mandatory)] [string]$Root, [switch]$IncludeHash)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $result = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $base -File -Recurse -ErrorAction SilentlyContinue)) {
        $relative = $file.FullName.Substring($base.Length + 1)
        $hash = if ($IncludeHash) { (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash } else { '' }
        $result[$relative] = [pscustomobject]@{ Length = $file.Length; Hash = $hash }
    }
    $result
}

if (-not (Test-Path -LiteralPath $PreviewPath -PathType Leaf)) { throw "Preview 不存在：$PreviewPath" }
if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) { throw "Backup 不存在：$BackupPath" }
$map = @(Import-Csv -LiteralPath $PreviewPath | Where-Object { $_.Changed -eq 'True' })
$modlistPath = Join-Path $ProfilePath 'modlist.txt'
$lines = [IO.File]::ReadAllLines($modlistPath)
$errors = [System.Collections.Generic.List[string]]::new()
$rows = [System.Collections.Generic.List[object]]::new()

foreach ($item in $map) {
    $current = Join-Path $ModsPath $item.NewName
    $before = Join-Path (Join-Path $BackupPath 'mods') $item.OldName
    $currentExists = Test-Path -LiteralPath $current -PathType Container
    $oldExists = Test-Path -LiteralPath (Join-Path $ModsPath $item.OldName) -PathType Container
    $newLineCount = @($lines | Where-Object { $_ -eq ('+' + $item.NewName) -or $_ -eq ('-' + $item.NewName) }).Count
    if (-not $currentExists) { [void]$errors.Add("缺少新文件夹：$($item.NewName)") }
    if ($oldExists) { [void]$errors.Add("旧文件夹仍存在：$($item.OldName)") }
    if ($newLineCount -ne 1) { [void]$errors.Add("modlist 新名称数量错误：$($item.NewName) = $newLineCount") }

    $contentMatch = $false
    if ($currentExists -and (Test-Path -LiteralPath $before -PathType Container)) {
        $a = Get-Manifest -Root $current -IncludeHash:$HashFiles
        $b = Get-Manifest -Root $before -IncludeHash:$HashFiles
        $diff = @()
        if ($a.Count -ne $b.Count) { $diff += 'file-count' }
        foreach ($key in @($a.Keys + $b.Keys | Sort-Object -Unique)) {
            if (-not $a.ContainsKey($key) -or -not $b.ContainsKey($key)) { $diff += $key; continue }
            if ($a[$key].Length -ne $b[$key].Length) { $diff += $key; continue }
            if ($HashFiles -and $a[$key].Hash -ne $b[$key].Hash) { $diff += $key }
        }
        $contentMatch = ($diff.Count -eq 0)
        if (-not $contentMatch) { [void]$errors.Add("内容校验失败：$($item.NewName)") }
    }

    [void]$rows.Add([pscustomobject]@{
        NewName = $item.NewName
        ModListLineCount = $newLineCount
        ContentMatch = $contentMatch
        HashFiles = $HashFiles.IsPresent
    })
}

foreach ($configName in @('plugins.txt', 'loadorder.txt')) {
    $current = Join-Path $ProfilePath $configName
    $before = Join-Path $BackupPath $configName
    if ((Test-Path -LiteralPath $current -PathType Leaf) -and (Test-Path -LiteralPath $before -PathType Leaf)) {
        $a = (Get-FileHash -Algorithm SHA256 -LiteralPath $current).Hash
        $b = (Get-FileHash -Algorithm SHA256 -LiteralPath $before).Hash
        if ($a -ne $b) { [void]$errors.Add("配置文件发生变化：$configName") }
        Write-Output "$configName=$a"
    }
}

$rows | Format-Table -AutoSize
Write-Output "Targets=$($rows.Count)"
Write-Output "Errors=$($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
