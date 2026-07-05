#!/usr/bin/env bash
# generate-plantuml.sh — Convert PlantUML source to SVG, PNG, PDF, or ASCII art
#
# Usage:
#   generate-plantuml.sh <input.puml> [output_dir] [options]
#
# Options:
#   --format svg|png|pdf|txt    Output format (default: svg)
#   --cjk                       Enable CJK (Chinese/Japanese/Korean) font support
#   --no-fix                    Disable automatic aspect ratio correction
#   --min-aspect N              Min allowed width/height ratio before correction (default: 0.7)
#   --max-aspect N              Max allowed width/height ratio before correction (default: 1.4)
#   --no-a4-check               Disable automatic A4 paper fit validation
#                               The A4 check ensures the rendered diagram fits within
#                               either portrait (794×1123 px @ 96 DPI) or landscape
#                               (1123×794 px) A4 dimensions and that the rendered
#                               font remains legible when printed. ON by default.
#   --min-font-pt N             Minimum legible font size on A4 paper, in pt
#                               (default: 8.0). Used only by --a4-check.
#   --use-public-server         Opt-in to render via the public Kroki server.
#                               WARNING: this uploads your diagram source to a third
#                               party (kroki.io by default). Override the host with
#                               PLANTUML_PUBLIC_SERVER=<url> to point at a self-hosted
#                               Kroki instance. Off by default.
#
# Defaults: output_dir=./output, format=svg
#
# ─────────────────────────────────────────────────────────────────────────────
# PRIVACY NOTICE
# ─────────────────────────────────────────────────────────────────────────────
# This script renders diagrams LOCALLY by default. The PlantUML source is NOT
# transmitted off-host unless you explicitly pass --use-public-server.
#
# Conversion methods (tried in strict priority order — local-first):
#   1. Docker (plantuml/plantuml image)        ← PREFERRED default, fully local
#   2. Local plantuml.jar if present           ← offline fallback (Java required)
#   3. Kroki public server (kroki.io)          ← OPT-IN ONLY (--use-public-server)
#                                                Uploads diagram source to a
#                                                third party operated by Yuzu Tech
#                                                (EU). Kroki is open source and
#                                                self-hostable — point at your
#                                                own instance with the env var
#                                                PLANTUML_PUBLIC_SERVER=<url>.
#                                                Avoid the default public host
#                                                for confidential architecture,
#                                                credentials, or proprietary
#                                                business logic.
#
# Note on the previous backend: the legacy https://www.plantuml.com/plantuml
# POST endpoint now sits behind a Cloudflare + Ezoic consent wall that returns
# HTTP 302 to a JavaScript-only HTML page, breaking automated rendering. Kroki
# replaces it as the default opt-in public backend in v1.4.1.
# ─────────────────────────────────────────────────────────────────────────────
#
# Cross-platform: works on Linux, macOS, and Windows (Git Bash / MSYS2 / WSL / Cygwin).
set -euo pipefail

INPUT=""
OUTPUT_DIR="./output"
FORMAT="svg"
CJK=false
AUTO_FIX=true
MIN_ASPECT=0.7
MAX_ASPECT=1.4
A4_CHECK=true
DARK_MODE=false
MIN_FONT_PT=8.0
USE_PUBLIC_SERVER=false

# A4 paper dimensions in pixels at 96 DPI (CSS standard: 1in = 96px, A4 = 210×297 mm)
A4_PORTRAIT_W=794
A4_PORTRAIT_H=1123
A4_LANDSCAPE_W=1123
A4_LANDSCAPE_H=794

# PlantUML/SVG default body font size in px produced by the mandatory preamble
DEFAULT_FONT_PX=12

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
        --cjk)
            CJK=true
            shift
            ;;
        --no-fix)
            AUTO_FIX=false
            shift
            ;;
        --min-aspect)
            MIN_ASPECT="${2:-0.7}"
            shift 2
            ;;
        --min-aspect=*)
            MIN_ASPECT="${1#*=}"
            shift
            ;;
        --max-aspect)
            MAX_ASPECT="${2:-1.4}"
            shift 2
            ;;
        --max-aspect=*)
            MAX_ASPECT="${1#*=}"
            shift
            ;;
        --dark-mode)
            DARK_MODE=true
            shift
            ;;
        --no-a4-check)
            A4_CHECK=false
            shift
            ;;
        --min-font-pt)
            MIN_FONT_PT="${2:-8.0}"
            shift 2
            ;;
        --min-font-pt=*)
            MIN_FONT_PT="${1#*=}"
            shift
            ;;
        --use-public-server)
            USE_PUBLIC_SERVER=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <input.puml> [output_dir] [options]"
            echo ""
            echo "Options:"
            echo "  --format svg|png|pdf|txt    Output format (default: svg)"
            echo "  --cjk                       Enable CJK (Chinese/Japanese/Korean) font support"
            echo "  --no-fix                    Disable automatic aspect ratio correction"
            echo "  --min-aspect N              Min width/height ratio before correction (default: 0.7)"
            echo "  --max-aspect N              Max width/height ratio before correction (default: 1.4)"
            echo "  --dark-mode                 Also emit a dark-themed variant (<name>.dark.<fmt>)"
            echo "  --no-a4-check               Disable automatic A4 paper fit validation (ON by default)"
            echo "  --min-font-pt N             Min legible font size on A4 paper in pt"
            echo "                              (default: 8.0). Used only when A4 check is on."
            echo "  --use-public-server         OPT-IN: render via Kroki (kroki.io). Uploads"
            echo "                              diagram source to a third party (Yuzu Tech, EU)."
            echo "                              Override host via PLANTUML_PUBLIC_SERVER=<url>"
            echo "                              to point at a self-hosted Kroki instance."
            echo "                              Off by default."
            echo ""
            echo "Backend priority (local-first):"
            echo "  1. Docker (plantuml/plantuml)   — preferred, fully local"
            echo "  2. Local plantuml.jar           — offline fallback (Java required)"
            echo "  3. Kroki public server          — OPT-IN ONLY via --use-public-server"
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

