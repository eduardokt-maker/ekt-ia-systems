$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$webBuild = Join-Path $projectRoot "build\web"
$dist = Join-Path $projectRoot "dist"
$client = Join-Path $dist "client"
$server = Join-Path $dist "server"

if (-not (Test-Path -LiteralPath (Join-Path $webBuild "index.html"))) {
    throw "Flutter web build not found. Run flutter build web first."
}

$resolvedProject = [System.IO.Path]::GetFullPath($projectRoot)
$resolvedDist = [System.IO.Path]::GetFullPath($dist)
if (-not $resolvedDist.StartsWith($resolvedProject, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare a dist directory outside the Flutter project."
}

if (Test-Path -LiteralPath $dist) {
    Remove-Item -LiteralPath $dist -Recurse -Force
}

New-Item -ItemType Directory -Path $client, $server | Out-Null
Copy-Item -Path (Join-Path $webBuild "*") -Destination $client -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "worker.js") -Destination (Join-Path $server "index.js")
