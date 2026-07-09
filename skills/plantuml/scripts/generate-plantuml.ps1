<#
.SYNOPSIS
    Convert PlantUML source to SVG, PNG, PDF, or ASCII art on Windows (PowerShell).

.DESCRIPTION
    Mirror of generate-plantuml.sh for native Windows PowerShell users.

    PRIVACY NOTICE
    --------------
    This script renders diagrams LOCALLY by default. The PlantUML source is
    NOT transmitted off-host unless you explicitly pass -UsePublicServer.

    Backend priority (local-first):
      1. Docker (plantuml/plantuml image)        — preferred, fully local
      2. Local plantuml.jar                       — offline fallback (Java required)
      3. Kroki public server (kroki.io)          — OPT-IN ONLY (-UsePublicServer)
                                                   Uploads diagram source to a third
                                                   party operated by Yuzu Tech (EU).
                                                   Kroki is open source and self-
                                                   hostable — set
                                                   $env:PLANTUML_PUBLIC_SERVER to
                                                   point at your own instance.
                                                   Avoid the default public host
                                                   for confidential architecture,
                                                   credentials, or proprietary
                                                   business processes.

    Note: the legacy https://www.plantuml.com/plantuml POST endpoint now sits
    behind a Cloudflare + Ezoic consent wall that returns HTTP 302 to a
    JavaScript-only HTML page, breaking automated rendering. Kroki replaces
    it as the default opt-in public backend in v1.4.1.

    Supports CJK (Chinese/Japanese/Korean) font rendering via -Cjk flag,
    and automatic aspect ratio correction for excessively wide or tall diagrams.

.PARAMETER InputPath
    Path to the .puml source file.

.PARAMETER OutputDir
    Output directory. Defaults to .\output.

.PARAMETER Format
    Output format: svg (default), png, pdf, or txt.

.PARAMETER Cjk
    Enable CJK font support. Mounts host font directories into Docker,
    replaces Helvetica with a CJK-compatible font.

.PARAMETER NoFix
    Disable automatic aspect ratio correction. By default, diagrams wider or
    taller than the threshold are automatically corrected and re-rendered.

.PARAMETER MinAspect
    Minimum allowed width/height ratio before correction (default: 0.7).

.PARAMETER MaxAspect
    Maximum allowed width/height ratio before correction (default: 1.4).

.PARAMETER DarkMode
    Also emit a dark companion image named <basename>.dark.<fmt>.
    Supported for svg and png (png requires ImageMagick convert).

.PARAMETER NoA4Check
    Disable automatic A4 paper fit validation. The A4 check ensures the
    rendered diagram fits within either portrait (794×1123 px @ 96 DPI) or
    landscape (1123×794 px) A4 dimensions and that the rendered font remains
    legible when printed. ON by default.

.PARAMETER MinFontPt
    Minimum legible font size on A4 paper, in pt (default: 8.0). Used only
    when the A4 check is enabled.

.PARAMETER UsePublicServer
    OPT-IN: render via the Kroki public server (kroki.io by default).
    WARNING: this uploads the diagram source to a third-party service.
    Override the host via $env:PLANTUML_PUBLIC_SERVER = '<url>' to point at
    a self-hosted Kroki instance. Off by default — local Docker / JAR
    backends are used instead.

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -Format svg

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -Cjk -Format png

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -MaxAspect 1.5 -MinAspect 0.6

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -Format svg -DarkMode

.EXAMPLE
    # Opt in to remote rendering (uploads diagram to kroki.io)
    .\generate-plantuml.ps1 diagram.puml .\out -UsePublicServer

.EXAMPLE
    # Opt in to a self-hosted Kroki instance
    $env:PLANTUML_PUBLIC_SERVER = 'https://kroki.internal.example.com'
    .\generate-plantuml.ps1 diagram.puml .\out -UsePublicServer
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias("Input")]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutputDir = ".\output",

    [ValidateSet("svg", "png", "pdf", "txt")]
    [string]$Format = "svg",

    [Parameter()]
    [switch]$Cjk,

    [Parameter()]
    [switch]$NoFix,

    [Parameter()]
    [float]$MinAspect = 0.7,

    [Parameter()]
    [float]$MaxAspect = 1.4,

    [Parameter()]
    [switch]$NoA4Check,

    [Parameter()]
    [float]$MinFontPt = 8.0,

    [Parameter()]
    [switch]$DarkMode,

    [Parameter()]
    [switch]$UsePublicServer
)

# A4 paper in CSS pixels at 96 DPI (1 in = 96px, A4 = 210×297 mm ⇒ 8.27×11.69 in)
$script:a4PortraitW = 794
$script:a4PortraitH = 1123
$script:a4LandscapeW = 1123
$script:a4LandscapeH = 794

# Body font px set by the mandatory uml-diagrams.org preamble (defaultFontSize 12)
$script:defaultFontPx = 12.0

# Caller-visible flag set by Test-A4Fit / consumed by Fix-A4Fit
$script:a4ScaleFactor = 1.0

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    Write-Error "Input file not found: $InputPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
$outputFile = Join-Path $OutputDir "$baseName.$Format"

# Script-level dimension variables (populated by Get-SvgDimensions / Get-PngDimensions)
$script:svgWidth = $null
$script:svgHeight = $null
$script:pngWidth = $null
$script:pngHeight = $null

