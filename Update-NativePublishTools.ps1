[CmdletBinding()]
param(
    [string]$WebsiteRoot = 'D:\Wolo\Web',
    [ValidateSet('all', 'closure-compiler', 'minify')]
    [string]$Tool = 'all',
    [switch]$CheckOnly,
    [switch]$Force,
    [switch]$CleanOldVersions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $WebsiteRoot -or -not (Test-Path -LiteralPath $WebsiteRoot)) {
    $parentDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (Test-Path -LiteralPath (Join-Path $parentDir '.native-tools')) {
        $WebsiteRoot = $parentDir
    } elseif (Test-Path -LiteralPath 'D:\Wolo\Web\.native-tools') {
        $WebsiteRoot = 'D:\Wolo\Web'
    } else {
        $WebsiteRoot = $parentDir
    }
}
$WebsiteRoot = [System.IO.Path]::GetFullPath($WebsiteRoot)
$toolsRoot = Join-Path $WebsiteRoot '.native-tools'
$toolchainJsonPath = Join-Path $toolsRoot 'toolchain.json'

New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null

function Write-Section {
    param([Parameter(Mandatory)] [string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-WoloJava {
    $preferredJava = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
    if (Test-Path -LiteralPath $preferredJava -PathType Leaf) {
        return $preferredJava
    }
    foreach ($candidate in @(
        'C:\Program Files\Java\*\bin\java.exe',
        'C:\Program Files\Eclipse Adoptium\*\bin\java.exe',
        'C:\Program Files\Microsoft\jdk-*\bin\java.exe'
    )) {
        $hit = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $fromPath = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    return $null
}

function Invoke-ClosureCompilerJava {
    param(
        [Parameter(Mandatory)] [string]$JavaPath,
        [Parameter(Mandatory)] [string[]]$ArgumentList
    )

    $extraArgs = @()
    try {
        & $JavaPath --sun-misc-unsafe-memory-access=allow -version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $extraArgs += '--sun-misc-unsafe-memory-access=allow'
        }
    } catch { }

    & $JavaPath @extraArgs @ArgumentList
}

function Ensure-WoloJavaClosureWrapper {
    param(
        [Parameter(Mandatory)] [string]$ToolsRoot,
        [Parameter(Mandatory)] [string]$JavaPath
    )

    $wrapperPath = Join-Path $ToolsRoot 'java-closure.sh'
    $full = [System.IO.Path]::GetFullPath($JavaPath)
    $javaUnix = if ($full -match '^([A-Za-z]):\\(.*)$') {
        '/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
    } else {
        $full -replace '\\', '/'
    }

    $supportsUnsafeFlag = $false
    try {
        & $JavaPath --sun-misc-unsafe-memory-access=allow -version 2>&1 | Out-Null
        $supportsUnsafeFlag = ($LASTEXITCODE -eq 0)
    } catch {
        $supportsUnsafeFlag = $false
    }

    $extraArgs = if ($supportsUnsafeFlag) { ' --sun-misc-unsafe-memory-access=allow' } else { '' }
    $scriptContent = "#!/usr/bin/env bash`nexec `"$javaUnix`"$extraArgs `"`$@`"`n"

    $needsWrite = $true
    if (Test-Path -LiteralPath $wrapperPath -PathType Leaf) {
        try {
            $existing = [System.IO.File]::ReadAllText($wrapperPath)
            if ($existing -eq $scriptContent) {
                $needsWrite = $false
            }
        } catch { }
    }

    if ($needsWrite) {
        [System.IO.File]::WriteAllText($wrapperPath, $scriptContent, [System.Text.UTF8Encoding]::new($false))
    }

    return $wrapperPath
}

function Get-ToolchainMetadata {
    if (Test-Path -LiteralPath $toolchainJsonPath -PathType Leaf) {
        try {
            return (Get-Content -LiteralPath $toolchainJsonPath -Raw | ConvertFrom-Json)
        } catch { }
    }
    return [pscustomobject]@{}
}

function Save-ToolchainMetadata {
    param([Parameter(Mandatory)] [psobject]$Metadata)
    $json = $Metadata | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($toolchainJsonPath, $json, [System.Text.Encoding]::UTF8)
}

function Get-InstalledClosureCompilerInfo {
    $java = Get-WoloJava
    $jars = @(Get-ChildItem -LiteralPath $toolsRoot -Filter 'closure-compiler-*.jar' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property Name -Descending)
    $canonical = Join-Path $toolsRoot 'closure-compiler.jar'
    $targetJar = $null

    if ($jars.Count -gt 0) {
        $targetJar = $jars[0].FullName
    } elseif (Test-Path -LiteralPath $canonical -PathType Leaf) {
        $targetJar = $canonical
    }

    if (-not $targetJar) {
        return [pscustomobject]@{
            Installed    = $false
            Version      = 'none'
            JarPath      = $null
            Sha256       = $null
        }
    }

    $version = 'unknown'
    if ($targetJar -match 'closure-compiler-(v?\d+)\.jar$') {
        $version = $Matches[1]
    }

    if ($java) {
        try {
            $output = Invoke-ClosureCompilerJava -JavaPath $java -ArgumentList @('-jar', $targetJar, '--version') 2>&1
            if ($LASTEXITCODE -eq 0) {
                $verLine = ($output | Where-Object { $_ -match 'Version:\s*(v?\d+)' } | Select-Object -First 1)
                if ($verLine -and $verLine -match 'Version:\s*(v?\d+)') {
                    $version = $Matches[1]
                }
            }
        } catch { }
    }

    $hash = (Get-FileHash -LiteralPath $targetJar -Algorithm SHA256).Hash

    return [pscustomobject]@{
        Installed    = $true
        Version      = $version
        JarPath      = $targetJar
        Sha256       = $hash
    }
}

function Get-LatestClosureCompilerInfo {
    $metaUrl = 'https://repo1.maven.org/maven2/com/google/javascript/closure-compiler/maven-metadata.xml'
    $xmlContent = & curl.exe -sL --retry 3 $metaUrl
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($xmlContent)) {
        throw "Failed to fetch Closure Compiler Maven metadata from $metaUrl"
    }

    [xml]$xml = $xmlContent
    $version = $null
    if ($xml.metadata.versioning.release) {
        $version = [string]$xml.metadata.versioning.release
    } elseif ($xml.metadata.versioning.latest) {
        $version = [string]$xml.metadata.versioning.latest
    } else {
        $allVersions = @($xml.metadata.versioning.versions.version)
        if ($allVersions.Count -gt 0) {
            $version = [string]$allVersions[-1]
        }
    }

    if (-not $version) {
        throw 'Could not determine latest Closure Compiler version from Maven metadata.'
    }

    $jarUrl = "https://repo1.maven.org/maven2/com/google/javascript/closure-compiler/$version/closure-compiler-$version.jar"
    $sha256Url = "$jarUrl.sha256"

    $expectedHash = $null
    $shaContent = (& curl.exe -sL --retry 3 $sha256Url)
    if ($LASTEXITCODE -eq 0 -and $shaContent -match '^[0-9a-fA-F]{64}') {
        $expectedHash = $Matches[0].ToUpperInvariant()
    }

    return [pscustomobject]@{
        Version      = $version
        DownloadUrl  = $jarUrl
        Sha256Url    = $sha256Url
        ExpectedHash = $expectedHash
    }
}

function Get-InstalledMinifyInfo {
    $minifyExe = Join-Path $toolsRoot 'minify\minify.exe'
    if (-not (Test-Path -LiteralPath $minifyExe -PathType Leaf)) {
        return [pscustomobject]@{
            Installed    = $false
            Version      = 'none'
            ExePath      = $null
            Sha256       = $null
        }
    }

    $version = 'unknown'
    try {
        $output = (& $minifyExe --version 2>&1)
        if ($output -match 'minify\s+v?(\d+\.\d+\.\d+)') {
            $version = $Matches[1]
        }
    } catch { }

    $hash = (Get-FileHash -LiteralPath $minifyExe -Algorithm SHA256).Hash

    return [pscustomobject]@{
        Installed    = $true
        Version      = $version
        ExePath      = $minifyExe
        Sha256       = $hash
    }
}

function Get-LatestMinifyInfo {
    $tag = $null
    $headers = & curl.exe -sI --retry 3 https://github.com/tdewolff/minify/releases/latest
    foreach ($line in ($headers -split "`r?`n")) {
        if ($line -match '^Location:\s*.+/releases/tag/v?(\d+\.\d+\.\d+)') {
            $tag = $Matches[1]
            break
        }
    }

    if (-not $tag) {
        try {
            $apiJson = & curl.exe -sL -H 'User-Agent: WoloToolUpdater' https://api.github.com/repos/tdewolff/minify/releases/latest
            $release = $apiJson | ConvertFrom-Json
            if ($release.tag_name -match 'v?(\d+\.\d+\.\d+)') {
                $tag = $Matches[1]
            }
        } catch { }
    }

    if (-not $tag) {
        throw 'Could not determine latest Minify release tag from GitHub.'
    }

    $downloadUrl = "https://github.com/tdewolff/minify/releases/download/v$tag/minify_windows_amd64.zip"

    return [pscustomobject]@{
        Version      = $tag
        DownloadUrl  = $downloadUrl
    }
}

function Update-WoloClosureCompiler {
    param([switch]$ForceRedownload, [switch]$CleanOld)

    Write-Section 'Checking Google Closure Compiler'
    $java = Get-WoloJava
    if (-not $java) {
        throw 'Java runtime (java.exe) was not found. Install Android Studio JBR or JDK before updating Closure Compiler.'
    }

    $current = Get-InstalledClosureCompilerInfo
    $latest = Get-LatestClosureCompilerInfo

    Write-Host "Current version: $($current.Version)"
    Write-Host "Latest version:  $($latest.Version)"

    $needsUpdate = $ForceRedownload -or (-not $current.Installed) -or ($current.Version -ne $latest.Version)
    if (-not $needsUpdate) {
        Write-Host "Closure Compiler is already up to date ($($current.Version))." -ForegroundColor Green
        return
    }

    $destJar = Join-Path $toolsRoot "closure-compiler-$($latest.Version).jar"
    $canonicalJar = Join-Path $toolsRoot 'closure-compiler.jar'
    $tempFile = Join-Path $toolsRoot "closure-compiler-download-$([Guid]::NewGuid().ToString('N')).tmp"

    Write-Host "Downloading Closure Compiler $($latest.Version) from $($latest.DownloadUrl)..." -ForegroundColor Yellow
    try {
        & curl.exe -fL --retry 3 -o $tempFile $latest.DownloadUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed from $($latest.DownloadUrl)"
        }

        $actualHash = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash
        if ($latest.ExpectedHash -and ($actualHash -ne $latest.ExpectedHash)) {
            throw "SHA256 mismatch for downloaded Closure Compiler: expected $($latest.ExpectedHash), got $actualHash"
        }

        Write-Host "Verifying Closure Compiler execution..."
        $testOut = Invoke-ClosureCompilerJava -JavaPath $java -ArgumentList @('-jar', $tempFile, '--version') 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Closure Compiler validation failed: $testOut"
        }

        Move-Item -LiteralPath $tempFile -Destination $destJar -Force
        Copy-Item -LiteralPath $destJar -Destination $canonicalJar -Force
        Ensure-WoloJavaClosureWrapper -ToolsRoot $toolsRoot -JavaPath $java | Out-Null

        $meta = Get-ToolchainMetadata
        $meta | Add-Member -NotePropertyName 'closureCompiler' -NotePropertyValue ([pscustomobject]@{
            version   = $latest.Version
            jar       = "closure-compiler-$($latest.Version).jar"
            sha256    = $actualHash
            updatedAt = (Get-Date).ToString('o')
        }) -Force
        Save-ToolchainMetadata -Metadata $meta

        Write-Host "Closure Compiler successfully updated to $($latest.Version) ($actualHash)" -ForegroundColor Green

        if ($CleanOld) {
            Get-ChildItem -LiteralPath $toolsRoot -Filter 'closure-compiler-*.jar' -File |
                Where-Object { $_.FullName -ne $destJar } |
                ForEach-Object {
                    Write-Host "Removing older jar: $($_.Name)" -ForegroundColor Gray
                    Remove-Item -LiteralPath $_.FullName -Force
                }
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Update-WoloMinify {
    param([switch]$ForceRedownload)

    Write-Section 'Checking tdewolff/minify'
    $current = Get-InstalledMinifyInfo
    $latest = Get-LatestMinifyInfo

    Write-Host "Current version: $($current.Version)"
    Write-Host "Latest version:  $($latest.Version)"

    $needsUpdate = $ForceRedownload -or (-not $current.Installed) -or ($current.Version -ne $latest.Version)
    if (-not $needsUpdate) {
        Write-Host "Minify is already up to date ($($current.Version))." -ForegroundColor Green
        return
    }

    $minifyDir = Join-Path $toolsRoot 'minify'
    $minifyExe = Join-Path $minifyDir 'minify.exe'
    $minifyZip = Join-Path $toolsRoot 'minify_windows_amd64.zip'
    $tempZip = Join-Path $toolsRoot "minify-download-$([Guid]::NewGuid().ToString('N')).tmp"
    $tempExtract = Join-Path $toolsRoot "minify-extract-$([Guid]::NewGuid().ToString('N'))"

    Write-Host "Downloading Minify v$($latest.Version) from $($latest.DownloadUrl)..." -ForegroundColor Yellow
    try {
        & curl.exe -fL --retry 3 -o $tempZip $latest.DownloadUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed from $($latest.DownloadUrl)"
        }

        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
        Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

        $extractedExe = Join-Path $tempExtract 'minify.exe'
        if (-not (Test-Path -LiteralPath $extractedExe -PathType Leaf)) {
            $extractedExe = (Get-ChildItem -LiteralPath $tempExtract -Filter 'minify.exe' -Recurse -File | Select-Object -First 1)?.FullName
        }
        if (-not $extractedExe) {
            throw 'Downloaded archive did not contain minify.exe.'
        }

        Write-Host "Verifying Minify execution..."
        $testOut = (& $extractedExe --version 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Minify validation failed: $testOut"
        }

        New-Item -ItemType Directory -Path $minifyDir -Force | Out-Null
        Copy-Item -LiteralPath $extractedExe -Destination $minifyExe -Force
        Copy-Item -LiteralPath $tempZip -Destination $minifyZip -Force

        $hash = (Get-FileHash -LiteralPath $minifyExe -Algorithm SHA256).Hash

        $meta = Get-ToolchainMetadata
        $meta | Add-Member -NotePropertyName 'minify' -NotePropertyValue ([pscustomobject]@{
            version   = $latest.Version
            sha256    = $hash
            updatedAt = (Get-Date).ToString('o')
        }) -Force
        Save-ToolchainMetadata -Metadata $meta

        Write-Host "Minify successfully updated to $($latest.Version) ($hash)" -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $tempZip) {
            Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempExtract) {
            Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($CheckOnly) {
    Write-Section 'Native Publishing Tools Status'
    Write-Host "Tools location: $toolsRoot"

    $closureCur = Get-InstalledClosureCompilerInfo
    $closureLat = Get-LatestClosureCompilerInfo
    $closureStatus = if (-not $closureCur.Installed) {
        'Not installed'
    } elseif ($closureCur.Version -eq $closureLat.Version) {
        'Up to date'
    } else {
        'Update available'
    }

    $minifyCur = Get-InstalledMinifyInfo
    $minifyLat = Get-LatestMinifyInfo
    $minifyStatus = if (-not $minifyCur.Installed) {
        'Not installed'
    } elseif ($minifyCur.Version -eq $minifyLat.Version) {
        'Up to date'
    } else {
        'Update available'
    }

    $report = @(
        [pscustomobject]@{
            Tool             = 'Closure Compiler'
            CurrentVersion   = $closureCur.Version
            LatestVersion    = $closureLat.Version
            Status           = $closureStatus
        },
        [pscustomobject]@{
            Tool             = 'tdewolff/minify'
            CurrentVersion   = $minifyCur.Version
            LatestVersion    = $minifyLat.Version
            Status           = $minifyStatus
        }
    )

    $report | Format-Table -AutoSize
    return
}

switch ($Tool) {
    'closure-compiler' {
        Update-WoloClosureCompiler -ForceRedownload:$Force -CleanOld:$CleanOldVersions
    }
    'minify' {
        Update-WoloMinify -ForceRedownload:$Force
    }
    'all' {
        Update-WoloClosureCompiler -ForceRedownload:$Force -CleanOld:$CleanOldVersions
        Update-WoloMinify -ForceRedownload:$Force
    }
}

Write-Section 'Toolchain Verification'
$closureFinal = Get-InstalledClosureCompilerInfo
$minifyFinal = Get-InstalledMinifyInfo
Write-Host "Closure Compiler: $($closureFinal.Version) ($($closureFinal.JarPath))" -ForegroundColor Green
Write-Host "Minify:           $($minifyFinal.Version) ($($minifyFinal.ExePath))" -ForegroundColor Green
