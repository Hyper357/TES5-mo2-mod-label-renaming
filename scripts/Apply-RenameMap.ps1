[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PreviewPath,
    [Parameter(Mandatory)] [string]$ModsPath,
    [Parameter(Mandatory)] [string]$ProfilePath,
    [string]$BackupPath,
    [switch]$CopyFolders
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8Csv {
    param([Parameter(Mandatory)] [object[]]$Data, [Parameter(Mandatory)] [string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("mod-apply-" + [guid]::NewGuid().ToString() + '.csv')
    try {
        $Data | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding utf8
        [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($temp), [Text.UTF8Encoding]::new($true))
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Get-OtherProfileModlists {
    param([Parameter(Mandatory)] [string]$ProfilePath)
    $profilesRoot = Split-Path -Parent $ProfilePath
    $current = [IO.Path]::GetFullPath($ProfilePath).TrimEnd('\')
    $result = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $profilesRoot -PathType Container) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue)) {
            if ([IO.Path]::GetFullPath($dir.FullName).TrimEnd('\') -eq $current) { continue }
            $modlist = Join-Path $dir.FullName 'modlist.txt'
            if (Test-Path -LiteralPath $modlist -PathType Leaf) { [void]$result.Add($modlist) }
        }
    }
    @($result)
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

function Get-LineEnding {
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Replace-ExactModlistEntries {
    param([string[]]$Lines, [object[]]$Map, [string]$LineEnding, [bool]$TrailingNewline)
    # 用调用方 ReadAllLines 得到的行数组做替换，不要自行对原始文本 -split。
    # ReadAllLines 是全部脚本统一采用、且已在多个 PowerShell 版本上验证过的读取路径；
    # 自行 split 会让解析结果随宿主版本变化（CI 上曾出现行匹配数恒为 0）。
    $parts = @($Lines)
    foreach ($item in $Map) {
        $replaced = 0
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -eq ('+' + $item.OldName)) { $parts[$i] = '+' + $item.NewName; $replaced++ }
            elseif ($parts[$i] -eq ('-' + $item.OldName)) { $parts[$i] = '-' + $item.NewName; $replaced++ }
        }
        if ($replaced -ne 1) {
            $probe = @($parts | Where-Object { $_ -like ('*' + $item.OldName + '*') } | Select-Object -First 3) -join ' ‖ '
            throw ("modlist.txt 中无法精确替换：{0}，匹配数 {1}；读取行数 {2}；含该名称的行：[{3}]" -f $item.OldName, $replaced, $parts.Count, $probe)
        }
    }
    $joined = [string]::Join($LineEnding, $parts)
    # ReadAllLines 不保留结尾换行，而 MO2 写出的 modlist.txt 是带尾随换行的，必须补回。
    if ($TrailingNewline) { $joined += $LineEnding }
    return $joined
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
$lineEnding = Get-LineEnding -Text $liveText
$trailingNewline = $liveText.EndsWith("`n") -or $liveText.EndsWith("`r")
foreach ($item in $map) {
    $hits = @($liveLines | Where-Object { $_ -eq ('+' + $item.OldName) -or $_ -eq ('-' + $item.OldName) })
    if ($hits.Count -ne 1) { throw "源名称在 modlist.txt 中不是恰好一条：$($item.OldName)" }
}

foreach ($otherModlist in (Get-OtherProfileModlists -ProfilePath $ProfilePath)) {
    $otherLines = @([IO.File]::ReadAllLines($otherModlist))
    $profileName = [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($otherModlist))
    foreach ($item in $map) {
        if (@($otherLines | Where-Object { $_ -eq ('+' + $item.OldName) -or $_ -eq ('-' + $item.OldName) }).Count -gt 0) {
            throw "OldName 同时出现在其他 profile（$profileName），应用会破坏该 profile：$($item.OldName)"
        }
    }
}

if (-not $BackupPath) {
    $backupRoot = Join-Path (Split-Path -Parent $ProfilePath) 'mod-label-renaming-backups'
    $BackupPath = Join-Path $backupRoot ('rename_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
$backupMods = Join-Path $BackupPath 'mods'
if ($CopyFolders) { New-Item -ItemType Directory -Path $backupMods -Force | Out-Null }
Copy-Item -LiteralPath $profileModlist -Destination (Join-Path $BackupPath 'modlist.txt') -Force
foreach ($configName in @('plugins.txt', 'loadorder.txt')) {
    $configPath = Join-Path $ProfilePath $configName
    if (Test-Path -LiteralPath $configPath -PathType Leaf) { Copy-Item -LiteralPath $configPath -Destination (Join-Path $BackupPath $configName) -Force }
}
Copy-Item -LiteralPath $PreviewPath -Destination (Join-Path $BackupPath 'preview.csv') -Force
Export-Utf8Csv -Data @($map) -Path (Join-Path $BackupPath 'rename-map.csv')

$manifest = [System.Collections.Generic.List[object]]::new()
foreach ($item in $map) {
    $source = Join-Path $ModsPath $item.OldName
    $files = @(Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue)
    [void]$manifest.Add([pscustomobject]@{
        OldName = $item.OldName
        NewName = $item.NewName
        FileCount = $files.Count
        TotalBytes = if ($files.Count -gt 0) { (($files | Measure-Object -Property Length -Sum).Sum) } else { 0 }
    })
    if ($CopyFolders) { Copy-Item -LiteralPath $source -Destination $backupMods -Recurse -Force }
}
Export-Utf8Csv -Data @($manifest) -Path (Join-Path $BackupPath 'folder-manifest-before.csv')

$moved = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($item in $map) {
        $sourcePath = Join-Path $ModsPath $item.OldName
        $targetPath = Join-Path $ModsPath $item.NewName
        # 用 .NET 做字面量改名，而不是 Rename-Item -NewName：
        # -NewName 在不同 PowerShell 版本下对通配符字符（尤其方括号）的处理不一致，
        # 而 2.0 命名规范的 [母体作者] 前缀会让目标名必然带方括号。
        [IO.Directory]::Move($sourcePath, $targetPath)
        [void]$moved.Add($item)
    }

    $rewritten = Replace-ExactModlistEntries -Lines $liveLines -Map $map -LineEnding $lineEnding -TrailingNewline $trailingNewline
    $tempModlist = Join-Path $ProfilePath ('.modlist.rename.' + [guid]::NewGuid().ToString() + '.tmp')
    [IO.File]::WriteAllText($tempModlist, $rewritten, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempModlist -Destination $profileModlist -Force
}
catch {
    $applyError = $_

    # 逆序回滚已改名的文件夹。用逆序 for 循环而不是 Select-Object -Reverse：
    # Select-Object 没有 -Reverse 参数，这行本身会抛终止错误并掩盖真正的异常。
    # 每步都独立 try/catch，清理失败同样不得掩盖原始异常。
    for ($i = $moved.Count - 1; $i -ge 0; $i--) {
        $item = $moved[$i]
        try {
            $newPath = Join-Path $ModsPath $item.NewName
            $oldPath = Join-Path $ModsPath $item.OldName
            if ((Test-Path -LiteralPath $newPath) -and -not (Test-Path -LiteralPath $oldPath)) {
                [IO.Directory]::Move($newPath, $oldPath)
            }
        }
        catch { }
    }
    try { Copy-Item -LiteralPath (Join-Path $BackupPath 'modlist.txt') -Destination $profileModlist -Force -ErrorAction Stop }
    catch { }

    # 必须用 Write-Output 而不是 Write-Error：调用方可能设置了
    # $ErrorActionPreference='Stop'，那会把 Write-Error 变成终止错误，
    # 于是原始异常再次被掩盖 —— 这正是之前 CI 只看到 'Reverse' 报错的原因。
    Write-Output "Apply-RenameMap 失败：$($applyError.Exception.Message)"
    Write-Output "  位置：$($applyError.InvocationInfo.PositionMessage.Trim())"
    Write-Output "  宿主：PowerShell $($PSVersionTable.PSVersion) / $($PSVersionTable.PSEdition)"
    throw $applyError
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
Write-Output "BackupMode=$(if ($CopyFolders) { 'full-folder-copy' } else { 'manifest-only' })"
Write-Output "PluginsLoadorder=backed-up-read-only"
