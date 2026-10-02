[CmdletBinding()]
param(
    [string]$WebsiteRoot = 'D:\Wolo\Web'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $WebsiteRoot -or -not (Test-Path -LiteralPath $WebsiteRoot)) {
    $parentDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (Test-Path -LiteralPath (Join-Path $parentDir '.native-tools')) {
        $WebsiteRoot = $parentDir
    } else {
        $WebsiteRoot = 'D:\Wolo\Web'
    }
}

$minifyVersion = '2.24.17'
$minifyHash = 'A854E283026752C34CF0C69FE574854526ADDA50721244285C53CF0C195F23B0'
$closureVersion = 'v20250402'
$closureHash = '6FCBD20F75994EDC6856E336BC0147CE3DD7110C6B3A132E93EDF580673C72BB'
$toolsRoot = Join-Path ([System.IO.Path]::GetFullPath($WebsiteRoot)) '.native-tools'
$minifyZip = Join-Path $toolsRoot 'minify_windows_amd64.zip'
$minifyDirectory = Join-Path $toolsRoot 'minify'
$minifyExe = Join-Path $minifyDirectory 'minify.exe'
$closureJar = Join-Path $toolsRoot "closure-compiler-$closureVersion.jar"
$canonicalClosureJar = Join-Path $toolsRoot 'closure-compiler.jar'

New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null

function Get-PinnedDownload {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [string]$Destination,
        [Parameter(Mandatory)] [string]$Sha256
    )

    if (
        (Test-Path -LiteralPath $Destination -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $Sha256
    ) {
        return
    }
    & curl.exe -fL --retry 3 -o $Destination $Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $Url"
    }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actual -ne $Sha256) {
        throw "SHA-256 mismatch for '$Destination': expected $Sha256, got $actual"
    }
}

Get-PinnedDownload `
    -Url "https://github.com/tdewolff/minify/releases/download/v$minifyVersion/minify_windows_amd64.zip" `
    -Destination $minifyZip `
    -Sha256 $minifyHash
if (-not (Test-Path -LiteralPath $minifyExe -PathType Leaf)) {
    New-Item -ItemType Directory -Path $minifyDirectory -Force | Out-Null
    Expand-Archive -LiteralPath $minifyZip -DestinationPath $minifyDirectory -Force
}

Get-PinnedDownload `
    -Url "https://repo1.maven.org/maven2/com/google/javascript/closure-compiler/$closureVersion/closure-compiler-$closureVersion.jar" `
    -Destination $closureJar `
    -Sha256 $closureHash

Copy-Item -LiteralPath $closureJar -Destination $canonicalClosureJar -Force

$toolchainJsonPath = Join-Path $toolsRoot 'toolchain.json'
if (-not (Test-Path -LiteralPath $toolchainJsonPath -PathType Leaf)) {
    $meta = [pscustomobject]@{
        closureCompiler = [pscustomobject]@{
            version   = $closureVersion
            jar       = "closure-compiler-$closureVersion.jar"
            sha256    = $closureHash
            updatedAt = (Get-Date).ToString('o')
        }
        minify = [pscustomobject]@{
            version   = $minifyVersion
            sha256    = $minifyHash
            updatedAt = (Get-Date).ToString('o')
        }
    }
    [System.IO.File]::WriteAllText($toolchainJsonPath, ($meta | ConvertTo-Json -Depth 4), [System.Text.Encoding]::UTF8)
}

# Preferred Java for Closure Compiler (same pin as ujnotes). Document fallbacks if missing.
$preferredJava = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
if (Test-Path -LiteralPath $preferredJava -PathType Leaf) {
    Write-Host "Java OK: $preferredJava" -ForegroundColor Green
} else {
    $fallback = $null
    foreach ($candidate in @(
        'C:\Program Files\Java\*\bin\java.exe',
        'C:\Program Files\Eclipse Adoptium\*\bin\java.exe',
        'C:\Program Files\Microsoft\jdk-*\bin\java.exe'
    )) {
        $hit = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $fallback = $hit.FullName; break }
    }
    if ($fallback) {
        Write-Host "Preferred Android Studio JBR missing. PublishRunner will need Java at: $fallback" -ForegroundColor Yellow
        Write-Host "Update Get-WoloNativeToolchain Java path in PublishRunner.ps1 if needed." -ForegroundColor Yellow
    } else {
        Write-Host "WARNING: No JRE/JDK found. Install Android Studio JBR or a JDK; Closure Compiler needs java.exe." -ForegroundColor Red
    }
}

Write-Host "Native publishing tools are ready in $toolsRoot" -ForegroundColor Green
