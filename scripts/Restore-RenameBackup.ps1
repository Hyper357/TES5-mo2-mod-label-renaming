[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$BackupPath,
    [Parameter(Mandatory)] [string]$ModsPath,
    [Parameter(Mandatory)] [string]$ProfilePath,
    [switch]$RestorePluginAndLoadorder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Get-Process -Name ModOrganizer,ModOrganizer2,SkyrimSE,SkyrimSELauncher,SkyrimLauncher -ErrorAction SilentlyContinue) {
    throw '检测到 MO2 或 Skyrim 进程。请关闭后再恢复。'
}
$mapPath = Join-Path $BackupPath 'rename-map.csv'
$backupModlist = Join-Path $BackupPath 'modlist.txt'
$backupMods = Join-Path $BackupPath 'mods'
if (-not (Test-Path -LiteralPath $mapPath -PathType Leaf)) { throw "备份缺少 rename-map.csv：$BackupPath" }
if (-not (Test-Path -LiteralPath $backupModlist -PathType Leaf)) { throw "备份缺少 modlist.txt：$BackupPath" }

$map = @(Import-Csv -LiteralPath $mapPath)
$quarantine = Join-Path $BackupPath ('rollback-quarantine-' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$fullBackup = Test-Path -LiteralPath $backupMods -PathType Container

if ($fullBackup) {
    New-Item -ItemType Directory -Path $quarantine -Force | Out-Null
    foreach ($item in $map) {
        $newPath = Join-Path $ModsPath $item.NewName
        $oldPath = Join-Path $ModsPath $item.OldName
        $backupOld = Join-Path $backupMods $item.OldName
        if (-not (Test-Path -LiteralPath $backupOld -PathType Container)) { throw "备份缺少源文件夹：$($item.OldName)" }
        if (Test-Path -LiteralPath $oldPath) { throw "恢复会覆盖已有旧文件夹，已停止：$($item.OldName)" }
        if (Test-Path -LiteralPath $newPath) { Move-Item -LiteralPath $newPath -Destination $quarantine -Force }
        Copy-Item -LiteralPath $backupOld -Destination $ModsPath -Recurse -Force
    }
}
else {
    $quarantine = ''
    foreach ($item in $map) {
        $newPath = Join-Path $ModsPath $item.NewName
        $oldPath = Join-Path $ModsPath $item.OldName
        if (Test-Path -LiteralPath $oldPath -PathType Container) { continue }
        if (-not (Test-Path -LiteralPath $newPath -PathType Container)) { throw "当前文件夹不存在，无法改回旧名：$($item.NewName)" }
        Rename-Item -LiteralPath $newPath -NewName $item.OldName -ErrorAction Stop
    }
}

Copy-Item -LiteralPath $backupModlist -Destination (Join-Path $ProfilePath 'modlist.txt') -Force
if ($RestorePluginAndLoadorder) {
    foreach ($configName in @('plugins.txt', 'loadorder.txt')) {
        $source = Join-Path $BackupPath $configName
        if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $ProfilePath $configName) -Force }
    }
}

Write-Output "Restored=$($map.Count)"
Write-Output "Mode=$(if ($fullBackup) { 'full-folder-copy' } else { 'rename-back' })"
Write-Output "Quarantine=$quarantine"
Write-Output "PluginLoadorderRestored=$($RestorePluginAndLoadorder.IsPresent)"
