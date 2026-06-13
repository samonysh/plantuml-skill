<#
.SYNOPSIS
    Convert PlantUML source to SVG, PNG, PDF, or ASCII art on Windows (PowerShell).

.DESCRIPTION
    Mirror of generate-plantuml.sh for native Windows PowerShell users.
    Tries three backends in strict priority order:
      1. PlantUML public server (plantuml.com)   — PREFERRED default backend
      2. Docker (plantuml/plantuml image)        — fallback
      3. Local plantuml.jar                       — last-resort offline fallback

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

.PARAMETER MaxAspect
    Maximum allowed aspect ratio before correction (default: 2.5).

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -Format svg

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -Cjk -Format png

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -MaxAspect 3.0
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
    [float]$MaxAspect = 2.5
)

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

    $ratio = if ($w -gt $h) { [math]::Round($w / $h, 2) } else { [math]::Round($h / $w, 2) }
    Write-Host "  📐 Dimensions: ${w}x${h}, aspect ratio: ${ratio}:1 (max: ${MaxAspect}:1)"
    return ($ratio -le $MaxAspect)
}

function Fix-PumlAspectRatio {
    param([string]$PumlPath, [string]$Problem)

    Write-Host "  → Attempting to fix aspect ratio (${Problem})..."
    $content = Get-Content -LiteralPath $PumlPath -Encoding UTF8 -Raw

    if ($content -match '!pragma aspectRatioFixed') {
        Write-Host "  → Already auto-fixed; skipping further attempts"
        return $null
    }

    $tmpPath = "${PumlPath}.fixed"
    $content = $content -replace '@startuml', "@startuml`n!pragma aspectRatioFixed"

    if ($Problem -eq "too_tall") {
        $content = $content -replace '@startuml', "@startuml`nleft to right direction"
        Write-Host "  → Applied: left to right direction"
        $content = $content -replace 'skinparam StereotypeCBackgroundColor white',
            "skinparam StereotypeCBackgroundColor white`nskinparam ParticipantPadding 5"
    } else {
        if ($content -match "left to right direction") {
            $content = $content -replace "left to right direction`r?`n", ""
        }
        $content = $content -replace '@startuml', "@startuml`ntop to bottom direction"
        Write-Host "  → Applied: top to bottom direction"
        $content = $content -replace 'skinparam StereotypeCBackgroundColor white',
            "skinparam StereotypeCBackgroundColor white`nskinparam BoxPadding 5`nskinparam ParticipantPadding 5"
    }

    if ($content -notmatch '^scale ') {
        $content = $content -replace 'skinparam StereotypeCBackgroundColor white',
            "skinparam StereotypeCBackgroundColor white`nscale 0.8"
        Write-Host "  → Applied: scale 0.8"
    }

    Set-Content -LiteralPath $tmpPath -Value $content -Encoding UTF8 -NoNewline
    return $tmpPath
}

# ═══════════════════════════════════════════════════════════════════════════════
# Rendering Backends
# ═══════════════════════════════════════════════════════════════════════════════

function Convert-ViaServer {
    param([string]$SourcePath = $InputPath)
    # PREFERRED backend — always attempted first.
    $serverUrl = switch ($Format) {
        "svg" { "https://www.plantuml.com/plantuml/svg" }
        "png" { "https://www.plantuml.com/plantuml/png" }
        "pdf" { "https://www.plantuml.com/plantuml/pdf" }
        "txt" { "https://www.plantuml.com/plantuml/txt" }
    }

    Write-Host "  → Trying PlantUML public server (preferred)..."
    try {
        $body = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $SourcePath))
        Invoke-WebRequest -Uri $serverUrl -Method Post -Body $body `
            -ContentType "text/plain" -OutFile $outputFile `
            -TimeoutSec 30 `
            -UseBasicParsing -ErrorAction Stop | Out-Null

        $ok = $false
        if ($Format -eq "svg") {
            $first = Get-Content -LiteralPath $outputFile -TotalCount 1 -ErrorAction SilentlyContinue
            if ($first -and ($first -match "<svg")) { $ok = $true }
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

    Write-Host "  ✗ Public server failed (will fall back to Docker, then local JAR)"
    if (Test-Path -LiteralPath $outputFile) { Remove-Item -LiteralPath $outputFile -Force }
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
    try {
        $proc = Start-Process -FilePath "java" -ArgumentList @(
            "-jar", "`"$jar`"", "-t$ext", "-o", "`"$OutputDir`"", "`"$SourcePath`""
        ) -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-Host "  ✓ Success (local JAR)"
            return $true
        }
    } catch {
        # fall through
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
$workCopy = $InputPath
$cjkCopy = $null
if ($Cjk) {
    Write-Host "🔤 CJK mode enabled: configuring CJK-compatible fonts"
    $cjkCopy = Prepare-PumlForCjk $InputPath
    $workCopy = $cjkCopy
}

# ── Render with aspect ratio correction loop ─────────────────────────────────
$renderOk = $false
$maxFixAttempts = 2
$fixAttempt = 0

while ($fixAttempt -le $maxFixAttempts) {
    # Render using the current working copy
    if (-not (Convert-ViaServer $workCopy)) {
        if (-not (Convert-ViaDocker $workCopy)) {
            if (-not (Convert-ViaLocal $workCopy)) {
                Write-Host ""
                Write-Host "❌ All conversion methods failed."
                Write-Host "   Install options:"
                Write-Host "   1. Docker: docker pull plantuml/plantuml:latest"
                Write-Host "   2. Java + JAR: download plantuml.jar from https://plantuml.com/download"
                if ($cjkCopy) { Remove-Item -LiteralPath $cjkCopy -Force -ErrorAction SilentlyContinue }
                exit 1
            }
        }
    }

    $renderOk = $true

    # ── Aspect Ratio Validation & Auto-Fix ────────────────────────────────────
    if (-not $NoFix -and $Format -notin @("txt", "pdf")) {
        $aspectOk = Test-AspectRatio $outputFile $Format
        if ($null -eq $aspectOk) {
            Write-Host "  ⓘ Could not determine image dimensions; skipping aspect ratio check."
            break
        }
        if ($aspectOk) { break }

        $fixAttempt++
        if ($fixAttempt -gt $maxFixAttempts) {
            Write-Host "  ⚠ Maximum fix attempts (2) reached. Manual adjustment may be needed."
            break
        }

        $w = if ($Format -eq "svg") { $script:svgWidth } else { $script:pngWidth }
        $h = if ($Format -eq "svg") { $script:svgHeight } else { $script:pngHeight }
        $problem = if ($h -gt $w) { "too_tall" } else { "too_wide" }

        $fixedPuml = Fix-PumlAspectRatio $workCopy $problem
        if (-not $fixedPuml) {
            Write-Host "  ✗ Auto-fix failed; using original diagram."
            break
        }

        if ($workCopy -ne $InputPath) {
            Remove-Item -LiteralPath $workCopy -Force -ErrorAction SilentlyContinue
        }
        $workCopy = $fixedPuml
        Write-Host "  → Re-rendering with corrected layout..."
    } else {
        break
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
    Write-Output $outputFile
}