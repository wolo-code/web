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
            throw "Apache probe failed for $uri (Host: $HostHeader): $status. Ensure Apachehttpd is running (may need UAC) and Caddy/hosts are configured. See E:\AGENTS.md."
        }
    } catch {
        throw "Apache probe error for $uri (Host: $HostHeader): $_. Apache :8084/:8085 must be up before native Tiggu."
    }
}


function Ensure-WoloTigguUrlDirs {
	param([Parameter(Mandatory=$true)][string]$ProjectPath)
	$interim = Join-Path $ProjectPath 'interim'
	$urlTsv = @(
		(Join-Path $ProjectPath 'Config\URL.tsv'),
		(Join-Path $ProjectPath 'Config\Url.tsv'),
		(Join-Path $ProjectPath 'config\URL.tsv')
	) | Where-Object { Test-Path Set-StrictMode -Version Latest

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
            throw "Apache probe failed for $uri (Host: $HostHeader): $status. Ensure Apachehttpd is running (may need UAC) and Caddy/hosts are configured. See E:\AGENTS.md."
        }
    } catch {
        throw "Apache probe error for $uri (Host: $HostHeader): $_. Apache :8084/:8085 must be up before native Tiggu."
    }
}

function Invoke-WoloNativeTiggu {
    param(
        [Parameter(Mandatory)] [ValidateSet('site', 'app')] [string]$Kind,
        [string]$WebsiteRoot = 'E:\Web',
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

    if (-not $SkipApacheProbe) {
        $probePath = if ($Kind -eq 'site') { '/about' } else { '/' }
        Test-WoloApacheOrigins -Origin $Origin -HostHeader $HostHeader -ProbePath $probePath
    }

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
}
 } | Select-Object -First 1
	if (-not $urlTsv) { return }
	Get-Content -LiteralPath $urlTsv | Select-Object -Skip 1 | ForEach-Object {
		if (-not Set-StrictMode -Version Latest

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
            throw "Apache probe failed for $uri (Host: $HostHeader): $status. Ensure Apachehttpd is running (may need UAC) and Caddy/hosts are configured. See E:\AGENTS.md."
        }
    } catch {
        throw "Apache probe error for $uri (Host: $HostHeader): $_. Apache :8084/:8085 must be up before native Tiggu."
    }
}

function Invoke-WoloNativeTiggu {
    param(
        [Parameter(Mandatory)] [ValidateSet('site', 'app')] [string]$Kind,
        [string]$WebsiteRoot = 'E:\Web',
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

    if (-not $SkipApacheProbe) {
        $probePath = if ($Kind -eq 'site') { '/about' } else { '/' }
        Test-WoloApacheOrigins -Origin $Origin -HostHeader $HostHeader -ProbePath $probePath
    }

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
}
 -or Set-StrictMode -Version Latest

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
            throw "Apache probe failed for $uri (Host: $HostHeader): $status. Ensure Apachehttpd is running (may need UAC) and Caddy/hosts are configured. See E:\AGENTS.md."
        }
    } catch {
        throw "Apache probe error for $uri (Host: $HostHeader): $_. Apache :8084/:8085 must be up before native Tiggu."
    }
}

function Invoke-WoloNativeTiggu {
    param(
        [Parameter(Mandatory)] [ValidateSet('site', 'app')] [string]$Kind,
        [string]$WebsiteRoot = 'E:\Web',
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

    if (-not $SkipApacheProbe) {
        $probePath = if ($Kind -eq 'site') { '/about' } else { '/' }
        Test-WoloApacheOrigins -Origin $Origin -HostHeader $HostHeader -ProbePath $probePath
    }

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
}
.StartsWith('#')) { return }
		$cols = Set-StrictMode -Version Latest

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
            throw "Apache probe failed for $uri (Host: $HostHeader): $status. Ensure Apachehttpd is running (may need UAC) and Caddy/hosts are configured. See E:\AGENTS.md."
        }
    } catch {
        throw "Apache probe error for $uri (Host: $HostHeader): $_. Apache :8084/:8085 must be up before native Tiggu."
    }
}

function Invoke-WoloNativeTiggu {
    param(
        [Parameter(Mandatory)] [ValidateSet('site', 'app')] [string]$Kind,
        [string]$WebsiteRoot = 'E:\Web',
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

    if (-not $SkipApacheProbe) {
        $probePath = if ($Kind -eq 'site') { '/about' } else { '/' }
        Test-WoloApacheOrigins -Origin $Origin -HostHeader $HostHeader -ProbePath $probePath
    }

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
}
 -split "`t"
		if ($cols.Count -lt 3) { return }
		$path = $cols[0].Trim()
		$name = $cols[1].Trim()
		$ext = $cols[2].Trim()
		if (-not $name) { return }
		$rel = if ($path) { "$path$name" } else { $name }
		if ($ext) { $rel = "$rel.$ext" }
		$dir = Split-Path -Parent (Join-Path $interim ($rel -replace '/', '\'))
		if ($dir -and $dir -ne $interim) {
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
		}
	}
}
function Invoke-WoloNativeTiggu {
    param(
        [Parameter(Mandatory)] [ValidateSet('site', 'app')] [string]$Kind,
        [string]$WebsiteRoot = 'E:\Web',
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

    if (-not $SkipApacheProbe) {
        $probePath = if ($Kind -eq 'site') { '/about' } else { '/' }
        Test-WoloApacheOrigins -Origin $Origin -HostHeader $HostHeader -ProbePath $probePath
    }

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
}