# ═══════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-BinaryOk {
    param([string]$Path, [string]$Fmt)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $fi = Get-Item -LiteralPath $Path
    if ($fi.Length -le 0) { return $false }
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $buf = New-Object byte[] 4
        $n = $stream.Read($buf, 0, 4)
        $stream.Close()
        if ($n -lt 4) { return $false }
        $hex = ($buf | ForEach-Object { $_.ToString("x2") }) -join ""
        switch ($Fmt) {
            "png" { return $hex -eq "89504e47" }
            "pdf" { return $hex -eq "25504446" }
            default { return $true }
        }
    } catch {
        return $false
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Source Sanitization (defensive)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Strip `skinparam style strictuml` from the source before dispatching to the
# backend. `strictuml` degrades key UML shapes (actors → text, use cases →
# rectangles, class header separator lost). All OTHER skinparam lines are
# preserved untouched. Emits a single stderr log line the first time it
# removes a match.
function Sanitize-PumlSource {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $pattern = '^\s*skinparam\s+style\s+strictuml\s*$'
    $matched = $lines | Where-Object { $_ -match $pattern }
    if ($matched) {
        [Console]::Error.WriteLine("  i Stripped forbidden 'skinparam style strictuml' (see SKILL.md -> Common Failure Patterns)")
        $filtered = $lines | Where-Object { $_ -notmatch $pattern }
        Set-Content -LiteralPath $Path -Value $filtered -Encoding UTF8
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# CJK Font Detection & Configuration
# ═══════════════════════════════════════════════════════════════════════════════

function Detect-Cjk {
    param([string]$Path)
    try {
        $content = [System.IO.File]::ReadAllText(
            (Resolve-Path -LiteralPath $Path),
            [System.Text.Encoding]::UTF8
        )
        foreach ($c in $content.ToCharArray()) {
            $cp = [int]$c
            if (($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or
                ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
                ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
                ($cp -ge 0x3040 -and $cp -le 0x30FF) -or
                ($cp -ge 0xAC00 -and $cp -le 0xD7AF) -or
                ($cp -ge 0x3000 -and $cp -le 0x303F) -or
                ($cp -ge 0xFF00 -and $cp -le 0xFFEF)) {
                return $true
            }
        }
    } catch {
        # fall through
    }
    return $false
}

function Prepare-PumlForCjk {
    param([string]$SrcPath)
    $dstPath = "$SrcPath.cjk.puml"
    $content = Get-Content -LiteralPath $SrcPath -Encoding UTF8 -Raw

    $content = $content -replace 'skinparam defaultFontName Helvetica',
        'skinparam defaultFontName "WenQuanYi Micro Hei"'

    if ($content -notmatch 'defaultFontName') {
        $content = $content -replace '@startuml',
            '@startuml' + "`n" + '!pragma defaultFontName "WenQuanYi Micro Hei"' + "`n" +
            'skinparam defaultFontName "WenQuanYi Micro Hei"'
    }

    Set-Content -LiteralPath $dstPath -Value $content -Encoding UTF8 -NoNewline
    return $dstPath
}

# ═══════════════════════════════════════════════════════════════════════════════
# Aspect Ratio Validation & Auto-Fix
# ═══════════════════════════════════════════════════════════════════════════════

function Get-SvgDimensions {
    param([string]$SvgPath)
    if (-not (Test-Path -LiteralPath $SvgPath)) { return $false }
    $firstLines = Get-Content -LiteralPath $SvgPath -TotalCount 5 -Encoding UTF8 -Raw
    if ($firstLines -match 'viewBox="(\S+)\s+(\S+)\s+(\S+)\s+(\S+)"') {
        $script:svgWidth  = [int][double]$Matches[3]
        $script:svgHeight = [int][double]$Matches[4]
        return ($script:svgWidth -gt 0 -and $script:svgHeight -gt 0)
    }
    return $false
}

function Get-PngDimensions {
    param([string]$PngPath)
    # Primary: use .NET System.Drawing (available on Windows)
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $PngPath))
        $script:pngWidth  = $img.Width
        $script:pngHeight = $img.Height
        $img.Dispose()
        return ($script:pngWidth -gt 0 -and $script:pngHeight -gt 0)
    } catch {
        # Fallback: try ImageMagick identify
        if (Test-Command "identify") {
            try {
                $dims = & identify -format "%w %h" $PngPath 2>$null
                if ($dims -match '^(\d+)\s+(\d+)$') {
                    $script:pngWidth  = [int]$Matches[1]
                    $script:pngHeight = [int]$Matches[2]
                    return $true
                }
            } catch { }
        }
    }
    return $false
}

function Test-AspectRatio {
    param([string]$ImgPath, [string]$Fmt)
    $w = $null; $h = $null
    switch ($Fmt) {
        "svg" {
            if (-not (Get-SvgDimensions $ImgPath)) { return $null }
            $w = $script:svgWidth; $h = $script:svgHeight
        }
        "png" {
            if (-not (Get-PngDimensions $ImgPath)) { return $null }
            $w = $script:pngWidth; $h = $script:pngHeight
        }
        default { return $null }
    }
    if (-not $w -or -not $h -or $w -le 0 -or $h -le 0) { return $null }

    $ratio = [math]::Round($w / $h, 2)
    Write-Host "  📐 Dimensions: ${w}x${h}, width/height: ${ratio} (band: ${MinAspect}-${MaxAspect})"
    if ($ratio -lt $MinAspect) { return "too_tall" }
    if ($ratio -gt $MaxAspect) { return "too_wide" }
    return "ok"
}

function Get-DiagramType {
    param([string]$PumlPath)
    $content = Get-Content -LiteralPath $PumlPath -Encoding UTF8 -Raw
    if ($content -match '(?im)^\s*(start\s*\r?\n|:[^\r\n]+;|if\s*\()') { return "activity" }
    if ($content -match '(?im)^\s*state\s+') { return "state" }
    if ($content -match '(?im)^\s*(participant|actor|->|--)\s+') { return "sequence" }
    return "other"
}

function Fix-PumlAspectRatio {
    param([string]$PumlPath, [string]$Problem)

    Write-Host "  → Attempting to fix aspect ratio (${Problem})..."
    $content = Get-Content -LiteralPath $PumlPath -Encoding UTF8 -Raw

    if ($content -match '!pragma aspectRatioFixed') {
        Write-Host "  → Already auto-fixed; skipping further attempts"
        return $null
    }

    $tmpPath = "${PumlPath}.fixed.puml"

    $lines = $content -split "`r?`n"
    $pragmaLine = "!pragma aspectRatioFixed"
    $spacingBlock = @(
        "<style>",
        "root {",
        "  padding 8",
        "  wrapWidth 220",
        "}",
        "activityDiagram {",
        "  activity { padding 8 }",
        "}",
        "sequenceDiagram {",
        "  participant { padding 8 }",
        "  box { padding 8 }",
        "}",
        "classDiagram {",
        "  class { padding 8; MinimumWidth 100 }",
        "}",
        "stateDiagram {",
        "  state { padding 8 }",
        "}",
        "</style>",
        "skinparam NodeSep 35",
        "skinparam RankSep 35"
    )

    $hasPragma = $false
    $outLines = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^!pragma aspectRatioFixed') { $hasPragma = $true }
        $outLines.Add($line)
        if ($line -match '^@startuml') {
            $outLines.Add($pragmaLine)
            foreach ($sl in $spacingBlock) {
                if ($content -notmatch [regex]::Escape($sl)) {
                    $outLines.Add($sl)
                }
            }
        }
    }

    $content = $outLines -join "`n"

    $diagramType = Get-DiagramType $PumlPath
    $directionSafe = $diagramType -notin @("activity", "sequence", "state")

    if ($directionSafe -and $Problem -eq "too_tall") {
        if ($content -match "top to bottom direction") {
            $content = $content -replace "(?m)^top to bottom direction\r?\n", ""
        }
        if ($content -notmatch "left to right direction") {
            $content = $content -replace '(?m)^@enduml\s*$', "left to right direction`n@enduml"
        }
        Write-Host "  → Applied: left to right direction"
    } elseif ($directionSafe -and $Problem -eq "too_wide") {
        if ($content -match "left to right direction") {
            $content = $content -replace "(?m)^left to right direction\r?\n", ""
        }
        if ($content -notmatch "top to bottom direction") {
            $content = $content -replace '(?m)^@enduml\s*$', "top to bottom direction`n@enduml"
        }
        Write-Host "  → Applied: top to bottom direction"
    } else {
        Write-Host "  → Direction change skipped for ${diagramType} diagram; using spacing guards only"
    }

    Set-Content -LiteralPath $tmpPath -Value $content -Encoding UTF8 -NoNewline
    return $tmpPath
}

