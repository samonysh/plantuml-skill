#!/usr/bin/env bash
# generate-plantuml.sh — Convert PlantUML source to SVG, PNG, PDF, or ASCII art
#
# Usage:
#   generate-plantuml.sh <input.puml> [output_dir] [--format svg|png|pdf|txt]
#
# Defaults: output_dir=./output, format=svg
#
# Conversion methods (tried in order):
#   1. PlantUML public server (plantuml.com)
#   2. Docker (plantuml/plantuml image)
#   3. Local plantuml.jar if present
#
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

echo "🖼️  Converting $INPUT → $OUTPUT_FILE (format: $FORMAT)"

# ─── Method 1: PlantUML Public Server ────────────────────────────────────────
convert_via_server() {
    local server_url
    case "$FORMAT" in
        svg) server_url="https://www.plantuml.com/plantuml/svg" ;;
        png) server_url="https://www.plantuml.com/plantuml/png" ;;
        pdf) server_url="https://www.plantuml.com/plantuml/pdf" ;;
        txt) server_url="https://www.plantuml.com/plantuml/txt" ;;
    esac

    echo "  → Trying PlantUML public server..."
    if curl -sSf -o "$OUTPUT_FILE" -X POST "$server_url" --data-binary "@$INPUT" 2>/dev/null; then
        if [[ "$FORMAT" == "svg" ]] && [[ -s "$OUTPUT_FILE" ]] && head -1 "$OUTPUT_FILE" | grep -q '<svg'; then
            echo "  ✓ Success (public server)"
            return 0
        elif [[ "$FORMAT" != "svg" ]] && [[ -s "$OUTPUT_FILE" ]] && file "$OUTPUT_FILE" | grep -qiE 'png|pdf|image'; then
            echo "  ✓ Success (public server)"
            return 0
        elif [[ "$FORMAT" == "txt" ]] && [[ -s "$OUTPUT_FILE" ]]; then
            echo "  ✓ Success (public server)"
            return 0
        fi
    fi
    echo "  ✗ Public server failed"
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

    # Docker outputs to the same filename but with new extension in same dir
    local docker_tmp="/tmp/plantuml_docker_$$"
    mkdir -p "$docker_tmp"
    cp "$INPUT" "$docker_tmp/"

    if docker run --rm -v "$docker_tmp:/data" plantuml/plantuml:latest \
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
        "$HOME/plantuml.jar"
        "./plantuml.jar"
    )
    local jar=""
    for p in "${jar_paths[@]}"; do
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
