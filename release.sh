#!/usr/bin/env bash
# release.sh — Automated release script for plantuml-skill
# Usage: ./release.sh <version> [--dry-run]
#
# Prerequisites:
#   - gh CLI authenticated (gh auth login)
#   - clawhub CLI authenticated (clawhub login --token <token>)
#   - All changes committed and pushed
#
# This script:
#   1. Validates the version format
#   2. Updates version references in README.md, README.zh-CN.md, SKILL.md
#   3. Creates a git tag
#   4. Creates a GitHub release with release notes
#   5. Builds and uploads a release archive (tar.gz)
#   6. Publishes to ClawHub

set -euo pipefail

# --- Configuration ---
REPO="samonysh/plantuml-skill"
SKILL_DIR="skills/plantuml"
ARCHIVE_NAME="plantuml-skill"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Functions ---
log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") <version> [--dry-run]

Release plantuml-skill to GitHub and ClawHub.

Arguments:
  version    Version string (e.g., 1.5.0, 1.6.0-beta.1)
  --dry-run  Preview changes without publishing

Examples:
  $(basename "$0") 1.5.0
  $(basename "$0") 1.6.0-beta.1 --dry-run
EOF
    exit 1
}

validate_version() {
    local ver="$1"
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        error "Invalid version format: $ver"
        error "Expected: X.Y.Z or X.Y.Z-tag (e.g., 1.5.0, 1.6.0-beta.1)"
        exit 1
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v gh &>/dev/null; then
        error "gh CLI not found. Install: https://cli.github.com/"
        exit 1
    fi
    
    if ! command -v clawhub &>/dev/null; then
        error "clawhub CLI not found. Install: npm i -g clawhub"
        exit 1
    fi
    
    if ! gh auth status &>/dev/null; then
        error "gh not authenticated. Run: gh auth login"
        exit 1
    fi
    
    if ! clawhub whoami &>/dev/null; then
        error "clawhub not authenticated. Run: clawhub login --token <token>"
        exit 1
    fi
    
    # Check for uncommitted changes
    if [[ -n "$(git status --porcelain)" ]]; then
        error "Working tree has uncommitted changes. Commit or stash first."
        exit 1
    fi
    
    log "Prerequisites OK."
}

update_version_refs() {
    local version="$1"
    local dry_run="$2"
    
    log "Updating version references to v${version}..."
    
    # README.md — version badge
    if grep -q 'version-v[0-9]' README.md; then
        if [[ "$dry_run" == "true" ]]; then
            log "[dry-run] Would update README.md version badge"
        else
            sed -i "s/version-v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/version-v${version}/g" README.md
        fi
    fi
    
    # README.zh-CN.md — version badge
    if grep -q 'version-v[0-9]' README.zh-CN.md; then
        if [[ "$dry_run" == "true" ]]; then
            log "[dry-run] Would update README.zh-CN.md version badge"
        else
            sed -i "s/version-v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/version-v${version}/g" README.zh-CN.md
        fi
    fi
    
    # SKILL.md — version line
    if grep -q '^version:' SKILL.md; then
        if [[ "$dry_run" == "true" ]]; then
            log "[dry-run] Would update SKILL.md version"
        else
            sed -i "s/^version: .*/version: ${version}/" SKILL.md
        fi
    fi
    
    # "Why Kroki" section version references
    for f in README.md README.zh-CN.md; do
        if grep -q 'Why Kroki (v[0-9]' "$f"; then
            if [[ "$dry_run" == "true" ]]; then
                log "[dry-run] Would update $f 'Why Kroki' version"
            else
                sed -i "s/Why Kroki (v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*)/Why Kroki (v${version})/g" "$f"
            fi
        fi
    done
}

build_archive() {
    local version="$1"
    local archive="${ARCHIVE_NAME}-v${version}.tar.gz"
    
    log "Building release archive: ${archive}"
    
    tar -czf "$archive" \
        "$SKILL_DIR/" \
        examples/*.puml \
        examples/*.svg \
        README.md \
        README.zh-CN.md \
        LICENSE 2>/dev/null || \
    tar -czf "$archive" \
        "$SKILL_DIR/" \
        examples/*.puml \
        examples/*.svg \
        README.md \
        README.zh-CN.md
    
    log "Archive size: $(du -h "$archive" | cut -f1)"
}

create_github_release() {
    local version="$1"
    local archive="${ARCHIVE_NAME}-v${version}.tar.gz"
    local dry_run="$2"
    
    log "Creating GitHub release v${version}..."
    
    # Generate release notes from SKILL.md changelog or use default
    local notes
    notes=$(cat <<EOF
## v${version}

See [CHANGELOG](https://github.com/${REPO}/blob/main/CHANGELOG.md) for details.

### Installation

\`\`\`bash
# Via skills.sh
npx skills add ${REPO}

# Via ClawHub
openclaw skills install plantuml-skill

# Manual
git clone https://github.com/${REPO}.git
cp -r plantuml-skill/${SKILL_DIR} ~/.config/opencode/skills/
\`\`\`
EOF
)
    
    if [[ "$dry_run" == "true" ]]; then
        log "[dry-run] Would create GitHub release v${version}"
        log "[dry-run] Would upload ${archive}"
    else
        # Create tag if it doesn't exist
        if ! git rev-parse "v${version}" &>/dev/null; then
            git tag -a "v${version}" -m "Release v${version}"
            git push origin "v${version}"
        fi
        
        # Create release
        gh release create "v${version}" \
            --title "v${version}" \
            --notes "$notes" \
            "$archive"
        
        log "GitHub release created: https://github.com/${REPO}/releases/tag/v${version}"
    fi
}

publish_clawhub() {
    local version="$1"
    local dry_run="$2"
    
    log "Publishing to ClawHub as plantuml-skill@${version}..."
    
    local commit_sha
    commit_sha=$(git rev-parse HEAD)
    
    if [[ "$dry_run" == "true" ]]; then
        log "[dry-run] Would publish ${SKILL_DIR} as plantuml-skill@${version}"
    else
        clawhub skill publish "$SKILL_DIR" \
            --slug plantuml-skill \
            --version "$version" \
            --source-repo "$REPO" \
            --source-commit "$commit_sha" \
            --changelog "Release v${version}"
        
        log "ClawHub published: https://clawhub.ai/samonysh/plantuml-skill"
    fi
}

# --- Main ---
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi
    
    local version=""
    local dry_run="false"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                if [[ -z "$version" ]]; then
                    version="$1"
                else
                    error "Unknown argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$version" ]]; then
        error "Version argument required"
        usage
    fi
    
    validate_version "$version"
    check_prerequisites
    
    log "Starting release v${version} (dry-run: ${dry_run})"
    echo "---"
    
    update_version_refs "$version" "$dry_run"
    
    if [[ "$dry_run" == "false" ]]; then
        # Commit version changes
        git add README.md README.zh-CN.md SKILL.md
        git commit -m "chore: bump version to v${version}" || true
        git push origin main
    fi
    
    build_archive "$version"
    create_github_release "$version" "$dry_run"
    publish_clawhub "$version" "$dry_run"
    
    echo "---"
    log "Release v${version} complete!"
    log "  GitHub: https://github.com/${REPO}/releases/tag/v${version}"
    log "  ClawHub: https://clawhub.ai/samonysh/plantuml-skill"
}

main "$@"