# ═══════════════════════════════════════════════════════════════════════════════
# A4 Paper Fit Validation & Auto-Scale Fix
#
# Same algorithm as generate-plantuml.sh:
#   * Compare rendered SVG/PNG dimensions against A4 portrait (794×1123) and
#     landscape (1123×794) boxes at 96 DPI.
#   * Accept if EITHER orientation fits.
#   * Otherwise compute scale = max(portrait_factor, landscape_factor), clamp
#     to [0.15, 1.0], inject a PlantUML "scale N" directive and re-render.
#   * After re-rendering warn if effective on-paper font (scale × 12px × 0.75)
#     falls below -MinFontPt.
# ═══════════════════════════════════════════════════════════════════════════════

function Test-A4Fit {
    param([string]$ImgPath, [string]$Fmt)
    $w = $null; $h = $null
    switch ($Fmt) {
        "svg" {
            if (-not (Get-SvgDimensions $ImgPath)) { return $null }
            $w = $script:svgWidth;   $h = $script:svgHeight
        }
        "png" {
            if (-not (Get-PngDimensions $ImgPath)) { return $null }
            $w = $script:pngWidth;   $h = $script:pngHeight
        }
        default { return $null }
    }
    if (-not $w -or -not $h -or $w -le 0 -or $h -le 0) { return $null }

    $script:a4ScaleFactor = 1.0

    $fitsPortrait  = ($w -le $script:a4PortraitW  -and $h -le $script:a4PortraitH)
    $fitsLandscape = ($w -le $script:a4LandscapeW -and $h -le $script:a4LandscapeH)

    if ($fitsPortrait -or $fitsLandscape) {
        Write-Host "  📄 A4 fit: ${w}x${h}px fits A4 portrait ($($script:a4PortraitW)x$($script:a4PortraitH)) or landscape ($($script:a4LandscapeW)x$($script:a4LandscapeH)) ✓"
        return $true
    }

    $sp = [math]::Min(($script:a4PortraitW  / $w), ($script:a4PortraitH  / $h))
    $sl = [math]::Min(($script:a4LandscapeW / $w), ($script:a4LandscapeH / $h))
    $factor = [math]::Max($sp, $sl)
    if ($factor -lt 0.15) { $factor = 0.15 }
    $script:a4ScaleFactor = [math]::Round($factor, 3)

    Write-Host "  📄 A4 fit: ${w}x${h}px exceeds A4 portrait ($($script:a4PortraitW)x$($script:a4PortraitH)) and landscape ($($script:a4LandscapeW)x$($script:a4LandscapeH))"
    Write-Host "     Required scale to fit: $($script:a4ScaleFactor) (portrait factor $([math]::Round($sp,3)), landscape factor $([math]::Round($sl,3)))"
    return $false
}

