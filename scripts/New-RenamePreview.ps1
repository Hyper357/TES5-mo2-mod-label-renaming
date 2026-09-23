[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$MapPath,
    [Parameter(Mandatory)] [string]$ModsPath,
    [Parameter(Mandatory)] [string]$ProfilePath,
    [Parameter(Mandatory)] [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8Csv {
    param([Parameter(Mandatory)] [object[]]$Data, [Parameter(Mandatory)] [string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("mod-preview-" + [guid]::NewGuid().ToString() + '.csv')
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

if (-not (Test-Path -LiteralPath $MapPath -PathType Leaf)) { throw "Rename map 不存在：$MapPath" }
$map = @(Import-Csv -LiteralPath $MapPath)
if ($map.Count -eq 0) { throw 'Rename map 为空。' }
foreach ($field in @('OldName', 'NewName')) {
    if (-not ($map[0].PSObject.Properties.Name -contains $field)) { throw "Rename map 缺少字段：$field" }
}
$modlistPath = Join-Path $ProfilePath 'modlist.txt'
if (-not (Test-Path -LiteralPath $modlistPath -PathType Leaf)) { throw "缺少 modlist.txt：$modlistPath" }

$lines = [IO.File]::ReadAllLines($modlistPath)
$otherProfiles = Get-OtherProfileModlists -ProfilePath $ProfilePath
$otherLines = @{}
foreach ($other in $otherProfiles) { $otherLines[[string]$other] = @([IO.File]::ReadAllLines($other)) }
$rows = [System.Collections.Generic.List[object]]::new()
$targetSet = @{}
$errors = [System.Collections.Generic.List[string]]::new()
$rowNumber = 0

foreach ($item in $map) {
    $rowNumber++
    $old = [string]$item.OldName
    $new = [string]$item.NewName
    $rowErrors = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($old)) { [void]$rowErrors.Add('OldName为空') }
    if ([string]::IsNullOrWhiteSpace($new)) { [void]$rowErrors.Add('NewName为空') }
    if ($new -match '[<>:"/\\|?*]') { [void]$rowErrors.Add('NewName含Windows非法字符') }
    $key = $new.ToLowerInvariant()
    if ($targetSet.ContainsKey($key)) { [void]$rowErrors.Add("目标名与第 $($targetSet[$key]) 行重复") } else { $targetSet[$key] = $rowNumber }

    $matches = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq ('+' + $old) -or $lines[$i] -eq ('-' + $old)) {
            $matches += [pscustomobject]@{ Line = $i + 1; Prefix = $lines[$i].Substring(0, 1) }
        }
    }
    if ($matches.Count -eq 0) { [void]$rowErrors.Add('OldName未在modlist.txt中找到') }
    if ($matches.Count -gt 1) { [void]$rowErrors.Add('OldName在modlist.txt中出现多次') }

    $otherRefs = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $otherLines.GetEnumerator()) {
        $found = @($entry.Value | Where-Object { $_ -eq ('+' + $old) -or $_ -eq ('-' + $old) })
        if ($found.Count -gt 0) { [void]$otherRefs.Add([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($entry.Key))) }
    }
    if ($otherRefs.Count -gt 0) { [void]$rowErrors.Add("OldName同时出现在其他profile：$($otherRefs -join '、')（应用会破坏该profile）") }

    $oldPath = Join-Path $ModsPath $old
    $newPath = Join-Path $ModsPath $new
    $oldExists = Test-Path -LiteralPath $oldPath -PathType Container
    $newExists = Test-Path -LiteralPath $newPath -PathType Container
    if (-not $oldExists) { [void]$rowErrors.Add('OldName文件夹不存在') }
    if ($newExists -and $old -ne $new) { [void]$rowErrors.Add('NewName文件夹已经存在') }

    $files = @()
    if ($oldExists) { $files = @(Get-ChildItem -LiteralPath $oldPath -File -Recurse -ErrorAction SilentlyContinue) }
    $totalBytes = 0
    if ($files.Count -gt 0) { $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum }
    $changed = $old -cne $new
    $status = if ($rowErrors.Count -eq 0 -and $changed) { 'Ready' } elseif (-not $changed) { 'NoChange' } else { 'Blocked' }
    if ($rowErrors.Count -gt 0) { foreach ($message in $rowErrors) { [void]$errors.Add("$old：$message") } }

    [void]$rows.Add([pscustomobject]@{
        MapRow = $rowNumber
        OldName = $old
        NewName = $new
        Changed = $changed
        Enabled = if ($matches.Count -eq 1) { $matches[0].Prefix -eq '+' } else { $null }
        Prefix = if ($matches.Count -eq 1) { $matches[0].Prefix } else { '' }
        ModListLine = if ($matches.Count -eq 1) { $matches[0].Line } else { 0 }
        FolderExists = $oldExists
        TargetExists = $newExists
        FileCount = $files.Count
        TotalBytes = $totalBytes
        Reason = [string]$item.Reason
        Confidence = [string]$item.Confidence
        SourceUrl = [string]$item.SourceUrl
        ReviewNote = [string]$item.ReviewNote
        ValidationStatus = $status
        ValidationErrors = ($rowErrors -join '；')
        OtherProfileRefs = ($otherRefs -join '、')
        ReadyToApply = ($status -eq 'Ready')
    })
}

Export-Utf8Csv -Data @($rows) -Path $OutputPath
Write-Output "Preview=$OutputPath"
Write-Output "Rows=$($rows.Count)"
Write-Output "Ready=$(@($rows | Where-Object { $_.ReadyToApply }).Count)"
Write-Output "Blocked=$(@($rows | Where-Object { $_.ValidationStatus -eq 'Blocked' }).Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
