<#
.SYNOPSIS
    Rasterize docs/architecture.svg to docs/architecture.png using headless Microsoft Edge.

.DESCRIPTION
    The README embeds a PNG (renders reliably on GitHub regardless of fonts). Run this after you
    edit docs/architecture.svg - or after re-exporting an SVG from docs/architecture.excalidraw
    (excalidraw.com -> Export -> SVG) - to refresh docs/architecture.png so the two stay in sync.

    Requires Microsoft Edge (preinstalled on Windows); no Node/ImageMagick needed.

.EXAMPLE
    ./tools/render-diagram.ps1
#>
[CmdletBinding()]
param(
    [string]$Svg,
    [string]$Png,
    [int]$Width  = 1600,
    [int]$Height = 900,
    [int]$Scale  = 2
)

$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { (Get-Location).Path }
if (-not $Svg) { $Svg = Join-Path $root 'docs\architecture.svg' }
if (-not $Png) { $Png = Join-Path $root 'docs\architecture.png' }
if (-not (Test-Path $Svg)) { throw "SVG not found: $Svg" }
$Svg  = (Resolve-Path $Svg).Path
$docs = Split-Path $Svg -Parent

$edge = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "Microsoft Edge not found - it is used as the headless SVG rasterizer." }

# Exact-size HTML wrapper so the screenshot has no margins.
$wrap    = Join-Path $docs '_render.html'
$svgName = Split-Path $Svg -Leaf
@"
<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:#fff}img{display:block;width:${Width}px;height:${Height}px}</style>
</head><body><img src="$svgName"></body></html>
"@ | Set-Content -Path $wrap -Encoding utf8

try {
    if (Test-Path $Png) { Remove-Item $Png -Force }
    $uri = ([System.Uri]$wrap).AbsoluteUri
    & $edge --headless=new --disable-gpu --hide-scrollbars "--force-device-scale-factor=$Scale" `
        "--window-size=$Width,$Height" "--screenshot=$Png" $uri | Out-Null
    for ($i = 0; $i -lt 20 -and -not (Test-Path $Png); $i++) { Start-Sleep -Milliseconds 300 }
    if (-not (Test-Path $Png)) { throw "Edge did not produce $Png" }
    Write-Host ("Wrote {0} ({1:N0} bytes)" -f $Png, (Get-Item $Png).Length)
}
finally {
    if (Test-Path $wrap) { Remove-Item $wrap -Force }
}