function Fix-A4Fit {
    param([string]$PumlPath)

    if (-not $script:a4ScaleFactor -or $script:a4ScaleFactor -eq 1.0) {
        return $null
    }
    $content = Get-Content -LiteralPath $PumlPath -Encoding UTF8 -Raw
    if ($content -match '!pragma a4FitFixed') { return $null }

    $tmpPath = "${PumlPath}.a4fixed.puml"
    $content = $content -replace '^@startuml', "@startuml`n!pragma a4FitFixed"

    $content = $content -replace '(?m)^scale [0-9.]+\r?\n', ''
    $content = $content -replace '!pragma a4FitFixed', "!pragma a4FitFixed`nscale $($script:a4ScaleFactor)"
    Write-Host "  → Applied: scale $($script:a4ScaleFactor) (A4 fit)"

    $effectivePt = [math]::Round($script:a4ScaleFactor * $script:defaultFontPx * 0.75, 1)
    if ($effectivePt -lt $MinFontPt) {
        Write-Host "  ⚠ After scaling to $($script:a4ScaleFactor), estimated font ≈ ${effectivePt}pt on A4"
        Write-Host "    That is below -MinFontPt $MinFontPt and may be hard to read in print."
        Write-Host "    Consider splitting into multiple diagrams or abbreviating labels."
    } else {
        Write-Host "     Estimated font ≈ ${effectivePt}pt on A4 (≥ min ${MinFontPt}pt) ✓"
    }

    Set-Content -LiteralPath $tmpPath -Value $content -Encoding UTF8 -NoNewline
    return $tmpPath
}

# ═══════════════════════════════════════════════════════════════════════════════
# Dark-mode post-processing
# ═══════════════════════════════════════════════════════════════════════════════

function New-BareStrokesSvg {
    param([string]$SvgPath)
    if (-not (Test-Path -LiteralPath $SvgPath)) { return }
    try {
        $content = Get-Content -LiteralPath $SvgPath -Encoding UTF8 -Raw
        $bareCss = @'
<style>@media (prefers-color-scheme: light) {
/* Bare elements: PlantUML CSS mode may omit stroke on some shapes */
ellipse:not([style*="stroke"]):not([stroke]),
circle:not([style*="stroke"]):not([stroke]) {
 stroke: #000000 !important;
 stroke-width: 0.75 !important;
}
rect[fill="#FFFFFF"]:not([style*="stroke"]):not([stroke]),
rect[fill="#ffffff"]:not([style*="stroke"]):not([stroke]) {
 stroke: #000000 !important;
 stroke-width: 0.75 !important;
}
path[fill="none"]:not([style*="stroke"]):not([stroke]) {
 stroke: #000000 !important;
 stroke-width: 0.75 !important;
}
/* Swimlane headers rendered with white stroke (invisible on white canvas) */
[style*="stroke:#FFFFFF"], [style*="stroke: #FFFFFF"],
[style*="stroke:#ffffff"], [style*="stroke: #ffffff"] {
 stroke: #000000 !important;
}
}</style>
'@
        $content = $content -replace '(<svg[^>]*>)', "`$1`n$bareCss"
        Set-Content -LiteralPath $SvgPath -Value $content -Encoding UTF8 -NoNewline
    } catch {}
}

