[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$parseErrors = [System.Collections.Generic.List[string]]::new()
foreach ($script in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { [void]$parseErrors.Add($script.Name + ': ' + (($errors | ForEach-Object { $_.Message }) -join '; ')) }
}
if ($parseErrors.Count -gt 0) { $parseErrors | ForEach-Object { Write-Error $_ }; exit 1 }

$fixtureMods = Join-Path $root 'fixtures\mo2\mods'
$fixtureProfile = Join-Path $root 'fixtures\mo2\profiles\Default'
$map = Join-Path $root 'examples\rename-map.csv'
$preview = Join-Path ([IO.Path]::GetTempPath()) ('mod-label-preview-' + [guid]::NewGuid().ToString() + '.csv')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mod-label-test-' + [guid]::NewGuid().ToString())
$testMods = Join-Path $testRoot 'mo2\mods'
$testProfile = Join-Path $testRoot 'mo2\profiles\Default'
$testBackup = Join-Path $testRoot 'backup'
try {
    & (Join-Path $PSScriptRoot 'New-RenamePreview.ps1') -MapPath $map -ModsPath $fixtureMods -ProfilePath $fixtureProfile -OutputPath $preview | Out-Host
    $childExitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    if ($childExitCode -ne 0) { throw 'fixture preview returned a non-zero exit code' }
    if (-not (Test-Path -LiteralPath $preview -PathType Leaf)) { throw 'fixture preview was not created' }
    $row = Import-Csv -LiteralPath $preview | Select-Object -First 1
    if ($row.ValidationStatus -ne 'Ready' -or $row.ReadyToApply -ne 'True') { throw 'fixture preview is not ReadyToApply' }

    $liveProcesses = @(Get-Process -Name ModOrganizer,ModOrganizer2,SkyrimSE,SkyrimSELauncher,SkyrimLauncher -ErrorAction SilentlyContinue)
    if ($liveProcesses.Count -gt 0) {
        Write-Warning '检测到 MO2/Skyrim 进程；本地测试只完成语法和预览测试，跳过夹具应用。GitHub Actions 会执行完整应用和验证。'
    }
    else {
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'fixtures\mo2') -Destination $testRoot -Recurse -Force
        & (Join-Path $PSScriptRoot 'Apply-RenameMap.ps1') -PreviewPath $preview -ModsPath $testMods -ProfilePath $testProfile -BackupPath $testBackup | Out-Host
        $childExitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($childExitCode -ne 0) { throw 'fixture apply returned a non-zero exit code' }
        & (Join-Path $PSScriptRoot 'Verify-RenameMap.ps1') -PreviewPath $preview -BackupPath $testBackup -ModsPath $testMods -ProfilePath $testProfile -HashFiles | Out-Host
        $childExitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($childExitCode -ne 0) { throw 'fixture verify returned a non-zero exit code' }
    }
}
finally {
    Remove-Item -LiteralPath $preview -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Project validation passed.'
