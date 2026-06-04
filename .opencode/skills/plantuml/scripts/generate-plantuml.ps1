<#
.SYNOPSIS
    Convert PlantUML source to SVG, PNG, PDF, or ASCII art on Windows (PowerShell).

.DESCRIPTION
    Mirror of generate-plantuml.sh for native Windows PowerShell users.
    Tries three backends in strict priority order:
      1. PlantUML public server (plantuml.com)   — PREFERRED default backend
      2. Docker (plantuml/plantuml image)        — fallback
      3. Local plantuml.jar                       — last-resort offline fallback

.PARAMETER InputPath
    Path to the .puml source file.

.PARAMETER OutputDir
    Output directory. Defaults to .\output.

.PARAMETER Format
    Output format: svg (default), png, pdf, or txt.

.EXAMPLE
    .\generate-plantuml.ps1 diagram.puml .\out -Format svg
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias("Input")]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutputDir = ".\output",

    [ValidateSet("svg", "png", "pdf", "txt")]
    [string]$Format = "svg"
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

Write-Host "🖼️  Converting $InputPath → $outputFile (format: $Format)"

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

function Convert-ViaServer {
    # PREFERRED backend — always attempted first.
    $serverUrl = switch ($Format) {
        "svg" { "https://www.plantuml.com/plantuml/svg" }
        "png" { "https://www.plantuml.com/plantuml/png" }
        "pdf" { "https://www.plantuml.com/plantuml/pdf" }
        "txt" { "https://www.plantuml.com/plantuml/txt" }
    }

    Write-Host "  → Trying PlantUML public server (preferred)..."
    try {
        $body = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $InputPath))
        # Bounded TimeoutSec so an unreachable server falls back quickly to Docker/JAR.
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
    if (-not (Test-Command "docker")) {
        Write-Host "  → Docker not available, skipping"
        return $false
    }

    Write-Host "  → Trying Docker (plantuml/plantuml)..."
    $ext = if ($Format -eq "txt") { "utxt" } else { $Format }

    $dockerTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("plantuml_docker_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dockerTmp -Force | Out-Null
    try {
        Copy-Item -LiteralPath $InputPath -Destination $dockerTmp -Force
        $inputFileName = [System.IO.Path]::GetFileName($InputPath)

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
            "-jar", "`"$jar`"", "-t$ext", "-o", "`"$OutputDir`"", "`"$InputPath`""
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

if (-not (Convert-ViaServer)) {
    if (-not (Convert-ViaDocker)) {
        if (-not (Convert-ViaLocal)) {
            Write-Host ""
            Write-Host "❌ All conversion methods failed."
            Write-Host "   Install options:"
            Write-Host "   1. Docker: docker pull plantuml/plantuml:latest"
            Write-Host "   2. Java + JAR: download plantuml.jar from https://plantuml.com/download"
            exit 1
        }
    }
}

Write-Host ""
Write-Host "✅ Output: $outputFile"
Write-Output $outputFile