function New-DarkSvg {
    param([string]$LightPath, [string]$DarkPath)
    if (-not (Test-Path -LiteralPath $LightPath)) { return $false }
    try {
        $content = Get-Content -LiteralPath $LightPath -Encoding UTF8 -Raw

        # CSS dark mode block — uses @media (prefers-color-scheme: dark)
        # Color palette: GitHub dark theme inspired
        $darkCss = @'
<style>@media (prefers-color-scheme: dark) {
 svg {
 background: transparent !important;
 }
 [style*="background:#FFFFFF"], [style*="background: #FFFFFF"],
 [style*="background:#ffffff"], [style*="background: #ffffff"] {
 background: #1e1e2e !important;
 }
 [fill="#FFFFFF"], [fill="#ffffff"], [fill="#FFF"], [fill="#fff"],
 [fill="#FEFEFE"], [fill="#fefefe"], [fill="#F1F1F1"], [fill="#f1f1f1"],
 [fill="#EEEEEE"], [fill="#eeeeee"], [fill="#ECECEC"], [fill="#ececec"],
 [fill="#FFFFCC"], [fill="#ffffcc"] {
 fill: #1e1e2e !important;
 }
 /* Use case ellipses/circles: transparent fill so outline visible */
 ellipse[fill="#FFFFFF"], ellipse[fill="#ffffff"],
 ellipse[fill="#FFF"], ellipse[fill="#fff"],
 ellipse[fill="#FEFEFE"], ellipse[fill="#fefefe"],
 ellipse[style*="fill:#FFFFFF"], ellipse[style*="fill:#ffffff"],
 circle[fill="#FFFFFF"], circle[fill="#ffffff"],
 circle[fill="#FFF"], circle[fill="#fff"],
 circle[fill="#FEFEFE"], circle[fill="#fefefe"],
 circle[style*="fill:#FFFFFF"], circle[style*="fill:#ffffff"] {
 fill: none !important;
 stroke-width: 1.5 !important;
 }
 [stroke="#000000"], [stroke="#000"], [stroke="#181818"],
 [stroke="#222222"], [stroke="#222"], [stroke="#333333"], [stroke="#333"] {
 stroke: #c9d1d9 !important;
 }
 [style*="stroke:#181818"], [style*="stroke: #181818"],
 [style*="stroke:#000000"], [style*="stroke: #000000"],
 [style*="stroke:#222222"], [style*="stroke: #222222"],
 [style*="stroke:#333333"], [style*="stroke: #333333"] {
 stroke: #c9d1d9 !important;
 }
 [style*="stroke:#FFDD88"], [style*="stroke: #FFDD88"],
 [style*="stroke:#ffdd88"], [style*="stroke: #ffdd88"] {
 stroke: #6e7681 !important;
 }
 text, [fill="#000000"], [fill="#000"], [fill="#181818"], [fill="#222222"] {
 fill: #c9d1d9 !important;
 }
 polygon[fill="#000000"], polygon[fill="#181818"], polygon[fill="#222222"],
 polygon[fill="#333333"] {
 fill: #c9d1d9 !important;
 stroke: #c9d1d9 !important;
 }
 rect[style*="stroke:#000000"], rect[style*="stroke: #000000"],
 rect[style*="stroke:#181818"], rect[style*="stroke: #181818"] {
 stroke: #c9d1d9 !important;
 }
 ellipse[style*="stroke:#000000"], ellipse[style*="stroke: #000000"],
 ellipse[style*="stroke:#181818"], ellipse[style*="stroke: #181818"] {
 stroke: #c9d1d9 !important;
 }
 polygon[style*="stroke:#000000"], polygon[style*="stroke: #000000"],
 polygon[style*="stroke:#181818"], polygon[style*="stroke: #181818"],
 polygon[style*="stroke:#222222"], polygon[style*="stroke: #222222"] {
 stroke: #c9d1d9 !important;
 }
 line[stroke="#181818"], line[stroke="#000000"],
 line[style*="stroke:#181818"], line[style*="stroke: #181818"],
 line[style*="stroke:#000000"], line[style*="stroke: #000000"] {
 stroke: #6e7681 !important;
 stroke-dasharray: 4 3 !important;
 }
 text[font-weight="700"], text[font-weight="bold"] {
 fill: #f0f6fc !important;
 }
  /* Bare elements: PlantUML CSS mode may omit stroke on some shapes */
  ellipse:not([style*="stroke"]):not([stroke]),
  circle:not([style*="stroke"]):not([stroke]) {
  stroke: #c9d1d9 !important;
  stroke-width: 0.75 !important;
  }
  rect[fill="#FFFFFF"]:not([style*="stroke"]):not([stroke]),
  rect[fill="#ffffff"]:not([style*="stroke"]):not([stroke]) {
  stroke: #c9d1d9 !important;
  stroke-width: 0.75 !important;
  }
  path[fill="none"]:not([style*="stroke"]):not([stroke]) {
  stroke: #c9d1d9 !important;
  stroke-width: 0.75 !important;
  }
  /* Swimlane headers rendered with white stroke (invisible on dark canvas) */
  [style*="stroke:#FFFFFF"], [style*="stroke: #FFFFFF"],
  [style*="stroke:#ffffff"], [style*="stroke: #ffffff"] {
  stroke: #c9d1d9 !important;
  }
}</style>
'@

        # Inject CSS block after opening <svg> tag
        $content = $content -replace '(<svg[^>]*>)', "`$1`n$darkCss"

        Set-Content -LiteralPath $DarkPath -Value $content -Encoding UTF8 -NoNewline
        return $true
    } catch {
        return $false
    }
}

function New-DarkPng {
    param([string]$LightPath, [string]$DarkPath)
    if (-not (Test-Path -LiteralPath $LightPath)) { return $false }
    if (-not (Test-Command "convert")) { return $false }
    try {
        & convert $LightPath `
            -fuzz 25% -fill '#1A1A1A' -opaque '#FFFFFF' `
            -fuzz 25% -fill '#2D2D2D' -opaque '#FAFAFA' `
            -fuzz 25% -fill '#2D2D2D' -opaque '#F1F1F1' `
            -fuzz 25% -fill '#2D2D2D' -opaque '#F2F2F2' `
            -fuzz 25% -fill '#C0C0C0' -opaque '#222222' `
            -fuzz 25% -fill '#C0C0C0' -opaque '#181818' `
            -fuzz 25% -fill '#E8E8E8' -opaque '#000000' `
            $DarkPath 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $DarkPath)) { return $true }
    } catch { }
    return $false
}

