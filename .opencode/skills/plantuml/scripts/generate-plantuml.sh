#!/usr/bin/env bash
# generate-plantuml.sh — Convert PlantUML source to SVG, PNG, PDF, or ASCII art
#
# Usage:
#   generate-plantuml.sh <input.puml> [output_dir] [--format svg|png|pdf|txt]
#
# Defaults: output_dir=./output, format=svg
#
# Conversion methods (tried in strict priority order):
#   1. PlantUML public server (plantuml.com)   ← PREFERRED default backend
#   2. Docker (plantuml/plantuml image)        ← fallback when public server unreachable
#   3. Local plantuml.jar if present           ← last-resort offline fallback
#
# Cross-platform: works on Linux, macOS, and Windows (Git Bash / MSYS2 / WSL / Cygwin).
set -euo pipefail

INPUT=""
OUTPUT_DIR="./output"
FORMAT="svg"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            FORMAT="${2:-svg}"
            shift 2
            ;;
        --format=*)
            FORMAT="${1#*=}"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <input.puml> [output_dir] [--format svg|png|pdf|txt]"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$INPUT" ]]; then
                INPUT="$1"
            elif [[ "$OUTPUT_DIR" == "./output" ]]; then
                OUTPUT_DIR="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    echo "Usage: $0 <input.puml> [output_dir] [--format svg|png|pdf|txt]" >&2
    exit 1
fi

INPUT_BASENAME=$(basename "$INPUT" .puml)
INPUT_BASENAME="${INPUT_BASENAME%.plantuml}"
INPUT_BASENAME="${INPUT_BASENAME%.txt}"
OUTPUT_FILE="${OUTPUT_DIR}/${INPUT_BASENAME}.${FORMAT}"

mkdir -p "$OUTPUT_DIR"

if [[ ! -f "$INPUT" ]]; then
    echo "ERROR: Input file not found: $INPUT" >&2
    exit 1
fi

# Validate format
case "$FORMAT" in
    svg|png|pdf|txt) ;;
    *)
        echo "ERROR: Unsupported format '$FORMAT'. Use: svg, png, pdf, txt" >&2
        exit 1
        ;;
esac

# Portable temp dir (Linux/macOS: /tmp; Windows Git-Bash/MSYS: $TMPDIR or $TEMP)
PORTABLE_TMP="${TMPDIR:-${TEMP:-${TMP:-/tmp}}}"

# Portable binary-file sniffer: prefer `file` if present, otherwise read magic bytes
detect_binary_ok() {
    local path="$1"
    local fmt="$2"
    [[ -s "$path" ]] || return 1

    if command -v file &>/dev/null; then
        file "$path" | grep -qiE 'png|pdf|image' && return 0
    fi

    # Fallback: check magic bytes with `od` (available on Linux, macOS, and Git Bash)
    if command -v od &>/dev/null; then
        local magic
        magic=$(od -An -N4 -tx1 "$path" 2>/dev/null | tr -d ' \n')
        case "$fmt" in
            png) [[ "$magic" == "89504e47" ]] && return 0 ;;
            pdf) [[ "$magic" == "25504446" ]] && return 0 ;;  # %PDF
        esac
    fi

    # Last resort: assume non-empty file is valid
    return 0
}

echo "🖼️  Converting $INPUT → $OUTPUT_FILE (format: $FORMAT)"

# ─── Method 1: PlantUML Public Server (PREFERRED) ───────────────────────────
# Always tried first — fast, no local dependency, produces canonical PlantUML output.
# Falls back to Docker / local JAR only when the public server cannot be reached.
convert_via_server() {
    local server_url
    case "$FORMAT" in
        svg) server_url="https://www.plantuml.com/plantuml/svg" ;;
        png) server_url="https://www.plantuml.com/plantuml/png" ;;
        pdf) server_url="https://www.plantuml.com/plantuml/pdf" ;;
        txt) server_url="https://www.plantuml.com/plantuml/txt" ;;
    esac

    if ! command -v curl &>/dev/null; then
        echo "  → curl not available, skipping public server"
        return 1
    fi

    echo "  → Trying PlantUML public server (preferred)..."
    # Short connect timeout + bounded total time so an unreachable server falls back quickly.
    if curl -sSf --connect-timeout 5 --max-time 30 \
            -o "$OUTPUT_FILE" -X POST "$server_url" --data-binary "@$INPUT" 2>/dev/null; then
        if [[ "$FORMAT" == "svg" ]] && [[ -s "$OUTPUT_FILE" ]] && head -1 "$OUTPUT_FILE" | grep -q '<svg'; then
            echo "  ✓ Success (public server)"
            return 0
        elif [[ "$FORMAT" == "txt" ]] && [[ -s "$OUTPUT_FILE" ]]; then
            echo "  ✓ Success (public server)"
            return 0
        elif [[ "$FORMAT" != "svg" && "$FORMAT" != "txt" ]] && detect_binary_ok "$OUTPUT_FILE" "$FORMAT"; then
            echo "  ✓ Success (public server)"
            return 0
        fi
    fi
    echo "  ✗ Public server failed (will fall back to Docker, then local JAR)"
    rm -f "$OUTPUT_FILE"
    return 1
}

