# Native (Dockerless) production merge for wolo.codes.
# Mirrors project/render.sh: bake app, bake site, then copy site public THEN app public
# into project/build so the app overwrites (owns /).
[CmdletBinding()]
param(
    [string]$WebsiteRoot = 'E:\Web',
    [switch]$SkipScriptVersioning,
    [switch]$SkipApacheProbe
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

    # Copy visible contents (do not wipe DestDir — preserve firebase.json siblings at build root)
    Get-ChildItem -LiteralPath $SourceDir -Force | ForEach-Object {
        $name = $_.Name
        if ($name -eq '.' -or $name -eq '..' -or $name -eq '.git') { return }
        $dest = Join-Path $DestDir $name
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        }
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
