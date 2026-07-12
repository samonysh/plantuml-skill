#!/usr/bin/env python3
"""release.py - Unified release manager for plantuml-skill.

Replaces the legacy release.sh with a single, environment-driven Python script.
Pipeline (run individually or via `all`):

  1. check        - preflight: version format, version consistency across files,
                     clean working tree, required CLIs, no leftover strictuml
  2. build        - build the release tar.gz (respects .clawhubignore)
  3. push         - commit version bumps if any, push to the main branch
  4. gh-release   - create a GitHub release via gh CLI and upload the archive
  5. clawhub-publish - publish the skill to ClawHub via clawhub CLI
  6. all          - run 1 -> 5 in order

All knobs are environment variables (with sensible defaults). See
scripts/.env.example for the full list. The script never reads or writes
secrets to disk; tokens are expected to be provided by the CLIs' own auth
(gh auth login / clawhub login) or via standard env vars (GH_TOKEN, etc.).

Usage:
    python scripts/release.py <version> [--step check|build|push|gh-release|clawhub-publish|all] [--dry-run]

Examples:
    python scripts/release.py 1.7.1                   # full release
    python scripts/release.py 1.7.1 --step check      # preflight only
    python scripts/release.py 1.8.0-beta.1 --dry-run  # preview everything
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tarfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

# ---------------------------------------------------------------------------
# Configuration (env-driven)
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
SKILL_DIR = REPO_ROOT / "skills" / "plantuml"
SKILL_MD = SKILL_DIR / "SKILL.md"
PACKAGE_JSON = REPO_ROOT / "package.json"
README_MD = REPO_ROOT / "README.md"
README_ZH = REPO_ROOT / "README.zh-CN.md"
CLAWHUB_IGNORE = REPO_ROOT / ".clawhubignore"
ENV_EXAMPLE = REPO_ROOT / "scripts" / ".env.example"

DEFAULT_GH_REPO = os.environ.get("PLANTUML_RELEASE_GH_REPO", "samonysh/plantuml-skill")
DEFAULT_MAIN_BRANCH = os.environ.get("PLANTUML_RELEASE_MAIN_BRANCH", "main")
DEFAULT_REMOTE = os.environ.get("PLANTUML_RELEASE_REMOTE", "origin")
DEFAULT_CLAWHUB_SLUG = os.environ.get("PLANTUML_RELEASE_CLAWHUB_SLUG", "plantuml-skill")
DEFAULT_ARCHIVE_NAME = os.environ.get("PLANTUML_RELEASE_ARCHIVE_NAME", "plantuml-skill")
DEFAULT_DIST_DIR = os.environ.get("PLANTUML_RELEASE_DIST_DIR", "dist")

VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$")
STRICTUML_PATTERN = re.compile(r"^\s*skinparam\s+style\s+strictuml\s*$", re.MULTILINE)


# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"


def info(msg: str) -> None:
    print(f"{Colors.GREEN}[INFO]{Colors.NC} {msg}")


def warn(msg: str) -> None:
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")


def error(msg: str) -> None:
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}", file=sys.stderr)


def step_header(name: str) -> None:
    print(f"\n{Colors.BLUE}━━ {name} ━━{Colors.NC}")


# ---------------------------------------------------------------------------
# Subprocess helper
# ---------------------------------------------------------------------------

@dataclass
class CmdResult:
    returncode: int
    stdout: str
    stderr: str


def _resolve_for_subprocess(cmd: list[str]) -> tuple:
    """Resolve a command for subprocess.run.

    On Windows, CLI wrappers shipped as .CMD/.BAT (e.g. clawhub.CMD) cannot be
    launched directly by CreateProcess - they need cmd.exe to interpret them.
    For those, return a quoted command string with shell=True. Real .exe files
    (git, gh) pass through unchanged with shell=False.
    """
    if os.name == "nt":
        resolved = shutil.which(cmd[0])
        if resolved and resolved.lower().endswith((".cmd", ".bat")):
            cmd_str = subprocess.list2cmdline([resolved] + list(cmd[1:]))
            return cmd_str, True
    return cmd, False


def run(cmd: list[str], *, capture: bool = False, check: bool = True,
        cwd: Optional[Path] = None) -> CmdResult:
    """Run a command; by default streams output, optionally captures."""
    actual_cmd, use_shell = _resolve_for_subprocess(cmd)
    if capture:
        proc = subprocess.run(actual_cmd, cwd=cwd, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              shell=use_shell)
        if check and proc.returncode != 0:
            error(f"Command failed: {' '.join(cmd)}")
            if proc.stderr.strip():
                print(proc.stderr, file=sys.stderr)
            raise SystemExit(proc.returncode)
        return CmdResult(proc.returncode, proc.stdout, proc.stderr)
    else:
        proc = subprocess.run(actual_cmd, cwd=cwd, shell=use_shell)
        if check and proc.returncode != 0:
            error(f"Command failed: {' '.join(cmd)}")
            raise SystemExit(proc.returncode)
        return CmdResult(proc.returncode, "", "")


def have_cmd(name: str) -> bool:
    return shutil.which(name) is not None


# ---------------------------------------------------------------------------
# Step 1: preflight check
# ---------------------------------------------------------------------------

def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def extract_skill_md_version() -> Optional[str]:
    m = re.search(r"^version:\s*(\S+)\s*$", read_text(SKILL_MD), re.MULTILINE)
    return m.group(1) if m else None


def extract_package_json_version() -> Optional[str]:
    import json
    try:
        data = json.loads(read_text(PACKAGE_JSON))
        return data.get("version")
    except Exception:
        return None


def extract_readme_badge_version(text: str) -> Optional[str]:
    m = re.search(r"version-v(\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?)-blue", text)
    return m.group(1) if m else None


def check_version_consistency(target: str) -> bool:
    ok = True
    skill_ver = extract_skill_md_version()
    pkg_ver = extract_package_json_version()
    en_badge = extract_readme_badge_version(read_text(README_MD))
    zh_badge = extract_readme_badge_version(read_text(README_ZH))

    def _cmp(label: str, actual: Optional[str]) -> None:
        nonlocal ok
        if actual is None:
            warn(f"{label}: version not found (will be set during bump)")
        elif actual != target:
            warn(f"{label}: {actual} != target {target} (will be bumped)")
        else:
            info(f"{label}: {actual} ✓")

    _cmp("SKILL.md", skill_ver)
    _cmp("package.json", pkg_ver)
    _cmp("README.md badge", en_badge)
    _cmp("README.zh-CN.md badge", zh_badge)
    return ok


def check_no_strictuml() -> bool:
    """Ensure no source file in the repo still ships `skinparam style strictuml`."""
    offenders: list[Path] = []
    for p in SKILL_DIR.rglob("*"):
        if p.is_file() and p.suffix in {".md", ".puml", ".sh", ".ps1"}:
            if STRICTUML_PATTERN.search(read_text(p)):
                offenders.append(p)
    for p in (README_MD, README_ZH):
        if p.exists() and STRICTUML_PATTERN.search(read_text(p)):
            offenders.append(p)
    if offenders:
        error("Found forbidden `skinparam style strictuml` in:")
        for p in offenders:
            error(f"  - {p.relative_to(REPO_ROOT)}")
        error("See SKILL.md -> Common Failure Patterns. Remove before releasing.")
        return False
    info("No `skinparam style strictuml` in tracked sources ✓")
    return True


def check_working_tree_clean() -> bool:
    res = run(["git", "status", "--porcelain"], capture=True, check=False,
              cwd=REPO_ROOT)
    if res.stdout.strip():
        error("Working tree has uncommitted changes. Commit or stash first:")
        print(res.stdout, file=sys.stderr)
        return False
    info("Working tree clean ✓")
    return True


def check_required_clis(needs_clawhub: bool) -> bool:
    ok = True
    for cmd in ("git", "gh"):
        if not have_cmd(cmd):
            error(f"{cmd} CLI not found. Install it and retry.")
            ok = False
        else:
            info(f"{cmd} present ✓")

    if needs_clawhub and not have_cmd("clawhub"):
        error("clawhub CLI not found. Install: npm i -g clawhub")
        ok = False
    elif needs_clawhub:
        info("clawhub present ✓")

    # gh auth
    if have_cmd("gh"):
        res = run(["gh", "auth", "status"], capture=True, check=False,
                  cwd=REPO_ROOT)
        if res.returncode != 0:
            error("gh not authenticated. Run: gh auth login")
            ok = False
        else:
            info("gh authenticated ✓")

    if needs_clawhub and have_cmd("clawhub"):
        res = run(["clawhub", "whoami"], capture=True, check=False,
                  cwd=REPO_ROOT)
        if res.returncode != 0:
            error("clawhub not authenticated. Run: clawhub login --token <token>")
            ok = False
        else:
            info("clawhub authenticated ✓")

    return ok


def step_check(version: str, dry_run: bool, needs_clawhub: bool = True) -> bool:
    step_header("STEP 1 / Preflight check")

    if not VERSION_PATTERN.match(version):
        error(f"Invalid version format: {version}")
        error("Expected: X.Y.Z or X.Y.Z-tag (e.g., 1.7.1, 1.8.0-beta.1)")
        return False
    info(f"Version format OK: {version} ✓")

    ok = True
    ok = check_version_consistency(version) and ok
    ok = check_no_strictuml() and ok
    ok = check_required_clis(needs_clawhub=needs_clawhub) and ok
    # Working tree cleanliness is only required for push/release; in pure
    # check mode we still report it but do not hard-fail so users can run
    # `check` while iterating.
    check_working_tree_clean()
    return ok


# ---------------------------------------------------------------------------
# Version bump
# ---------------------------------------------------------------------------

def bump_version_refs(version: str, dry_run: bool) -> None:
    step_header("STEP (pre) / Bump version references")
    info(f"Bumping version references to v{version}...")

    def _bump_file(path: Path, transform: Callable[[str], str], label: str) -> None:
        if not path.exists():
            return
        original = read_text(path)
        updated = transform(original)
        if updated == original:
            info(f"{label}: no version-pattern match, leaving untouched")
            return
        if dry_run:
            info(f"[dry-run] {label}: would bump to v{version}")
        else:
            path.write_text(updated, encoding="utf-8")
            info(f"{label}: bumped to v{version} ✓")

    _bump_file(SKILL_MD,
               lambda s: re.sub(r"^version:.*$", f"version: {version}",
                                s, count=1, flags=re.MULTILINE),
               "SKILL.md")

    _bump_file(PACKAGE_JSON,
               lambda s: re.sub(r'"version"\s*:\s*"[^"]*"',
                                f'"version": "{version}"', s),
               "package.json")

    badge_re = r"version-v\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?-blue"
    _bump_file(README_MD,
               lambda s: re.sub(badge_re, f"version-v{version}-blue", s),
               "README.md badge")
    _bump_file(README_ZH,
               lambda s: re.sub(badge_re, f"version-v{version}-blue", s),
               "README.zh-CN.md badge")

    # "Why Kroki (vX.Y.Z)" section headers — English uses half-width parens,
    # Chinese uses "为什么是 Kroki（vX.Y.Z）" with full-width parens.
    en_kroki_re = r"Why Kroki \(v\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?\)"
    zh_kroki_re = r"为什么是 Kroki（v\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?）"
    _bump_file(README_MD,
               lambda s: re.sub(en_kroki_re, f"Why Kroki (v{version})", s),
               "README.md Why Kroki header")
    _bump_file(README_ZH,
               lambda s: re.sub(zh_kroki_re, f"为什么是 Kroki（v{version}）", s),
               "README.zh-CN.md 为什么是 Kroki 标题")


# ---------------------------------------------------------------------------
# Step 2: build archive
# ---------------------------------------------------------------------------

def parse_clawhub_ignore() -> set[str]:
    patterns: set[str] = set()
    if not CLAWHUB_IGNORE.exists():
        return patterns
    for line in read_text(CLAWHUB_IGNORE).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        patterns.add(line)
    return patterns


def archive_filter(tarinfo: tarfile.TarInfo) -> Optional[tarfile.TarInfo]:
    """Filter out files matching .clawhubignore patterns and common junk."""
    name = tarinfo.name
    junk_prefixes = (
        ".git/", "node_modules/", ".opencode/node_modules/",
        "output/", "dist/", "plantuml.jar", ".omo/",
    )
    for jp in junk_prefixes:
        if name.startswith(jp):
            return None
    if name.endswith(".swp") or name.endswith(".swo") or name.endswith("~"):
        return None
    if name in (".DS_Store", "Thumbs.db"):
        return None
    # Respect .clawhubignore top-level entries
    ignored = parse_clawhub_ignore()
    for pat in ignored:
        pat = pat.rstrip("/")
        if name == pat or name.startswith(pat + "/"):
            return None
    return tarinfo


def step_build(version: str, dry_run: bool) -> Path:
    step_header("STEP 2 / Build release archive")
    dist_dir = REPO_ROOT / DEFAULT_DIST_DIR
    dist_dir.mkdir(parents=True, exist_ok=True)
    archive_name = f"{DEFAULT_ARCHIVE_NAME}-v{version}.tar.gz"
    archive_path = dist_dir / archive_name

    if dry_run:
        info(f"[dry-run] Would build {archive_path}")
        return archive_path

    # Collect paths to include (matching legacy release.sh behavior)
    include_paths: list[Path] = []
    if SKILL_DIR.exists():
        include_paths.append(SKILL_DIR)
    examples_dir = REPO_ROOT / "examples"
    if examples_dir.exists():
        for p in sorted(examples_dir.iterdir()):
            if p.suffix in {".puml", ".svg"}:
                include_paths.append(p)
    for f in (README_MD, README_ZH, REPO_ROOT / "LICENSE"):
        if f.exists():
            include_paths.append(f)

    with tarfile.open(archive_path, "w:gz") as tar:
        for p in include_paths:
            arcname = p.relative_to(REPO_ROOT)
            tar.add(p, arcname=str(arcname), filter=archive_filter)

    size_kb = archive_path.stat().st_size / 1024
    info(f"Built {archive_path.relative_to(REPO_ROOT)} ({size_kb:.1f} KB) ✓")
    if size_kb > 500:
        warn("Archive is >500KB - check for accidentally included files "
             "(plantuml.jar, .omo/, output/, node_modules/)")
    return archive_path


# ---------------------------------------------------------------------------
# Step 3: push to main
# ---------------------------------------------------------------------------

def step_push(version: str, dry_run: bool) -> None:
    step_header("STEP 3 / Commit & push to main branch")

    # Detect if there are staged/unstaged changes after a bump
    res = run(["git", "status", "--porcelain"], capture=True, check=False,
              cwd=REPO_ROOT)
    dirty = bool(res.stdout.strip())

    if not dirty:
        info("No version-bump changes to commit; skipping commit/push ✓")
        return

    if dry_run:
        info("[dry-run] Would commit version bump and push to "
             f"{DEFAULT_REMOTE}/{DEFAULT_MAIN_BRANCH}")
        return

    run(["git", "add", "README.md", "README.zh-CN.md",
         "skills/plantuml/SKILL.md", "package.json"],
        cwd=REPO_ROOT, check=False)
    run(["git", "commit", "-m", f"chore: bump version to v{version}"],
        cwd=REPO_ROOT, check=False)
    run(["git", "push", DEFAULT_REMOTE, DEFAULT_MAIN_BRANCH],
        cwd=REPO_ROOT)
    info(f"Pushed to {DEFAULT_REMOTE}/{DEFAULT_MAIN_BRANCH} ✓")


# ---------------------------------------------------------------------------
# Step 4: GitHub release
# ---------------------------------------------------------------------------

def step_gh_release(version: str, archive_path: Path, dry_run: bool) -> None:
    step_header("STEP 4 / GitHub release via gh CLI")
    tag = f"v{version}"

    if dry_run:
        info(f"[dry-run] Would create git tag {tag}, push it, and run "
             f"`gh release create {tag}` with {archive_path.name}")
        return

    # Create + push tag if missing
    res = run(["git", "rev-parse", "--verify", "--quiet", tag],
              capture=True, check=False, cwd=REPO_ROOT)
    if res.returncode != 0:
        run(["git", "tag", "-a", tag, "-m", f"Release {tag}"], cwd=REPO_ROOT)
        run(["git", "push", DEFAULT_REMOTE, tag], cwd=REPO_ROOT)
        info(f"Created and pushed tag {tag} ✓")
    else:
        info(f"Tag {tag} already exists, reusing ✓")

    notes = f"""## {tag}