function New-DarkImage {
    param([string]$LightPath, [string]$Fmt)
    if ($Fmt -notin @("svg", "png")) { return $null }
    $darkPath = $LightPath -replace "\.$Fmt$", ".dark.$Fmt"
    $ok = if ($Fmt -eq "svg") { New-DarkSvg $LightPath $darkPath } else { New-DarkPng $LightPath $darkPath }
    if ($ok) { return $darkPath }
    return $null
}

# ═══════════════════════════════════════════════════════════════════════════════
# Rendering Backends
# ═══════════════════════════════════════════════════════════════════════════════

function Convert-ViaServer {
    param([string]$SourcePath = $InputPath)
    # OPT-IN ONLY backend. DISABLED unless -UsePublicServer is passed.
    # When enabled, this function POSTs the entire diagram source to a Kroki
    # server (kroki.io by default, overridable via $env:PLANTUML_PUBLIC_SERVER).
    # The audit (SDI-2) flagged this as a data-exfiltration path, so we require
    # explicit user consent. Kroki is open source and self-hostable.
    if (-not $UsePublicServer) {
        Write-Host "  → Public server disabled (privacy default). Pass -UsePublicServer to enable."
        return $false
    }

    $serverHost = if ($env:PLANTUML_PUBLIC_SERVER) {
        $env:PLANTUML_PUBLIC_SERVER.TrimEnd('/')
    } else {
        "https://kroki.io"
    }
    $serverUrl = "$serverHost/plantuml/$Format"
    $hostLabel = ($serverHost -replace '^https?://', '') -replace '/.*$', ''

    Write-Host ""
    Write-Host "  ⚠  PRIVACY WARNING: about to upload diagram source to $serverUrl"
    Write-Host "     The full contents of '$SourcePath' will be transmitted to $hostLabel."
    if ($serverHost -eq "https://kroki.io") {
        Write-Host "     kroki.io is operated by Yuzu Tech (EU). Kroki is open source and"
        Write-Host "     self-hostable — set `$env:PLANTUML_PUBLIC_SERVER = '<your-url>' to use your own."
    } else {
        Write-Host "     (Custom backend selected via `$env:PLANTUML_PUBLIC_SERVER.)"
    }
    Write-Host "     Do NOT use this backend for confidential architecture, credentials,"
    Write-Host "     customer data, or proprietary business logic."
    Write-Host ""
    Write-Host "  → Trying public server (opt-in via -UsePublicServer)..."
    try {
        $body = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $SourcePath))
        Invoke-WebRequest -Uri $serverUrl -Method Post -Body $body `
            -ContentType "text/plain" -OutFile $outputFile `
            -TimeoutSec 60 -MaximumRedirection 5 `
            -UseBasicParsing -ErrorAction Stop | Out-Null

        $ok = $false
        if ($Format -eq "svg") {
            $content = Get-Content -LiteralPath $outputFile -Raw -ErrorAction SilentlyContinue
            if ($content -and ($content -match "<svg")) { $ok = $true }
        } elseif ($Format -eq "txt") {
            if ((Get-Item -LiteralPath $outputFile).Length -gt 0) { $ok = $true }
        } else {
            $ok = Test-BinaryOk -Path $outputFile -Fmt $Format
        }

        if ($ok) {
            Write-Host "  ✓ Success (public server)"
            return $true
        }
    } catch {
        # fall through
    }

    Write-Host "  ✗ Public server failed — check network or try Docker/local JAR backend"
    return $false
}

function Convert-ViaDocker {
    param([string]$SourcePath = $InputPath)
    if (-not (Test-Command "docker")) {
        Write-Host "  → Docker not available, skipping"
        return $false
    }

    Write-Host "  → Trying Docker (plantuml/plantuml)..."
    $ext = if ($Format -eq "txt") { "utxt" } else { $Format }

    $dockerTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("plantuml_docker_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dockerTmp -Force | Out-Null
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $dockerTmp -Force
        $inputFileName = [System.IO.Path]::GetFileName($SourcePath)

        # CJK font support: mount host font directories into container
        if ($Cjk) {
            $fontDirs = @()
            if ($env:WINDIR) { $fontDirs += "$env:WINDIR\Fonts" }
            foreach ($fd in @("C:\Windows\Fonts", "$env:SystemRoot\Fonts")) {
                if ($fd -and (Test-Path -LiteralPath $fd) -and $fontDirs -notcontains $fd) {
                    $fontDirs += $fd
                }
            }

            $fontMounted = $false
            $cjkDockerArgs = @("run", "--rm", "-v", "${dockerTmp}:/data")
            foreach ($fd in $fontDirs) {
                if (Test-Path -LiteralPath $fd) {
                    $cjkDockerArgs += "-v", "${fd}:/Windows/Fonts:ro"
                    $fontMounted = $true
                }
            }

            if ($fontMounted) {
                $cjkDockerArgs += @(
                    "--entrypoint", "sh",
                    "plantuml/plantuml:latest",
                    "-c", "fc-cache -f 2>/dev/null; plantuml -t$ext /data/$inputFileName"
                )
                Write-Host "  → CJK mode: mounting Windows fonts and refreshing font cache"
                try {
                    $proc = Start-Process -FilePath "docker" -ArgumentList $cjkDockerArgs `
                        -NoNewWindow -Wait -PassThru -RedirectStandardError "$dockerTmp\stderr.log"

                    if ($proc.ExitCode -eq 0) {
                        $generated = Get-ChildItem -Path $dockerTmp -Filter "*.$ext" -ErrorAction SilentlyContinue |
                                     Where-Object { $_.Name -ne $inputFileName } | Select-Object -First 1
                        if (-not $generated) {
                            $generated = Get-ChildItem -Path $dockerTmp -Filter "*.$Format" -ErrorAction SilentlyContinue |
                                         Where-Object { $_.Name -ne $inputFileName } | Select-Object -First 1
                        }
                        if ($generated) {
                            Move-Item -LiteralPath $generated.FullName -Destination $outputFile -Force
                            Write-Host "  ✓ Success (Docker + CJK)"
                            return $true
                        }
                    }
                } catch {
                    # fall through to standard Docker
                }
            } else {
                Write-Host "  ⚠ CJK mode: no host font directories found. CJK characters may not render correctly."
                Write-Host "    Install CJK fonts on your system, or place them in C:\Windows\Fonts"
            }
        }

        # Standard Docker rendering
        $proc = Start-Process -FilePath "docker" -ArgumentList @(
            "run", "--rm",
            "-v", "${dockerTmp}:/data",
            "plantuml/plantuml:latest",
            "-t$ext",
            "/data/$inputFileName"
        ) -NoNewWindow -Wait -PassThru -RedirectStandardError "$dockerTmp\stderr.log"

        if ($proc.ExitCode -eq 0) {
            $generated = Get-ChildItem -Path $dockerTmp -Filter "*.$ext" -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -ne $inputFileName } | Select-Object -First 1
            if (-not $generated) {
                $generated = Get-ChildItem -Path $dockerTmp -Filter "*.$Format" -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -ne $inputFileName } | Select-Object -First 1
            }
            if ($generated) {
                Move-Item -LiteralPath $generated.FullName -Destination $outputFile -Force
                Write-Host "  ✓ Success (Docker)"
                return $true
            }
        }
    } catch {
        # fall through
    } finally {
        if (Test-Path -LiteralPath $dockerTmp) {
            Remove-Item -LiteralPath $dockerTmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "  ✗ Docker conversion failed"
    return $false
}

function Convert-ViaLocal {
    param([string]$SourcePath = $InputPath)
    $candidates = @(
        (Join-Path $env:USERPROFILE   "plantuml.jar"),
        (Join-Path ${env:ProgramFiles} "PlantUML\plantuml.jar"),
        (Join-Path $env:LOCALAPPDATA  "PlantUML\plantuml.jar"),
        ".\plantuml.jar"
    )
    $jar = $null
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { $jar = $p; break }
    }
    if (-not $jar) {
        Write-Host "  → No local plantuml.jar found, skipping"
        return $false
    }
    if (-not (Test-Command "java")) {
        Write-Host "  → Java not available, skipping local JAR"
        return $false
    }

    Write-Host "  → Trying local JAR ($jar)..."
    $ext = if ($Format -eq "txt") { "utxt" } else { $Format }
    $tmpRender = Join-Path ([System.IO.Path]::GetTempPath()) ("plantuml_local_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmpRender -Force | Out-Null
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $tmpRender -Force
        $inputFileName = [System.IO.Path]::GetFileName($SourcePath)
        $proc = Start-Process -FilePath "java" -ArgumentList @(
            "-jar", "`"$jar`"", "-t$ext", "-o", "`"$tmpRender`"", "`"$tmpRender\$inputFileName`""
        ) -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            $baseSrc = [System.IO.Path]::GetFileNameWithoutExtension($inputFileName)
            $generated = Get-ChildItem -Path $tmpRender -Filter "$baseSrc.$ext" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $generated) {
                $generated = Get-ChildItem -Path $tmpRender -Filter "$baseSrc.$Format" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($generated) {
                Move-Item -LiteralPath $generated.FullName -Destination $outputFile -Force
                Write-Host "  ✓ Success (local JAR)"
                return $true
            }
        }
    } catch {
        # fall through
    } finally {
        if (Test-Path -LiteralPath $tmpRender) {
            Remove-Item -LiteralPath $tmpRender -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  ✗ Local JAR failed"
    return $false
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "🖼️  Converting $InputPath → $outputFile (format: $Format)"

# ── CJK Detection ────────────────────────────────────────────────────────────
if (-not $Cjk) {
    if (Detect-Cjk $InputPath) {
        Write-Host ""
        Write-Host "🔤 CJK (Chinese/Japanese/Korean) characters detected in input."
        Write-Host "   These may not render correctly without CJK font support."
        Write-Host "   Re-run with -Cjk to enable CJK rendering, or install CJK fonts."
        Write-Host "   Attempting to proceed anyway..."
        Write-Host ""
    }
}

# ── Prepare working copy ─────────────────────────────────────────────────────
# Always work on a copy so sanitization/CJK/aspect/A4 mutations never touch the
# original .puml on disk.
$tmpRoot = if ($env:TEMP) { $env:TEMP } elseif ($env:TMP) { $env:TMP } else { [System.IO.Path]::GetTempPath() }
$workCopy = Join-Path $tmpRoot ("plantuml_src_" + [System.Guid]::NewGuid().ToString("N") + ".puml")
Copy-Item -LiteralPath $InputPath -Destination $workCopy -Force
Sanitize-PumlSource $workCopy

$cjkCopy = $null
if ($Cjk) {
    Write-Host "🔤 CJK mode enabled: configuring CJK-compatible fonts"
    $cjkCopy = Prepare-PumlForCjk $workCopy
    Remove-Item -LiteralPath $workCopy -Force -ErrorAction SilentlyContinue
    $workCopy = $cjkCopy
    Sanitize-PumlSource $workCopy
}

# ── Render with aspect-ratio + A4-fit correction loop ────────────────────────
$renderOk = $false
$maxFixAttempts = 3
$fixAttempt = 0
$aspectDone = $false
$a4Tried = $false
$lastOkSrc = $workCopy

while ($fixAttempt -le $maxFixAttempts) {
    # Render using the current working copy (local-first: Docker → JAR → opt-in server)
    if (-not (Convert-ViaDocker $workCopy)) {
        if (-not (Convert-ViaLocal $workCopy)) {
            if (-not (Convert-ViaServer $workCopy)) {
                Write-Host ""
                Write-Host "❌ All conversion methods failed."
                Write-Host "   Install options (local, recommended for privacy):"
                Write-Host "   1. Docker: docker pull plantuml/plantuml:latest"
                Write-Host "   2. Java + JAR: download plantuml.jar from https://plantuml.com/download"
                Write-Host "   Or, to use the public Kroki server (uploads diagram to kroki.io):"
                Write-Host "   3. Re-run with -UsePublicServer (review the privacy notice first)"
                Write-Host "      Override the host with `$env:PLANTUML_PUBLIC_SERVER = '<url>' if self-hosting"
                if ($cjkCopy) { Remove-Item -LiteralPath $cjkCopy -Force -ErrorAction SilentlyContinue }
                exit 1
            }
        }
    }
    $renderOk = $true
    $lastOkSrc = $workCopy

    if ($Format -in @("txt", "pdf")) { break }

    if (-not $NoFix -and -not $aspectDone) {
        $aspectProblem = Test-AspectRatio $outputFile $Format
        if ($null -eq $aspectProblem) {
            Write-Host "  ⓘ Could not determine image dimensions; skipping aspect ratio check."
            $aspectDone = $true
        } elseif ($aspectProblem -ne "ok") {
            $fixAttempt++
            if ($fixAttempt -gt $maxFixAttempts) {
                Write-Host "  ⚠ Maximum fix attempts ($maxFixAttempts) reached. Manual adjustment may be needed."
                break
            }

            $fixedPuml = Fix-PumlAspectRatio $workCopy $aspectProblem
            if (-not $fixedPuml) {
                Write-Host "  ✗ Auto-fix step failed; keeping current output." >&2
                break
            }

            if ($workCopy -ne $InputPath) {
                Remove-Item -LiteralPath $workCopy -Force -ErrorAction SilentlyContinue
            }
            $workCopy = $fixedPuml
            Write-Host "  → Re-rendering with corrected layout..."
            continue
        }
        $aspectDone = $true
    }

    if (-not $NoA4Check -and -not $a4Tried) {
        $a4Ok = Test-A4Fit $outputFile $Format
        if ($null -eq $a4Ok) {
            Write-Host "  ⓘ Could not determine image dimensions; skipping A4 check."
            break
        } elseif (-not $a4Ok) {
            $fixAttempt++
            if ($fixAttempt -gt $maxFixAttempts) {
                Write-Host "  ⚠ Maximum fix attempts ($maxFixAttempts) reached; A4 fit may not hold."
                break
            }

            $a4Fixed = Fix-A4Fit $workCopy
            if (-not $a4Fixed) {
                Write-Host "  ✗ A4 auto-fit failed; using current diagram."
                $a4Tried = $true
                break
            }

            if ($workCopy -ne $InputPath) {
                Remove-Item -LiteralPath $workCopy -Force -ErrorAction SilentlyContinue
            }
            $workCopy = $a4Fixed
            $a4Tried = $true
            Write-Host "  → Re-rendering with A4-fit scale..."
            continue
        }
    }

    break
}

# Ensure we keep the last successful output if the final fix attempt did not re-render.
if ($workCopy -ne $lastOkSrc -and (Test-Path -LiteralPath $lastOkSrc)) {
    $workCopy = $lastOkSrc
}

# Fix bare strokes in light SVG (CSS mode may omit strokes on some shapes)
if ($renderOk -and $Format -eq "svg") {
    New-BareStrokesSvg $outputFile
}

# ── Dark-mode companion ──────────────────────────────────────────────────────
$darkOutput = $null
if ($DarkMode -and $renderOk -and $Format -in @("svg", "png")) {
    $darkOutput = New-DarkImage $outputFile $Format
    if ($darkOutput) {
        Write-Host "  🌙 Dark mode: $darkOutput"
    } else {
        Write-Host "  ⚠ Dark-mode companion could not be generated for $Format"
    }
}

# ── Cleanup temp files ───────────────────────────────────────────────────────
if ($workCopy -ne $InputPath) {
    Remove-Item -LiteralPath $workCopy -Force -ErrorAction SilentlyContinue
}
if ($cjkCopy -and $cjkCopy -ne $workCopy) {
    Remove-Item -LiteralPath $cjkCopy -Force -ErrorAction SilentlyContinue
}

# ── Report ───────────────────────────────────────────────────────────────────
if ($renderOk) {
    Write-Host ""
    Write-Host "✅ Output: $outputFile"
    if ($darkOutput) { Write-Host "✅ Dark:   $darkOutput" }
    Write-Output $outputFile
}