# ═══════════════════════════════════════════════════════════════════════════════
# CJK Font Detection & Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# detect_cjk — Check if file contains CJK characters
# Returns: 0 if CJK found, 1 otherwise
detect_cjk() {
    local file="$1"
    # Try python3, then python (Windows often uses "python"), then perl, then grep -P
    local py_cmd=""
    if command -v python3 &>/dev/null; then
        py_cmd="python3"
    elif command -v python &>/dev/null; then
        py_cmd="python"
    fi
    if [[ -n "$py_cmd" ]]; then
        $py_cmd -c "
import sys
data = open(sys.argv[1], 'rb').read().decode('utf-8', errors='ignore')
for c in data:
    cp = ord(c)
    if ((0x4E00 <= cp <= 0x9FFF) or (0x3400 <= cp <= 0x4DBF) or
        (0x20000 <= cp <= 0x2A6DF) or (0xF900 <= cp <= 0xFAFF) or
        (0x2F800 <= cp <= 0x2FA1F) or (0x3000 <= cp <= 0x303F) or
        (0xFF00 <= cp <= 0xFFEF) or (0x3040 <= cp <= 0x309F) or
        (0x30A0 <= cp <= 0x30FF) or (0xAC00 <= cp <= 0xD7AF)):
        sys.exit(0)
sys.exit(1)
" "$file" 2>/dev/null
        return $?
    elif command -v perl &>/dev/null; then
        perl -CS -ne 'exit(0) if /[\x{4E00}-\x{9FFF}\x{3400}-\x{4DBF}\x{F900}-\x{FAFF}\x{3040}-\x{30FF}\x{AC00}-\x{D7AF}]/' "$file" 2>/dev/null
        return $?
    else
        # grep -P (Perl regex) — supported by GNU grep, not by MSYS2/BSD
        # Fallback: check raw UTF-8 byte sequences for CJK ranges
        grep -qP '[\x{4e00}-\x{9fff}]' "$file" 2>/dev/null && return 0
        grep -qP '[\x{3040}-\x{30ff}]' "$file" 2>/dev/null && return 0
        grep -qP '[\x{ac00}-\x{d7af}]' "$file" 2>/dev/null && return 0
        return 1
    fi
}