See [RELEASE.md](https://github.com/{DEFAULT_GH_REPO}/blob/main/RELEASE.md) for the release process.

### Installation

```bash
# Via skills.sh
npx skills add {DEFAULT_GH_REPO}

# Via ClawHub
openclaw skills install {DEFAULT_CLAWHUB_SLUG}

# Manual
git clone https://github.com/{DEFAULT_GH_REPO}.git
cp -r plantuml-skill/skills/plantuml ~/.config/opencode/skills/
```
"""

    run(["gh", "release", "create", tag,
         "--title", tag,
         "--notes", notes,
         str(archive_path)],
        cwd=REPO_ROOT)
    info(f"GitHub release created: "
         f"https://github.com/{DEFAULT_GH_REPO}/releases/tag/{tag} ✓")


# ---------------------------------------------------------------------------
# Step 5: ClawHub publish
# ---------------------------------------------------------------------------

def step_clawhub_publish(version: str, dry_run: bool) -> None:
    step_header("STEP 5 / Publish to ClawHub via clawhub CLI")

    if dry_run:
        info(f"[dry-run] Would run `clawhub skill publish` for "
             f"{DEFAULT_CLAWHUB_SLUG}@{version}")
        return

    res = run(["git", "rev-parse", "HEAD"], capture=True, cwd=REPO_ROOT)
    commit_sha = res.stdout.strip()

    run(["clawhub", "skill", "publish", str(SKILL_DIR),
         "--slug", DEFAULT_CLAWHUB_SLUG,
         "--version", version,
         "--source-repo", DEFAULT_GH_REPO,
         "--source-commit", commit_sha,
         "--changelog", f"Release v{version}"],
        cwd=REPO_ROOT)
    info(f"ClawHub published: "
         f"https://clawhub.ai/samonysh/{DEFAULT_CLAWHUB_SLUG} ✓")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Unified release manager for plantuml-skill.")
    parser.add_argument("version", help="Version to release, e.g. 1.7.1")
    parser.add_argument("--step",
                        choices=["check", "build", "push",
                                 "gh-release", "clawhub-publish", "all"],
                        default="all",
                        help="Which step to run (default: all)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview without publishing")
    parser.add_argument("--skip-clawhub", action="store_true",
                        help="Skip clawhub auth check / publish step")
    args = parser.parse_args()

    if not VERSION_PATTERN.match(args.version):
        error(f"Invalid version format: {args.version}")
        return 2

    needs_clawhub = (args.step in {"clawhub-publish", "all"}) and not args.skip_clawhub

    if args.step in {"check", "all"}:
        if not step_check(args.version, args.dry_run,
                          needs_clawhub=needs_clawhub):
            error("Preflight check failed. Fix the issues above and retry.")
            return 1
        if args.step == "check":
            return 0

    if args.step == "build":
        step_build(args.version, args.dry_run)
        return 0

    if args.step == "push":
        step_push(args.version, args.dry_run)
        return 0

    if args.step == "gh-release":
        archive = step_build(args.version, args.dry_run)
        step_gh_release(args.version, archive, args.dry_run)
        return 0

    if args.step == "clawhub-publish":
        step_clawhub_publish(args.version, args.dry_run)
        return 0

    # all
    bump_version_refs(args.version, args.dry_run)
    archive = step_build(args.version, args.dry_run)
    step_push(args.version, args.dry_run)
    step_gh_release(args.version, archive, args.dry_run)
    if needs_clawhub:
        step_clawhub_publish(args.version, args.dry_run)
    else:
        warn("--skip-clawhub set; skipping ClawHub publish step")

    print(f"\n{Colors.GREEN}━━ Release v{args.version} complete ━━{Colors.NC}")
    print(f"  GitHub:  https://github.com/{DEFAULT_GH_REPO}/releases/tag/v{args.version}")
    print(f"  ClawHub: https://clawhub.ai/samonysh/{DEFAULT_CLAWHUB_SLUG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
