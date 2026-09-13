# Native (Dockerless) production merge for wolo.codes.
# Mirrors project/render.sh: bake app, bake site, then copy site public THEN app public
# into project/build so the app overwrites (owns /).
[CmdletBinding()]
param(
    [string]$WebsiteRoot = 'E:\Web',
    [switch]$SkipScriptVersioning,
    [switch]$SkipApacheProbe,
    [switch]$SkipBuildIncrement
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'PublishRunner.ps1')

$buildRoot = Join-Path $WebsiteRoot 'project\build'
$buildInterim = Join-Path $buildRoot 'interim'
$buildPublic = Join-Path $buildRoot 'public'

foreach ($dir in @($buildInterim, $buildPublic)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Copy-WoloDotDirs {
    param(
        [Parameter(Mandatory)] [string]$SourceDir,
        [Parameter(Mandatory)] [string]$DestDir
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "Missing Tiggu output directory: $SourceDir"
    }
    if (-not (Test-Path -LiteralPath $DestDir -PathType Container)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }

    # Merge into DestDir. Copy-Item -Recurse onto an existing folder nests
    # source\about into dest\about\about and leaves stale dest\about\index.html.
    $rc = & robocopy.exe $SourceDir $DestDir /E /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed ($LASTEXITCODE) from $SourceDir to $DestDir"
    }
    $null = $rc
}

if (-not $SkipBuildIncrement) {
    Write-Host "=== Increment app build number ===" -ForegroundColor Cyan
    $incrementScript = Join-Path $WebsiteRoot 'app\project\scripts\increment-build-number.js'
    $varsPath = Join-Path $WebsiteRoot 'app\project\Root\Config\Vars.tsv'
    $node = (Get-Command node -ErrorAction Stop).Source
    & $node $incrementScript $varsPath
    if ($LASTEXITCODE -ne 0) {
        throw "App build-number increment failed with exit code $LASTEXITCODE."
    }
}

Write-Host "=== Native Tiggu: app ===" -ForegroundColor Cyan
Invoke-WoloNativeTiggu -Kind app -WebsiteRoot $WebsiteRoot -SkipScriptVersioning:$SkipScriptVersioning -SkipApacheProbe:$SkipApacheProbe

Write-Host "=== Native Tiggu: site ===" -ForegroundColor Cyan
Invoke-WoloNativeTiggu -Kind site -WebsiteRoot $WebsiteRoot -SkipScriptVersioning:$SkipScriptVersioning -SkipApacheProbe:$SkipApacheProbe

# Same order as render.sh: site first, then app (app overwrites for index.html etc.)
Write-Host "=== Merge into project/build (site then app) ===" -ForegroundColor Cyan
$siteInterim = Join-Path $WebsiteRoot 'site\project\interim'
$sitePublic = Join-Path $WebsiteRoot 'site\project\public'
$appInterim = Join-Path $WebsiteRoot 'app\project\interim'
$appPublic = Join-Path $WebsiteRoot 'app\project\public'

Copy-WoloDotDirs -SourceDir $siteInterim -DestDir $buildInterim
Copy-WoloDotDirs -SourceDir $sitePublic -DestDir $buildPublic
Copy-WoloDotDirs -SourceDir $appInterim -DestDir $buildInterim
Copy-WoloDotDirs -SourceDir $appPublic -DestDir $buildPublic

Write-Host "=== SRI gate: merged public ===" -ForegroundColor Cyan
Invoke-WoloSriGate -WebsiteRoot $WebsiteRoot -Dir $buildPublic

Write-Host "Native render complete. Output: $buildPublic" -ForegroundColor Green