# prepare_puml_for_cjk — Creates a modified copy of the puml with CJK font config
# Returns: path to modified puml file
prepare_puml_for_cjk() {
    local src="$1"
    local dst="${src}.cjk.puml"

    sed -e 's/skinparam defaultFontName Helvetica/skinparam defaultFontName "WenQuanYi Micro Hei"/' \
        -e 's/skinparam defaultFontName [A-Za-z]*/skinparam defaultFontName "WenQuanYi Micro Hei"/' \
        "$src" > "$dst"

    if ! grep -q 'defaultFontName' "$dst"; then
        sed -i '1s/^@startuml/@startuml\n!pragma defaultFontName "WenQuanYi Micro Hei"\nskinparam defaultFontName "WenQuanYi Micro Hei"/' "$dst"
    fi

    echo "$dst"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Aspect Ratio Validation & Auto-Fix
# ═══════════════════════════════════════════════════════════════════════════════

# get_svg_dimensions — Extract width/height from SVG viewBox
# Sets global vars: SVG_WIDTH, SVG_HEIGHT
# Returns: 0 on success, 1 on failure
get_svg_dimensions() {
    local svg_file="$1"
    SVG_WIDTH=""
    SVG_HEIGHT=""

    if [[ ! -f "$svg_file" ]]; then
        return 1
    fi

    # Extract viewBox numbers using sed + awk (portable, no grep -P dependency)
    local nums
    nums=$(sed -n 's/.*viewBox="\([0-9.]* [0-9.]* [0-9.]* [0-9.]*\)".*/\1/p' "$svg_file" 2>/dev/null | head -1)

    if [[ -n "$nums" ]]; then
        SVG_WIDTH=$(echo "$nums" | awk '{print int($3)}')
        SVG_HEIGHT=$(echo "$nums" | awk '{print int($4)}')

        if [[ -n "$SVG_WIDTH" ]] && [[ -n "$SVG_HEIGHT" ]]; then
            return 0
        fi
    fi
    return 1
}

# get_png_dimensions — Extract width/height from PNG using ImageMagick identify
# Sets global vars: PNG_WIDTH, PNG_HEIGHT
# Returns: 0 on success, 1 on failure
get_png_dimensions() {
    local png_file="$1"
    PNG_WIDTH=""
    PNG_HEIGHT=""

    if ! command -v identify &>/dev/null; then
        return 1
    fi

    local dims
    dims=$(identify -format "%w %h" "$png_file" 2>/dev/null) || return 1
    PNG_WIDTH=$(echo "$dims" | cut -d' ' -f1)
    PNG_HEIGHT=$(echo "$dims" | cut -d' ' -f2)

    [[ -n "$PNG_WIDTH" ]] && [[ -n "$PNG_HEIGHT" ]]
}

# check_aspect_ratio — Validate width/height ratio sits inside [MIN_ASPECT, MAX_ASPECT]
# Arguments: $1=image_file, $2=format (svg|png)
# Returns: 0 if OK, 1 if needs fixing, 2 if check failed (can't determine dimensions)
# Side effects: sets CHECKED_ASPECT_PROBLEM to too_tall|too_wide|ok
check_aspect_ratio() {
    local img="$1"
    local fmt="$2"
    local w h

    CHECKED_ASPECT_PROBLEM="ok"

    case "$fmt" in
        svg)
            get_svg_dimensions "$img" || return 2
            w="$SVG_WIDTH"
            h="$SVG_HEIGHT"
            ;;
        png)
            get_png_dimensions "$img" || return 2
            w="$PNG_WIDTH"
            h="$PNG_HEIGHT"
            ;;
        *) return 2 ;;
    esac

    if [[ -z "$w" ]] || [[ -z "$h" ]] || [[ "$w" -le 0 ]] || [[ "$h" -le 0 ]]; then
        return 2
    fi

    local ratio
    ratio=$(awk "BEGIN {printf \"%.2f\", $w / $h}")

    echo "  📐 Dimensions: ${w}x${h}, width/height ratio: ${ratio} (target ${MIN_ASPECT}–${MAX_ASPECT})"

    if awk "BEGIN {exit !($ratio < $MIN_ASPECT)}" 2>/dev/null; then
        echo "  ⚠ Aspect ratio ${ratio} is below minimum ${MIN_ASPECT} — diagram is too tall"
        CHECKED_ASPECT_PROBLEM="too_tall"
        return 1
    fi

    if awk "BEGIN {exit !($ratio > $MAX_ASPECT)}" 2>/dev/null; then
        echo "  ⚠ Aspect ratio ${ratio} exceeds maximum ${MAX_ASPECT} — diagram is too wide"
        CHECKED_ASPECT_PROBLEM="too_wide"
        return 1
    fi

    return 0
}

# Spacing guards injected during aspect-ratio auto-fix to keep text readable.
# Uses CSS <style> block where possible; skinparam only for settings without CSS equivalent.
SPACING_GUARD_CSS='<style>
root {
  padding 8
  wrapWidth 220
}
activityDiagram {
  activity { padding 8 }
}
sequenceDiagram {
  participant { padding 8 }
  box { padding 8 }
}
classDiagram {
  class { padding 8; MinimumWidth 100 }
}
stateDiagram {
  state { padding 8 }
}
</style>'
# NodeSep / RankSep have no CSS equivalent — keep as skinparam
SPACING_GUARD_SKINPARAMS="skinparam NodeSep 35
skinparam RankSep 35"

# fix_puml_aspect_ratio — Modify .puml file to improve aspect ratio
# Arguments: $1=puml_file, $2=too_wide|too_tall
# Returns: path to modified .puml on stdout, empty string on failure.
# stdout must stay clean because callers capture it via $(...); logs go to stderr.
fix_puml_aspect_ratio() {
    local puml="$1"
    local problem="$2"
    local tmp="${puml%.puml}.fixed.puml"

    echo "  → Attempting to fix aspect ratio (${problem})..." >&2
    cp "$puml" "$tmp"

    if grep -q '!pragma aspectRatioFixed' "$puml" 2>/dev/null; then
        echo "  → Already auto-fixed; skipping further attempts" >&2
        rm -f "$tmp"
        echo ""
        return 1
    fi

    # Inject pragma and spacing guards right after @startuml so they take effect early
    sed -i '1s/^@startuml/@startuml\n!pragma aspectRatioFixed/' "$tmp"

    local spacing_tmp="${tmp}.spacing"
    printf '%s\n' "$SPACING_GUARD_CSS" > "$spacing_tmp"
    printf '%s\n' "$SPACING_GUARD_SKINPARAMS" >> "$spacing_tmp"
    sed -i '/!pragma aspectRatioFixed/r '"$spacing_tmp" "$tmp"
    rm -f "$spacing_tmp"
    echo "  → Applied: spacing guards (CSS padding/wrapWidth/MinimumWidth + skinparam NodeSep/RankSep)" >&2

    # Direction directives help class/usecase/component diagrams, but they can
    # break activity diagrams (after start/stop), are redundant for sequence
    # diagrams, and often make complex state diagrams worse.  Only inject them
    # when the source looks safe.
    local is_activity is_sequence is_state
    is_activity=false
    is_sequence=false
    is_state=false
    if grep -qE '^[[:space:]]*(start|stop)[[:space:]]*$' "$tmp" || \
       grep -qE '^[[:space:]]*:[^;]+;' "$tmp"; then
        is_activity=true
    fi
    if grep -qE '^[[:space:]]*participant[[:space:]]' "$tmp"; then
        is_sequence=true
    fi
    if grep -qE '^[[:space:]]*state[[:space:]]' "$tmp"; then
        is_state=true
    fi

    if [[ "$problem" == "too_tall" ]]; then
        sed -i '/top to bottom direction/d' "$tmp"
        if ! $is_activity && ! $is_sequence && ! $is_state && ! grep -q 'left to right direction' "$tmp"; then
            if grep -q '^@enduml' "$tmp"; then
                sed -i '/^@enduml/i\left to right direction' "$tmp"
            else
                echo "left to right direction" >> "$tmp"
            fi
            echo "  → Applied: left to right direction" >&2
        fi
    else
        sed -i '/left to right direction/d' "$tmp"
        if ! $is_activity && ! $is_sequence && ! $is_state && ! grep -q 'top to bottom direction' "$tmp"; then
            if grep -q '^@enduml' "$tmp"; then
                sed -i '/^@enduml/i\top to bottom direction' "$tmp"
            else
                echo "top to bottom direction" >> "$tmp"
            fi
            echo "  → Applied: top to bottom direction" >&2
        fi
    fi

    echo "$tmp"
    return 0
}

