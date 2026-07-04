# Release Process

This document describes how to release a new version of plantuml-skill to GitHub and ClawHub.

## Prerequisites

1. **GitHub CLI** (`gh`) — authenticated with `gh auth login`
2. **ClawHub CLI** (`clawhub`) — authenticated with `clawhub login --token <token>`
3. **All changes committed** — working tree must be clean

## Quick Release

Use the automated release script:

```bash
./release.sh <version>

# Example:
./release.sh 1.5.0

# Preview changes without publishing:
./release.sh 1.6.0 --dry-run
```

The script will:
1. Validate version format (X.Y.Z or X.Y.Z-tag)
2. Update version references in README.md, README.zh-CN.md, SKILL.md
3. Commit and push version changes
4. Build a release archive (`plantuml-skill-v<version>.tar.gz`)
5. Create a GitHub release with the archive attached
6. Publish to ClawHub

## Manual Release Steps

If you need to release manually:

### 1. Update Version References

Update version badges and references in:
- `README.md` — version badge (line ~10)
- `README.zh-CN.md` — version badge (line ~10)
- `SKILL.md` — `version:` field
- Both READMEs — "Why Kroki (vX.Y.Z)" section headers

### 2. Commit and Push

```bash
git add README.md README.zh-CN.md SKILL.md
git commit -m "chore: bump version to vX.Y.Z"
git push origin main
```

### 3. Create Release Archive

```bash
tar -czf plantuml-skill-vX.Y.Z.tar.gz \
  skills/plantuml/ \
  examples/*.puml \
  examples/*.svg \
  README.md \
  README.zh-CN.md \
  LICENSE
```

### 4. Create GitHub Release

```bash
# Create tag
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z

# Create release with archive
gh release create vX.Y.Z \
  --title "vX.Y.Z" \
  --notes "Release vX.Y.Z" \
  plantuml-skill-vX.Y.Z.tar.gz
```

### 5. Publish to ClawHub

```bash
clawhub skill publish skills/plantuml \
  --slug plantuml-skill \
  --version X.Y.Z \
  --source-repo samonysh/plantuml-skill \
  --source-commit $(git rev-parse HEAD) \
  --changelog "Release vX.Y.Z"
```

## ClawHub API Key

The ClawHub API key is stored locally. To login:

```bash
clawhub login --token clh_<your-token>
```

To verify authentication:

```bash
clawhub whoami
```

## Versioning

We follow [Semantic Versioning](https://semver.org/):

- **Major** (X.0.0) — Breaking changes to the SKILL.md contract or render script flags
- **Minor** (0.X.0) — New features, new diagram types, new flags
- **Patch** (0.0.X) — Bug fixes, documentation updates, example regenerations

Pre-release versions (e.g., `1.6.0-beta.1`) are supported.

## Checklist

Before releasing, verify:

- [ ] All examples render correctly (run `./examples/regenerate-all.sh`)
- [ ] Both Bash and PowerShell scripts work (test on both platforms if possible)
- [ ] SKILL.md documentation matches actual behavior
- [ ] README.md and README.zh-CN.md are in sync
- [ ] Dark mode SVGs have correct palette (#1A1A1A, #2D2D2D, #E8E8E8, #C0C0C0)
- [ ] Aspect ratios are within [0.7, 1.4] band (or warned if outside)
- [ ] No temporary files in the archive (plantuml.jar, .omo/, etc.)

## Troubleshooting

### ClawHub publish fails with "unauthorized"

```bash
clawhub login --token clh_<your-token>
```

### GitHub release fails

```bash
gh auth status
gh auth login
```

### Archive too large

The archive should be ~100KB. If it's much larger, check for accidentally included files:
- `plantuml.jar` (~5MB) — should be in .gitignore
- `.omo/` directory — should be in .gitignore
- `output/` directory — should be in .gitignore
