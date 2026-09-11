Set-StrictMode -Version Latest

function ConvertTo-WoloGitBashPath {
    param([Parameter(Mandatory)] [string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        return '/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
    }
    return ($full -replace '\\', '/')
}

function Get-WoloGitBash {
    $bash = 'C:\Program Files\Git\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
        throw "Native runner needs Git bash at $bash."
    }
    return $bash
}

function Get-WoloNativeToolchain {
    param([Parameter(Mandatory)] [string]$WebsiteRoot)

    $toolsRoot = Join-Path $WebsiteRoot '.native-tools'
    $minify = Join-Path $toolsRoot 'minify\minify.exe'
    $closure = Join-Path $toolsRoot 'closure-compiler-v20250402.jar'
    $java = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
    if (-not (Test-Path -LiteralPath $java -PathType Leaf)) {
        foreach ($candidate in @(
            'C:\Program Files\Java\*\bin\java.exe',
            'C:\Program Files\Eclipse Adoptium\*\bin\java.exe',
            'C:\Program Files\Microsoft\jdk-*\bin\java.exe'
        )) {
            $hit = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { $java = $hit.FullName; break }
        }
    }
    foreach ($required in @($minify, $closure, $java)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Native publishing dependency is missing: $required. Run Install-NativePublishTools.ps1."
        }
    }
    return [pscustomobject]@{
        Minify = $minify
        Closure = $closure
        Java = $java
    }
}

function Test-WoloApacheOrigins {
    param(
        [Parameter(Mandatory)] [string]$Origin,
        [Parameter(Mandatory)] [string]$HostHeader,
        [string]$ProbePath = '/'
    )

    $uri = $Origin.TrimEnd('/') + $ProbePath
    try {
        $headers = & curl.exe -sI -H "Host: $HostHeader" $uri 2>&1
        $status = ($headers | Select-Object -First 1)
        if ($status -notmatch 'HTTP/\S+\s+200') {
            throw "Apache probe failed for $uri (Host: $HostHeader): $status. Ensure Apachehttpd is running (may need UAC) and Caddy/hosts are configured. See D:\Wolo\Web\AGENTS.md."
        }
    } catch {
        throw "Apache probe error for $uri (Host: $HostHeader): $_. Apache :8084/:8085 must be up before native Tiggu."
    }
}

function Test-WoloFrameworkCssBase {
    param([Parameter(Mandatory)] [string]$ProjectPath)

    $cssBase = Join-Path $ProjectPath 'Root\Framework\CSS\Base'
    if (-not (Test-Path -LiteralPath $cssBase -PathType Container)) {
        throw "Native bake gate: Cutie Framework CSS is missing: $cssBase. Ensure Root/Framework/CSS/Base exists with at least one .css file before running Tiggu."
    }
    $cssFiles = @(Get-ChildItem -LiteralPath $cssBase -Filter '*.css' -File -ErrorAction SilentlyContinue)
    if ($cssFiles.Count -eq 0) {
        throw "Native bake gate: Cutie Framework CSS/Base is empty (no .css files): $cssBase. PHP includeDir('../CSS/Base/') will fatal during bake."
    }
}