# Dark-mode post-processing
# PlantUML's 'monochrome true' overrides most explicit font/border skinparams,
# so the most reliable dark variant is produced by post-processing the already
# rendered light image rather than re-rendering a recoloured .puml.

# postprocess_svg_bare_strokes — Add CSS stroke rules for elements PlantUML renders
# without stroke attributes (common with CSS <style> blocks + skinparam style strictuml).
# Arguments: $1=svg_path
# This ensures use case ellipses, actor paths, and component rects are visible.
postprocess_svg_bare_strokes() {
    local svg="$1"
    local css_file
    css_file=$(mktemp /tmp/bare-strokes-XXXXXX.css)
    cat > "$css_file" <<'CSSBLOCK'
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
CSSBLOCK
    perl -pe "BEGIN { open(F,'<','$css_file'); \$css=join('',<F>); close(F); chomp \$css } if (/^<svg/ && !\$done) { s/(<svg[^>]*>)/\$1\n\$css/; \$done=1 }" "$svg" > "$svg.tmp" && mv "$svg.tmp" "$svg"
    rm -f "$css_file"
}

# postprocess_dark_svg — Inject CSS-based dark mode into SVG
# Arguments: $1=light_svg_path, $2=dark_svg_path
# Uses @media (prefers-color-scheme: dark) CSS block for automatic theme switching.
# This approach is CSS-first (aligning with the skill's styling preference) and
# automatically adapts to the user's system theme without requiring separate files.
postprocess_dark_svg() {
    local light="$1"
    local dark="$2"

    # CSS dark mode block — injected after opening <svg> tag
    # Color palette matches the reference examples (GitHub dark theme inspired):
    #   - Canvas: #1e1e2e (subtle dark surface)
    #   - Text/strokes: #c9d1d9 (light ink)
    #   - Bold text: #f0f6fc (brighter for emphasis)
    #   - Lifelines: #6e7681 (subtle dashed gray)
    local dark_css_file
    dark_css_file=$(mktemp /tmp/dark-css-XXXXXX.css)
    cat > "$dark_css_file" <<'CSSBLOCK'
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
CSSBLOCK

    # Inject CSS block after opening <svg> tag using perl (handles single-line SVGs)
    perl -pe "BEGIN { open(F,'<','$dark_css_file'); \$css=join('',<F>); close(F); chomp \$css } if (/^<svg/ && !\$done) { s/(<svg[^>]*>)/\$1\n\$css/; \$done=1 }" "$light" > "$dark"
    rm -f "$dark_css_file"
}

# postprocess_dark_png — Recolor a light PNG into a dark-themed PNG
# Arguments: $1=light_png_path, $2=dark_png_path
# Requires ImageMagick (convert/identify). This is a best-effort recolour;
# anti-aliased edges may retain a slight halo. SVG dark mode is preferred.
postprocess_dark_png() {
    local light="$1"
    local dark="$2"

    if ! command -v convert &>/dev/null; then
        return 1
    fi

    # Map colours in an order that preserves contrast.  Dark greys replace
    # light fills first; text/stroke colours are replaced last so they remain
    # visible on the new fills.
    convert "$light" \
        -fuzz 25% -fill '#1A1A1A' -opaque '#FFFFFF' \
        -fuzz 25% -fill '#2D2D2D' -opaque '#FAFAFA' \
        -fuzz 25% -fill '#2D2D2D' -opaque '#F1F1F1' \
        -fuzz 25% -fill '#2D2D2D' -opaque '#F2F2F2' \
        -fuzz 25% -fill '#C0C0C0' -opaque '#222222' \
        -fuzz 25% -fill '#C0C0C0' -opaque '#181818' \
        -fuzz 25% -fill '#E8E8E8' -opaque '#000000' \
        "$dark"
}