# ─── Method 2: Docker ────────────────────────────────────────────────────────
convert_via_docker() {
    if ! command -v docker &>/dev/null; then
        echo "  → Docker not available, skipping"
        return 1
    fi

    echo "  → Trying Docker (plantuml/plantuml)..."
    local ext="$FORMAT"
    [[ "$FORMAT" == "txt" ]] && ext="utxt"

    # Portable temporary working directory
    local docker_tmp="${PORTABLE_TMP}/plantuml_docker_$$"
    mkdir -p "$docker_tmp"
    cp "$INPUT" "$docker_tmp/"

    # On Windows Git-Bash/MSYS the path passed to `docker -v` must be converted.
    # `cygpath -w` (Cygwin/MSYS) or `wslpath -w` (WSL) handle this when available.
    local docker_mount="$docker_tmp"
    if command -v cygpath &>/dev/null; then
        docker_mount=$(cygpath -w "$docker_tmp")
    elif command -v wslpath &>/dev/null; then
        docker_mount=$(wslpath -w "$docker_tmp" 2>/dev/null || echo "$docker_tmp")
    fi

    if MSYS_NO_PATHCONV=1 docker run --rm -v "${docker_mount}:/data" plantuml/plantuml:latest \
        "-t$ext" "/data/$(basename "$INPUT")" 2>/dev/null; then

        local generated
        generated=$(ls "$docker_tmp"/*."$ext" 2>/dev/null || ls "$docker_tmp"/*."$FORMAT" 2>/dev/null || echo "")
        if [[ -n "$generated" ]]; then
            mv "$generated" "$OUTPUT_FILE"
            rm -rf "$docker_tmp"
            echo "  ✓ Success (Docker)"
            return 0
        fi
    fi
    rm -rf "$docker_tmp"
    echo "  ✗ Docker conversion failed"
    return 1
}

# ─── Method 3: Local JAR ─────────────────────────────────────────────────────
convert_via_local() {
    local jar_paths=(
        "/usr/local/bin/plantuml.jar"
        "/usr/share/plantuml/plantuml.jar"
        "${HOME:-}/plantuml.jar"
        "${USERPROFILE:-}/plantuml.jar"
        "${PROGRAMFILES:-}/PlantUML/plantuml.jar"
        "${LOCALAPPDATA:-}/PlantUML/plantuml.jar"
        "./plantuml.jar"
    )
    local jar=""
    for p in "${jar_paths[@]}"; do
        [[ -z "$p" ]] && continue
        if [[ -f "$p" ]]; then
            jar="$p"
            break
        fi
    done
    if [[ -z "$jar" ]]; then
        echo "  → No local plantuml.jar found, skipping"
        return 1
    fi
    if ! command -v java &>/dev/null; then
        echo "  → Java not available, skipping local JAR"
        return 1
    fi

    echo "  → Trying local JAR ($jar)..."
    local ext="$FORMAT"
    [[ "$FORMAT" == "txt" ]] && ext="utxt"

    if java -jar "$jar" "-t$ext" -o "$OUTPUT_DIR" "$INPUT" 2>/dev/null; then
        echo "  ✓ Success (local JAR)"
        return 0
    fi
    echo "  ✗ Local JAR failed"
    return 1
}

# ─── Main ────────────────────────────────────────────────────────────────────
convert_via_server || convert_via_docker || convert_via_local || {
    echo ""
    echo "❌ All conversion methods failed."
    echo "   Install options:"
    echo "   1. Docker: docker pull plantuml/plantuml:latest"
    echo "   2. Java + JAR: download plantuml.jar from https://plantuml.com/download"
    exit 1
}

echo ""
echo "✅ Output: $OUTPUT_FILE"
echo "$OUTPUT_FILE"
