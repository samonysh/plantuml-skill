# Release Process

This document describes how to release a new version of plantuml-skill to GitHub
and ClawHub using the unified Python release manager `scripts/release.py`.

## Prerequisites

1. **Python 3.8+** - the release manager is a single stdlib-only script
2. **Git** - with the main branch (`main` by default) as the working branch
3. **GitHub CLI** (`gh`) - authenticated via `gh auth login`
4. **ClawHub CLI** (`clawhub`) - authenticated via `clawhub login --token <token>`
   (only required for the `clawhub-publish` / `all` steps)
5. **All changes committed** - the preflight `check` step reports a clean tree
   before any push/release

## Configuration

All knobs are environment variables with sensible defaults. See
[scripts/.env.example](scripts/.env.example) for the full list. Either export
them in your shell or copy the file to `.env` (which is gitignored) and source
it before running the script.

| Variable | Default | Purpose |
|---|---|---|
| `PLANTUML_RELEASE_GH_REPO` | `samonysh/plantuml-skill` | GitHub repo for `gh release` + clawhub `--source-repo` |
| `PLANTUML_RELEASE_MAIN_BRANCH` | `main` | Branch to push version-bump commits to |
| `PLANTUML_RELEASE_REMOTE` | `origin` | Git remote to push to |
| `PLANTUML_RELEASE_CLAWHUB_SLUG` | `plantuml-skill` | ClawHub skill slug |
| `PLANTUML_RELEASE_ARCHIVE_NAME` | `plantuml-skill` | Archive base name (`<name>-v<version>.tar.gz`) |
| `PLANTUML_RELEASE_DIST_DIR` | `dist` | Where built archives land |

Tokens are **never** stored in `.env`. Rely on the CLIs' own auth
(`gh auth login`, `clawhub login`) or their standard env vars (`GH_TOKEN`).

## Quick Release

```bash
# Full release (check -> bump -> build -> push -> gh release -> clawhub publish)
python scripts/release.py 1.7.1

# Preview everything without side effects
python scripts/release.py 1.8.0-beta.1 --dry-run

# Run a single step
python scripts/release.py 1.7.1 --step check
python scripts/release.py 1.7.1 --step build
python scripts/release.py 1.7.1 --step push
python scripts/release.py 1.7.1 --step gh-release
python scripts/release.py 1.7.1 --step clawhub-publish

# Full release but skip the ClawHub step (e.g. ClawHub is down)
python scripts/release.py 1.7.1 --skip-clawhub
```

## What each step does

### 1. `check` (preflight)

- Validates the version format (`X.Y.Z` or `X.Y.Z-tag`)
- Cross-checks version consistency across `SKILL.md`, `package.json`, and the
  README badges (reports mismatches as warnings; the `all` flow will bump them)
- Scans every tracked source file under `skills/plantuml/` and both READMEs for
  any leftover `skinparam style strictuml` line and fails hard if found
- Verifies `git`, `gh`, and (when needed) `clawhub` are installed and
  authenticated
- Reports working-tree cleanliness (informational in `check` mode; the `all`
  flow enforces it via the `push` step)

### 2. `build`

- Builds `dist/plantuml-skill-v<version>.tar.gz`
- Includes `skills/plantuml/`, `examples/*.puml`, `examples/*.svg`, `README.md`,
  `README.zh-CN.md`, `LICENSE`
- Honors `.clawhubignore` and additionally excludes `.git/`, `node_modules/`,
  `output/`, `dist/`, `plantuml.jar`, `.omo/`, editor swap files, `.DS_Store`,
  `Thumbs.db`
- Warns if the archive exceeds 500KB (likely an accidental inclusion)

### 3. `push`

- If the version-bump produced staged changes, commits them as
  `chore: bump version to v<version>` and pushes to
  `<PLANTUML_RELEASE_REMOTE>/<PLANTUML_RELEASE_MAIN_BRANCH>`
- No-op if nothing changed

### 4. `gh-release`

- Creates and pushes the `v<version>` tag if it does not already exist
- Runs `gh release create v<version> --title v<version> --notes <...>` with the
  archive attached

### 5. `clawhub-publish`

- Resolves the current `HEAD` commit SHA
- Runs `clawhub skill publish skills/plantuml --slug plantuml-skill
  --version <version> --source-repo samonysh/plantuml-skill
  --source-commit <sha> --changelog "Release v<version>"`

## Versioning

We follow [Semantic Versioning](https://semver.org/):

- **Major** (X.0.0) - Breaking changes to the SKILL.md contract or render
  script flags
- **Minor** (0.X.0) - New features, new diagram types, new flags
- **Patch** (0.0.X) - Bug fixes, documentation updates, example regenerations

Pre-release versions (e.g., `1.8.0-beta.1`) are supported.

## Checklist

Before releasing, verify:

- [ ] All examples render correctly (both Bash and PowerShell scripts)
- [ ] SKILL.md documentation matches actual behavior
- [ ] README.md and README.zh-CN.md are in sync
- [ ] Dark mode SVGs have correct palette
- [ ] Aspect ratios are within [0.7, 1.4] band (or warned if outside)
- [ ] `python scripts/release.py <version> --step check` passes cleanly
- [ ] No `skinparam style strictuml` anywhere in tracked sources

## Troubleshooting

### `check` fails with "Found forbidden `skinparam style strictuml`"

The preflight scanner found a leftover `strictuml` line. Remove it manually
(see SKILL.md -> Common Failure Patterns) and re-run. The render scripts also
defensively strip it at runtime, but the release gate keeps the source clean.

### clawhub publish fails with "unauthorized"

```bash
clawhub login --token clh_<your-token>
clawhub whoami
```

### GitHub release fails

```bash
gh auth status
gh auth login
```

### Archive too large

The `build` step warns at >500KB. Inspect `dist/plantuml-skill-v<version>.tar.gz`
for accidentally included `plantuml.jar`, `.omo/`, `output/`, or
`node_modules/` directories - the filter should already exclude them, but a
newly-added large file under `skills/plantuml/` could slip through.