# ═══════════════════════════════════════════════════════════════════════════════
# A4 Paper Fit Validation & Auto-Scale Fix
# ═══════════════════════════════════════════════════════════════════════════════
#
# Checks the rendered diagram against A4 paper dimensions (210×297 mm).
# PlantUML output is measured in SVG pixels at 96 DPI (the CSS standard);
# 1 in = 96 px, A4 = 210×297 mm = 8.27×11.69 in ⇒ 794×1123 px (portrait),
# 1123×794 px (landscape). The script accepts the diagram if it fits in
# EITHER orientation without overflowing.
#
# If the diagram exceeds A4 in BOTH dimensions, it applies a PlantUML "scale"
# directive computed from the smaller of the two required scale factors, then
# re-renders. After re-rendering it also estimates the effective on-paper font
# size: scale × DEFAULT_FONT_PX ÷ (96/72) = scale × DEFAULT_FONT_PX × 0.75,
# i.e. px-to-pt ratio. If the effective pt is below --min-font-pt, the diagram
# can no longer be made readable by scaling alone and the user is warned.

# check_a4_fit — Validate image fits within A4 portrait OR landscape
# Arguments: $1=image_file, $2=format (svg|png)
# Sets global: A4_SCALE_FACTOR (1.0 if already fits; otherwise required factor)
# Returns: 0 if fits A4, 1 if needs scaling, 2 if check failed
check_a4_fit() {
    local img="$1"
    local fmt="$2"
    local w h

    case "$fmt" in
        svg)
            get_svg_dimensions "$img" || return 2
            w="$SVG_WIDTH"
            h="$SVG_HEIGHT"
            ;;
        png)
            get_png_dimensions "$img" || return 2
            w="$PNG_WIDTH"
            h="$PNG_HEIGHT"
            ;;
        *) return 2 ;;
    esac

    if [[ -z "$w" ]] || [[ -z "$h" ]] || [[ "$w" -le 0 ]] || [[ "$h" -le 0 ]]; then
        return 2
    fi

    A4_SCALE_FACTOR="1.0"

    local fits_portrait fits_landscape
    awk "BEGIN {exit !($w <= $A4_PORTRAIT_W && $h <= $A4_PORTRAIT_H)}" 2>/dev/null && fits_portrait=1 || fits_portrait=0
    awk "BEGIN {exit !($w <= $A4_LANDSCAPE_W && $h <= $A4_LANDSCAPE_H)}" 2>/dev/null && fits_landscape=1 || fits_landscape=0

    if [[ "$fits_portrait" -eq 1 ]] || [[ "$fits_landscape" -eq 1 ]]; then
        echo "  📄 A4 fit: ${w}x${h}px fits A4 portrait (794x1123) or landscape (1123x794) ✓"
        return 0
    fi

    # scale = min(target_w / w, target_h / h); compute for each orientation
    local sp sl
    sp=$(awk "BEGIN {p1=($A4_PORTRAIT_W / $w); p2=($A4_PORTRAIT_H / $h); s=(p1<p2)?p1:p2; printf \"%.3f\", s}" 2>/dev/null || echo "")
    sl=$(awk "BEGIN {l1=($A4_LANDSCAPE_W / $w); l2=($A4_LANDSCAPE_H / $h); s=(l1<l2)?l1:l2; printf \"%.3f\", s}" 2>/dev/null || echo "")

    if [[ -z "$sp" ]] || [[ -z "$sl" ]]; then
        echo "  ⚠ A4 fit: could not compute scale factor (awk failed); skipping"
        return 2
    fi

    # Use the orientation that needs less shrinking (the higher of the two factors)
    A4_SCALE_FACTOR=$(awk "BEGIN {printf \"%.3f\", ($sp > $sl) ? $sp : $sl}" 2>/dev/null)

    # Clamp: never go below 0.15 — beyond that the diagram is unreadable
    local clamped
    clamped=$(awk "BEGIN {printf \"%.3f\", ($A4_SCALE_FACTOR < 0.15) ? 0.15 : $A4_SCALE_FACTOR}" 2>/dev/null)
    A4_SCALE_FACTOR="$clamped"

    echo "  📄 A4 fit: ${w}x${h}px exceeds A4 portrait (794x1123) and landscape (1123x794)"
    echo "     Required scale to fit: ${A4_SCALE_FACTOR} (portrait factor ${sp}, landscape factor ${sl})"
    return 1
}