function Test-WoloPublicHtmlClean {
    param([Parameter(Mandatory)] [string]$PublicDir)

    if (-not (Test-Path -LiteralPath $PublicDir -PathType Container)) {
        throw "Native bake gate: Tiggu public output is missing: $PublicDir"
    }

    # Catch PHP fatals/warnings baked into HTML (e.g. missing Framework/CSS/Base after a path move).
    $patterns = @(
        @{ Label = 'PHP fatal error'; Regex = '(?i)fatal\s+error' },
        @{ Label = 'PHP uncaught exception'; Regex = '(?i)uncaught' },
        @{ Label = 'PHP scandir failure'; Regex = '(?i)scandir\s*\(' },
        @{ Label = 'failed to open directory'; Regex = '(?i)failed to open directory' },
        @{ Label = 'PHP HTML error line marker'; Regex = '(?i)on line <b>' },
        @{ Label = 'Windows path leak (D:\Wolo)'; Regex = '(?i)D:\\Wolo\\' },
        @{ Label = 'Windows path leak (E:\Web)'; Regex = '(?i)E:\\Web\\' }
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $PublicDir -Filter '*.html' -File -Recurse | ForEach-Object {
        $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
        foreach ($pattern in $patterns) {
            if ($content -match $pattern.Regex) {
                $violations.Add("$($_.FullName): $($pattern.Label)")
            }
        }
    }

    if ($violations.Count -gt 0) {
        $detail = ($violations | Select-Object -Unique) -join '; '
        throw "Native bake gate: PHP error leakage detected in public HTML ($detail). Fix the bake before copying to web-public."
    }
}

function Ensure-WoloTigguUrlDirs {
    param([Parameter(Mandatory)] [string]$ProjectPath)

    $interim = Join-Path $ProjectPath 'interim'
    $urlTsv = @(
        (Join-Path $ProjectPath 'Config\URL.tsv'),
        (Join-Path $ProjectPath 'Config\Url.tsv'),
        (Join-Path $ProjectPath 'config\URL.tsv')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $urlTsv) { return }

    Get-Content -LiteralPath $urlTsv | Select-Object -Skip 1 | ForEach-Object {
        $line = $_
        if (-not $line -or $line.StartsWith('#')) { return }
        $cols = $line -split "`t"
        if ($cols.Count -lt 2) { return }
        $path = $cols[0].Trim()
        $name = $cols[1].Trim()
        $ext = if ($cols.Count -ge 3) { $cols[2].Trim() } else { '' }
        if (-not $name) { return }
        $rel = if ($path) { ($path.TrimEnd('/') + '/' + $name).Replace('\', '/') } else { $name }
        if ($ext) { $rel = "$rel.$ext" }
        $full = Join-Path $interim (($rel -replace '/', [IO.Path]::DirectorySeparatorChar))
        $dir = [IO.Path]::GetDirectoryName($full)
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}
function Invoke-WoloNativeTiggu {
    param(
        [Parameter(Mandatory)] [ValidateSet('site', 'app')] [string]$Kind,
        [string]$WebsiteRoot = 'D:\Wolo\Web',
        [string]$ProjectPath,
        [string]$Origin,
        [string]$HostHeader = 'wolo.local',
        [switch]$SkipScriptVersioning,
        [switch]$SkipApacheProbe
    )

    if (-not $ProjectPath) {
        $ProjectPath = Join-Path $WebsiteRoot "$Kind\project"
    }
    if (-not $Origin) {
        $Origin = if ($Kind -eq 'site') { 'http://127.0.0.1:8084' } else { 'http://127.0.0.1:8085' }
    }

    $bash = Get-WoloGitBash
    $tiggu = Join-Path $WebsiteRoot 'tiggu\build.sh'
    if (-not (Test-Path -LiteralPath $tiggu -PathType Leaf)) {
        throw "Native runner needs Tiggu at $tiggu."
    }
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        throw "Native renderer project does not exist: $ProjectPath"
    }

    # Pre-bake: refuse to snapshot when Cutie Framework CSS/Base is missing (PHP includeDir fatals).
    Test-WoloFrameworkCssBase -ProjectPath $ProjectPath

    if (-not $SkipApacheProbe) {
        $probePath = if ($Kind -eq 'site') { '/about' } else { '/' }
        Test-WoloApacheOrigins -Origin $Origin -HostHeader $HostHeader -ProbePath $probePath
    }

    if ($Kind -eq 'site') {
        Invoke-WoloSriGate -WebsiteRoot $WebsiteRoot `
            -SentryConfig (Join-Path $ProjectPath 'Root\Config\Vars.tsv') `
            -SentrySrc (Join-Path $ProjectPath 'Root\Framework\JS\Fragment\Sentry_version.php')
    }

    Ensure-WoloTigguUrlDirs -ProjectPath $ProjectPath

    $tigguUnix = ConvertTo-WoloGitBashPath -Path $tiggu
    $projectUnix = ConvertTo-WoloGitBashPath -Path $ProjectPath
    $toolchain = Get-WoloNativeToolchain -WebsiteRoot $WebsiteRoot
    $minifyUnix = ConvertTo-WoloGitBashPath -Path $toolchain.Minify
    $closureUnix = ConvertTo-WoloGitBashPath -Path $toolchain.Closure
    $javaUnix = ConvertTo-WoloGitBashPath -Path $toolchain.Java
    $pythonPath = (Get-Command python -ErrorAction Stop).Source
    $pythonUnix = ConvertTo-WoloGitBashPath -Path $pythonPath
    # Do not inherit Windows PATH: a curl-based wget shim in ~/bin returns HTTP 404
    # for Tiggu downloads (Host header + origin). Use Git's curl instead.
    $command = 'export PATH=/usr/bin:/mingw64/bin:/bin; ' +
        'export TIGGU_ORIGIN="' + $Origin + '"; ' +
        'export TIGGU_HOST_HEADER="' + $HostHeader + '"; ' +
        $(if ($SkipScriptVersioning) { 'export TIGGU_SKIP_SCRIPT_VERSIONING=1; ' } else { '' }) +
        'export TIGGU_MINIFY="' + $minifyUnix + '"; ' +
        'export TIGGU_CLOSURE_JAR="' + $closureUnix + '"; ' +
        'export TIGGU_JAVA="' + $javaUnix + '"; ' +
        'export TIGGU_NATIVE_PYTHON="' + $pythonUnix + '"; ' +
        '"' + $tigguUnix + '" "' + $projectUnix + '"'
    Push-Location $WebsiteRoot
    try {
        & $bash --noprofile --norc -c $command
        if ($LASTEXITCODE -ne 0) {
            throw "Native Tiggu ($Kind) failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    # Post-bake: refuse publishable public/ when PHP errors were baked into HTML.
    Test-WoloPublicHtmlClean -PublicDir (Join-Path $ProjectPath 'public')

    Invoke-WoloSriGate -WebsiteRoot $WebsiteRoot -Dir (Join-Path $ProjectPath 'public')
}

function Invoke-WoloSriGate {
    param(
        [Parameter(Mandatory)] [string]$WebsiteRoot,
        [string]$Dir,
        [string]$SentryConfig,
        [string]$SentrySrc
    )

    $script = Join-Path $WebsiteRoot 'project\build\scripts\verify-sri.mjs'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw "SRI gate script is missing: $script"
    }
    $node = (Get-Command node -ErrorAction Stop).Source
    $argList = @($script)
    if ($Dir) { $argList += @('--dir', $Dir) }
    if ($SentryConfig) { $argList += @('--sentry-config', $SentryConfig) }
    if ($SentrySrc) { $argList += @('--sentry-src', $SentrySrc) }
    Write-Host "SRI gate: $($argList -join ' ')" -ForegroundColor Cyan
    & $node @argList
    if ($LASTEXITCODE -ne 0) {
        throw "SRI gate failed with exit code $LASTEXITCODE. CDN integrity hashes must match the bytes currently served."
    }
}