# fix_puml_a4_fit — Insert a PlantUML scale directive into a .puml copy
# Arguments: $1=puml_file
# Uses global A4_SCALE_FACTOR set by check_a4_fit
# Returns: path to modified .puml on stdout, empty string on failure.
# stdout must stay clean because callers capture it via $(...); logs go to stderr.
fix_puml_a4_fit() {
    local puml="$1"
    local tmp="${puml%.puml}.a4fixed.puml"

    if [[ -z "$A4_SCALE_FACTOR" ]] || [[ "$A4_SCALE_FACTOR" == "1.0" ]]; then
        echo ""
        return 1
    fi
    if grep -q '!pragma a4FitFixed' "$puml" 2>/dev/null; then
        echo ""
        return 1
    fi

    cp "$puml" "$tmp"
    sed -i '1s/^@startuml/@startuml\n!pragma a4FitFixed/' "$tmp"

    # PlantUML uses only one scale directive per diagram; remove any existing
    # scale line (including the aspect-ratio auto-fix's scale 0.9) so the A4
    # scale is the one that takes effect.
    sed -i '/^[[:space:]]*scale[[:space:]]/d' "$tmp"

    sed -i "/!pragma a4FitFixed/a scale ${A4_SCALE_FACTOR}" "$tmp"
    echo "  → Applied: scale ${A4_SCALE_FACTOR} (A4 fit)" >&2

    # Warn about font legibility on A4 if we shrunk a lot
    local effective_pt
    effective_pt=$(awk "BEGIN {printf \"%.1f\", $A4_SCALE_FACTOR * $DEFAULT_FONT_PX * 0.75}" 2>/dev/null)
    if [[ -n "$effective_pt" ]]; then
        if awk "BEGIN {exit !($effective_pt < $MIN_FONT_PT)}" 2>/dev/null; then
            echo "  ⚠ After scaling to ${A4_SCALE_FACTOR}, estimated font ≈ ${effective_pt}pt on A4" >&2
            echo "    That is below --min-font-pt ${MIN_FONT_PT} and may be hard to read in print." >&2
            echo "    Consider splitting into multiple diagrams or abbreviating labels." >&2
        else
            echo "     Estimated font ≈ ${effective_pt}pt on A4 (≥ min ${MIN_FONT_PT}pt) ✓" >&2
        fi
    fi

    echo "$tmp"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Rendering Backends
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Method 3: Kroki Public Server (OPT-IN ONLY) ────────────────────────────
# DISABLED BY DEFAULT for privacy. Only invoked when the user explicitly passes
# --use-public-server. This backend POSTs the entire diagram source to Kroki
# (kroki.io by default, overridable via PLANTUML_PUBLIC_SERVER) — never use it
# for confidential architecture, credentials, or proprietary business
# processes. Kroki is open source and self-hostable.
convert_via_server() {
    local src="$1"

    if ! $USE_PUBLIC_SERVER; then
        echo "  → Public server disabled (privacy default). Pass --use-public-server to enable."
        return 1
    fi

    local server_host="${PLANTUML_PUBLIC_SERVER:-https://kroki.io}"
    server_host="${server_host%/}"
    local server_url="${server_host}/plantuml/${FORMAT}"

    if ! command -v curl &>/dev/null; then
        echo "  → curl not available, skipping public server"
        return 1
    fi

    local host_label
    host_label=$(echo "$server_host" | sed -E 's|^https?://||; s|/.*$||')

    echo ""
    echo "  ⚠  PRIVACY WARNING: about to upload diagram source to ${server_url}"
    echo "     The full contents of '$src' will be transmitted to ${host_label}."
    if [[ "$server_host" == "https://kroki.io" ]]; then
        echo "     kroki.io is operated by Yuzu Tech (EU). Kroki is open source and"
        echo "     self-hostable — set PLANTUML_PUBLIC_SERVER=<your-url> to use your own."
    else
        echo "     (Custom backend selected via PLANTUML_PUBLIC_SERVER.)"
    fi
    echo "     Do NOT use this backend for confidential architecture, credentials,"
    echo "     customer data, or proprietary business logic."
    echo ""
    echo "  → Trying public server (opt-in via --use-public-server)..."
    if curl -sSfL --connect-timeout 10 --max-time 60 \
            -H "Content-Type: text/plain" \
            -o "$OUTPUT_FILE" -X POST "$server_url" --data-binary "@$src" 2>/dev/null; then
        if [[ "$FORMAT" == "svg" ]] && [[ -s "$OUTPUT_FILE" ]] && grep -q '<svg' "$OUTPUT_FILE"; then
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
    echo "  ✗ Public server failed — check network or try Docker/local JAR backend"
    return 1
}

# ─── Method 1: Docker (PREFERRED — fully local) ─────────────────────────────
# Always tried first. Renders entirely on-host with no third-party network calls.
convert_via_docker() {
    local src="$1"
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
    cp "$src" "$docker_tmp/"

    # On Windows Git-Bash/MSYS the path passed to `docker -v` must be converted.
    local docker_mount="$docker_tmp"
    if command -v cygpath &>/dev/null; then
        docker_mount=$(cygpath -w "$docker_tmp")
    elif command -v wslpath &>/dev/null; then
        docker_mount=$(wslpath -w "$docker_tmp" 2>/dev/null || echo "$docker_tmp")
    fi

    # CJK font support: mount host font directories into container
    if $CJK; then
        local font_mounts=()
        # Linux/macOS font paths
        for font_dir in /usr/share/fonts /usr/local/share/fonts /System/Library/Fonts; do
            [[ -d "$font_dir" ]] && font_mounts+=(-v "${font_dir}:${font_dir}:ro")
        done
        # Windows font paths (Git Bash/MSYS: /c/Windows/Fonts, WSL: /mnt/c/Windows/Fonts)
        for win_fonts in /c/Windows/Fonts /mnt/c/Windows/Fonts; do
            [[ -d "$win_fonts" ]] && font_mounts+=(-v "${win_fonts}:/Windows/Fonts:ro")
        done

        if [[ ${#font_mounts[@]} -gt 0 ]]; then
            if MSYS_NO_PATHCONV=1 docker run --rm \
                -v "${docker_mount}:/data" \
                "${font_mounts[@]}" \
                --entrypoint sh plantuml/plantuml:latest \
                -c "fc-cache -f 2>/dev/null; plantuml -t${ext} /data/$(basename "$src")" 2>/dev/null; then
                local generated
                local src_basename
                src_basename=$(basename "$src" .puml)
                generated=$(ls "$docker_tmp"/"${src_basename}"."$ext" 2>/dev/null || ls "$docker_tmp"/"${src_basename}"."$FORMAT" 2>/dev/null || echo "")
                [[ -n "$generated" ]] && mv "$generated" "$OUTPUT_FILE"
                rm -rf "$docker_tmp"
                echo "  ✓ Success (Docker + CJK)"
                return 0
            fi
        else
            echo "  ⚠ CJK mode: no host font directories found. CJK characters may not render correctly."
            echo "    Install CJK fonts on your system (e.g., 'apt install fonts-wqy-zenhei')"
        fi
    fi

    # Standard Docker rendering
    if MSYS_NO_PATHCONV=1 docker run --rm -v "${docker_mount}:/data" plantuml/plantuml:latest \
        "-t${ext}" "/data/$(basename "$src")" 2>/dev/null; then

        local generated
        local src_basename
        src_basename=$(basename "$src" .puml)
        generated=$(ls "$docker_tmp"/"${src_basename}"."$ext" 2>/dev/null || ls "$docker_tmp"/"${src_basename}"."$FORMAT" 2>/dev/null || echo "")
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

# ─── Method 2: Local JAR (offline fallback) ─────────────────────────────────
convert_via_local() {
    local src="$1"
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

    # PlantUML places output relative to the source file's directory, so render
    # from a temporary directory to know exactly where the generated file lands.
    local local_tmp="${PORTABLE_TMP}/plantuml_local_$$"
    mkdir -p "$local_tmp"
    cp "$src" "$local_tmp/"

    local src_basename
    src_basename=$(basename "$src" .puml)
    src_basename="${src_basename%.plantuml}"
    src_basename="${src_basename%.txt}"

    if java -jar "$jar" "-t${ext}" "$local_tmp/${src_basename}.puml" 2>/dev/null; then
        local generated
        generated=$(ls "$local_tmp"/${src_basename}."$ext" 2>/dev/null || ls "$local_tmp"/${src_basename}."$FORMAT" 2>/dev/null || echo "")
        if [[ -n "$generated" ]]; then
            mv "$generated" "$OUTPUT_FILE"
            rm -rf "$local_tmp"
            echo "  ✓ Success (local JAR)"
            return 0
        fi
    fi
    rm -rf "$local_tmp"
    echo "  ✗ Local JAR failed"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════════

# ── CJK Detection ────────────────────────────────────────────────────────────
if ! $CJK; then
    if detect_cjk "$INPUT"; then
        echo ""
        echo "🔤 CJK (Chinese/Japanese/Korean) characters detected in input."
        echo "   These may not render correctly without CJK font support."
        echo "   Re-run with --cjk to enable CJK rendering, or install CJK fonts."
        echo "   Attempting to proceed anyway..."
        echo ""
    fi
fi

# ── Prepare working copy ─────────────────────────────────────────────────────
WORK_COPY="$INPUT"
CJK_COPY=""
if $CJK; then
    echo "🔤 CJK mode enabled: configuring CJK-compatible fonts"
    CJK_COPY=$(prepare_puml_for_cjk "$INPUT")
    WORK_COPY="$CJK_COPY"
fi

# ── Render ───────────────────────────────────────────────────────────────────
RENDER_OK=false
MAX_FIX_ATTEMPTS=3
FIX_ATTEMPT=0
ASPECT_DONE=false
A4_TRIED=false

while [[ "$FIX_ATTEMPT" -le "$MAX_FIX_ATTEMPTS" ]]; do
    convert_via_docker "$WORK_COPY" || convert_via_local "$WORK_COPY" || convert_via_server "$WORK_COPY" || {
        if $RENDER_OK && [[ -f "$OUTPUT_FILE" ]]; then
            echo "  ⚠ Re-render failed; keeping the last successful output"
            break
        fi
        echo ""
        echo "❌ All conversion methods failed."
        echo "   Install options (local, recommended for privacy):"
        echo "   1. Docker: docker pull plantuml/plantuml:latest"
        echo "   2. Java + JAR: download plantuml.jar from https://plantuml.com/download"
        echo "   Or, to use the public Kroki server (uploads diagram to kroki.io):"
        echo "   3. Re-run with --use-public-server (review the privacy notice first)"
        echo "      Override the host with PLANTUML_PUBLIC_SERVER=<url> if self-hosting"
        [[ -n "$CJK_COPY" ]] && rm -f "$CJK_COPY"
        exit 1
    }
    RENDER_OK=true

    if [[ "$FORMAT" == "txt" ]] || [[ "$FORMAT" == "pdf" ]]; then
        break
    fi

    if $AUTO_FIX && ! $ASPECT_DONE; then
        aspect_rc=2
        CHECKED_ASPECT_PROBLEM="ok"
        check_aspect_ratio "$OUTPUT_FILE" "$FORMAT" && aspect_rc=0 || aspect_rc=$?

        if [[ "$aspect_rc" -eq 2 ]]; then
            echo "  ⓘ Could not determine image dimensions; skipping aspect ratio check."
            ASPECT_DONE=true
        elif [[ "$aspect_rc" -eq 1 ]]; then
            FIX_ATTEMPT=$((FIX_ATTEMPT + 1))
            if [[ "$FIX_ATTEMPT" -gt "$MAX_FIX_ATTEMPTS" ]]; then
                echo "  ⚠ Maximum fix attempts ($MAX_FIX_ATTEMPTS) reached. Manual adjustment may be needed."
                ASPECT_DONE=true
            else
                aspect_fixed=$(fix_puml_aspect_ratio "$WORK_COPY" "$CHECKED_ASPECT_PROBLEM") || {
                    echo "  ✗ Auto-fix step failed; keeping current output." >&2
                    ASPECT_DONE=true
                    break
                }

                if [[ "$WORK_COPY" != "$INPUT" ]]; then
                    rm -f "$WORK_COPY"
                fi
                WORK_COPY="$aspect_fixed"
                echo "  → Re-rendering with corrected layout..."
                continue
            fi
        fi
        ASPECT_DONE=true
    fi

    if $A4_CHECK && ! $A4_TRIED; then
        a4_rc=2
        check_a4_fit "$OUTPUT_FILE" "$FORMAT" && a4_rc=0 || a4_rc=$?

        if [[ "$a4_rc" -eq 2 ]]; then
            echo "  ⓘ Could not determine image dimensions; skipping A4 check."
            break
        elif [[ "$a4_rc" -eq 1 ]]; then
            FIX_ATTEMPT=$((FIX_ATTEMPT + 1))
            if [[ "$FIX_ATTEMPT" -gt "$MAX_FIX_ATTEMPTS" ]]; then
                echo "  ⚠ Maximum fix attempts ($MAX_FIX_ATTEMPTS) reached; A4 fit may not hold."
                break
            fi

            a4_fixed=$(fix_puml_a4_fit "$WORK_COPY") || {
                echo "  ✗ A4 auto-fit failed; using current diagram."
                break
            }

            if [[ -z "$a4_fixed" ]]; then
                echo "  ✗ A4 auto-fit produced no output; using current diagram."
                A4_TRIED=true
                break
            fi

            if [[ "$WORK_COPY" != "$INPUT" ]]; then
                rm -f "$WORK_COPY"
            fi
            WORK_COPY="$a4_fixed"
            A4_TRIED=true
            echo "  → Re-rendering with A4-fit scale..."
            continue
        fi
    fi

    break
done

# ── Fix bare strokes in light SVG (CSS mode may omit strokes on some shapes) ──
if $RENDER_OK && [[ "$FORMAT" == "svg" ]]; then
    postprocess_svg_bare_strokes "$OUTPUT_FILE"
fi

# ── Dark-mode variant (opt-in) ───────────────────────────────────────────────
DARK_OUTPUT_FILE=""
if $DARK_MODE && $RENDER_OK; then
    DARK_OUTPUT_FILE="${OUTPUT_DIR}/${INPUT_BASENAME}.dark.${FORMAT}"
    echo ""
    echo "🌙 Dark-mode variant requested: $DARK_OUTPUT_FILE"

    if [[ "$FORMAT" == "svg" ]]; then
        postprocess_dark_svg "$OUTPUT_FILE" "$DARK_OUTPUT_FILE"
        echo "  ✓ Dark-mode SVG generated"
    elif [[ "$FORMAT" == "png" ]]; then
        if postprocess_dark_png "$OUTPUT_FILE" "$DARK_OUTPUT_FILE"; then
            echo "  ✓ Dark-mode PNG generated"
        else
            echo "  ⚠ Dark-mode PNG requires ImageMagick (convert); dark variant skipped"
            DARK_OUTPUT_FILE=""
        fi
    else
        echo "  ⚠ Dark-mode is only supported for svg and png output; skipping"
        DARK_OUTPUT_FILE=""
    fi
fi

# ── Cleanup temp files ───────────────────────────────────────────────────────
if [[ "$WORK_COPY" != "$INPUT" ]]; then
    rm -f "$WORK_COPY"
fi
[[ -n "$CJK_COPY" ]] && [[ "$CJK_COPY" != "$WORK_COPY" ]] && rm -f "$CJK_COPY"

# ── Report ───────────────────────────────────────────────────────────────────
if $RENDER_OK; then
    echo ""
    echo "✅ Output: $OUTPUT_FILE"
    echo "$OUTPUT_FILE"
    if [[ -n "$DARK_OUTPUT_FILE" ]] && [[ -f "$DARK_OUTPUT_FILE" ]]; then
        echo "🌙 Dark: $DARK_OUTPUT_FILE"
        echo "$DARK_OUTPUT_FILE"
    fi
fi
