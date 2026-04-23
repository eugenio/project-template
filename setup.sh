#!/usr/bin/env bash
# setup.sh — bootstrap a new project from the protein_ai_platform templates.
#
# Usage:
#   bash setup.sh --lang python|rust|typescript --project-dir /path/to/new-project
#
# What it does:
#   1. Copies shared templates (releaserc, package.json, gitleaks, gitignore, editorconfig)
#   2. Copies language-specific templates (pyproject.toml, clippy.toml, tsconfig, etc.)
#   3. Installs the language-appropriate pre-commit hook
#   4. Prints a summary and lists every ADAPT comment to review

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()      { echo -e "${GREEN}  [+] $*${NC}"; }
skip()    { echo -e "${YELLOW}  [-] $*${NC}"; }
section() { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }
fail()    { echo -e "${RED}[ERROR] $*${NC}"; exit 1; }

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
LANG=""
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lang)
            LANG="${2:-}"
            shift 2
            ;;
        --project-dir)
            PROJECT_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --lang python|rust|typescript --project-dir <path>"
            exit 0
            ;;
        *)
            fail "Unknown argument: $1. Run $0 --help for usage."
            ;;
    esac
done

[ -z "$LANG" ]        && fail "--lang is required. Choose: python, rust, typescript"
[ -z "$PROJECT_DIR" ] && fail "--project-dir is required."

case "$LANG" in
    python|rust|typescript) ;;
    *) fail "Unsupported language: $LANG. Choose: python, rust, typescript" ;;
esac

if [ ! -d "$PROJECT_DIR" ]; then
    fail "Project directory does not exist: $PROJECT_DIR"
fi

SHARED_DIR="$SCRIPT_DIR/shared"
LANG_DIR="$SCRIPT_DIR/$LANG"

[ -d "$SHARED_DIR" ] || fail "Shared template dir missing: $SHARED_DIR"
[ -d "$LANG_DIR"   ] || fail "Language template dir missing: $LANG_DIR"

echo ""
echo -e "${BOLD}Project Template Setup${NC}"
echo -e "  Language:    ${CYAN}$LANG${NC}"
echo -e "  Target dir:  ${CYAN}$PROJECT_DIR${NC}"

# ---------------------------------------------------------------------------
# Helper: copy a template file, stripping the .template suffix
# ---------------------------------------------------------------------------
copy_template() {
    local src="$1"
    local dst_dir="$2"
    local basename
    basename="$(basename "$src" .template)"
    local dst="$dst_dir/$basename"

    if [ -f "$dst" ]; then
        skip "Already exists (skipping): $basename"
    else
        cp "$src" "$dst"
        ok "Copied: $basename"
    fi
}

# ---------------------------------------------------------------------------
# 1. Shared templates
# ---------------------------------------------------------------------------
section "Shared templates"

for tmpl in \
    "$SHARED_DIR/.releaserc.yml.template" \
    "$SHARED_DIR/package.json.template" \
    "$SHARED_DIR/.gitleaksignore.template" \
    "$SHARED_DIR/.editorconfig.template" \
    "$SHARED_DIR/commitlint.config.js.template"
do
    copy_template "$tmpl" "$PROJECT_DIR"
done

# scripts/hooks/: copy gate script and README into project (tracked files)
HOOKS_SRC_DIR="$SHARED_DIR/scripts/hooks"
HOOKS_DST_DIR="$PROJECT_DIR/scripts/hooks"
mkdir -p "$HOOKS_DST_DIR"

for hook_script in git-absorb-gate.sh atomicity-check.sh pre-push-atomicity-gate.sh pr-checklist-merge-gate.sh; do
    src="$HOOKS_SRC_DIR/$hook_script"
    dst="$HOOKS_DST_DIR/$hook_script"
    if [ -f "$dst" ]; then
        skip "Already exists (skipping): scripts/hooks/$hook_script"
    else
        cp "$src" "$dst"
        chmod +x "$dst"
        ok "Copied + chmod +x: scripts/hooks/$hook_script"
    fi
done

HOOKS_README_SRC="$HOOKS_SRC_DIR/README.md"
HOOKS_README_DST="$HOOKS_DST_DIR/README.md"
if [ -f "$HOOKS_README_DST" ]; then
    skip "Already exists (skipping): scripts/hooks/README.md"
else
    cp "$HOOKS_README_SRC" "$HOOKS_README_DST"
    ok "Copied: scripts/hooks/README.md"
fi

# scripts/configure-merge-strategy.sh: opt-in script to enforce rebase-only merges
MERGE_SCRIPT_SRC="$SHARED_DIR/scripts/configure-merge-strategy.sh"
MERGE_SCRIPT_DST="$PROJECT_DIR/scripts/configure-merge-strategy.sh"
if [ -f "$MERGE_SCRIPT_DST" ]; then
    skip "Already exists (skipping): scripts/configure-merge-strategy.sh"
else
    cp "$MERGE_SCRIPT_SRC" "$MERGE_SCRIPT_DST"
    chmod +x "$MERGE_SCRIPT_DST"
    ok "Copied + chmod +x: scripts/configure-merge-strategy.sh"
fi

# scripts/{validate,run}_pr_checklists.py: PR checklist validator + gh CLI runner
for py_script in validate_pr_checklists.py run_pr_checklists.py; do
    src="$SHARED_DIR/scripts/$py_script"
    dst="$PROJECT_DIR/scripts/$py_script"
    if [ -f "$dst" ]; then
        skip "Already exists (skipping): scripts/$py_script"
    else
        cp "$src" "$dst"
        ok "Copied: scripts/$py_script"
    fi
done

# tests/unit/test_validate_pr_checklists.py: reference pytest suite for the PR-checklist parser
PR_CHECKLIST_TEST_SRC="$SHARED_DIR/tests/unit/test_validate_pr_checklists.py"
PR_CHECKLIST_TEST_DST_DIR="$PROJECT_DIR/tests/unit"
PR_CHECKLIST_TEST_DST="$PR_CHECKLIST_TEST_DST_DIR/test_validate_pr_checklists.py"
mkdir -p "$PR_CHECKLIST_TEST_DST_DIR"
if [ -f "$PR_CHECKLIST_TEST_DST" ]; then
    skip "Already exists (skipping): tests/unit/test_validate_pr_checklists.py"
else
    cp "$PR_CHECKLIST_TEST_SRC" "$PR_CHECKLIST_TEST_DST"
    ok "Copied: tests/unit/test_validate_pr_checklists.py"
fi

# .github/workflows/pr-checklist.yml: CI gate that mirrors the pre-merge-commit hook
PR_CHECKLIST_WORKFLOW_SRC="$SHARED_DIR/.github/workflows/pr-checklist.yml.template"
PR_CHECKLIST_WORKFLOW_DST_DIR="$PROJECT_DIR/.github/workflows"
PR_CHECKLIST_WORKFLOW_DST="$PR_CHECKLIST_WORKFLOW_DST_DIR/pr-checklist.yml"
mkdir -p "$PR_CHECKLIST_WORKFLOW_DST_DIR"
if [ -f "$PR_CHECKLIST_WORKFLOW_DST" ]; then
    skip "Already exists (skipping): .github/workflows/pr-checklist.yml"
else
    cp "$PR_CHECKLIST_WORKFLOW_SRC" "$PR_CHECKLIST_WORKFLOW_DST"
    ok "Copied: .github/workflows/pr-checklist.yml"
fi

# .github/PULL_REQUEST_TEMPLATE.md: rebase-merge reminder + atomic-commit checklist
PR_TEMPLATE_SRC="$SHARED_DIR/.github/PULL_REQUEST_TEMPLATE.md.template"
PR_TEMPLATE_DST_DIR="$PROJECT_DIR/.github"
PR_TEMPLATE_DST="$PR_TEMPLATE_DST_DIR/PULL_REQUEST_TEMPLATE.md"
mkdir -p "$PR_TEMPLATE_DST_DIR"
if [ -f "$PR_TEMPLATE_DST" ]; then
    skip "Already exists (skipping): .github/PULL_REQUEST_TEMPLATE.md"
else
    cp "$PR_TEMPLATE_SRC" "$PR_TEMPLATE_DST"
    ok "Copied: .github/PULL_REQUEST_TEMPLATE.md"
fi

# .gitignore-additions: append to existing .gitignore rather than replacing it
GITIGNORE_ADDITIONS="$SHARED_DIR/.gitignore-additions.template"
GITIGNORE_TARGET="$PROJECT_DIR/.gitignore"

if [ -f "$GITIGNORE_TARGET" ]; then
    if grep -q "# --- Coverage ---" "$GITIGNORE_TARGET" 2>/dev/null; then
        skip "gitignore additions already present"
    else
        echo "" >> "$GITIGNORE_TARGET"
        echo "# ----- project-template additions -----" >> "$GITIGNORE_TARGET"
        cat "$GITIGNORE_ADDITIONS" >> "$GITIGNORE_TARGET"
        ok "Appended .gitignore additions"
    fi
else
    copy_template "$GITIGNORE_ADDITIONS" "$PROJECT_DIR"
fi

# ---------------------------------------------------------------------------
# 2. Language-specific templates
# ---------------------------------------------------------------------------
section "Language-specific templates ($LANG)"

case "$LANG" in
    python)
        copy_template "$LANG_DIR/pyproject.toml.template" "$PROJECT_DIR"
        copy_template "$LANG_DIR/.coveragerc.template"    "$PROJECT_DIR"
        ;;
    rust)
        copy_template "$LANG_DIR/clippy.toml.template"  "$PROJECT_DIR"
        copy_template "$LANG_DIR/rustfmt.toml.template" "$PROJECT_DIR"
        ;;
    typescript)
        copy_template "$LANG_DIR/tsconfig.json.template"      "$PROJECT_DIR"
        copy_template "$LANG_DIR/eslint.config.mjs.template"  "$PROJECT_DIR"
        ;;
esac

# ---------------------------------------------------------------------------
# 3. Git hooks (pre-commit + commit-msg + post-commit + pre-push + pre-merge-commit)
# ---------------------------------------------------------------------------
section "Git hooks (pre-commit + commit-msg + post-commit + pre-push + pre-merge-commit)"

HOOK_SRC="$LANG_DIR/pre-commit-hook.sh"
GIT_DIR="$PROJECT_DIR/.git"
HOOK_DST="$GIT_DIR/hooks/pre-commit"
COMMIT_MSG_SRC="$SHARED_DIR/commit-msg-hook.sh"
COMMIT_MSG_DST="$GIT_DIR/hooks/commit-msg"
POST_COMMIT_DST="$GIT_DIR/hooks/post-commit"
PRE_PUSH_DST="$GIT_DIR/hooks/pre-push"
PRE_MERGE_COMMIT_DST="$GIT_DIR/hooks/pre-merge-commit"

if [ ! -d "$GIT_DIR" ]; then
    skip ".git directory not found in $PROJECT_DIR — skipping hook install."
    skip "Initialize a git repo first, then re-run this script."
else
    if [ -f "$HOOK_DST" ]; then
        skip "pre-commit hook already exists at $HOOK_DST"
        skip "Review and merge manually if needed."
    else
        cp "$HOOK_SRC" "$HOOK_DST"
        chmod +x "$HOOK_DST"
        ok "Installed pre-commit hook → $HOOK_DST"
    fi

    if [ -f "$COMMIT_MSG_DST" ]; then
        skip "commit-msg hook already exists at $COMMIT_MSG_DST"
    else
        cp "$COMMIT_MSG_SRC" "$COMMIT_MSG_DST"
        chmod +x "$COMMIT_MSG_DST"
        ok "Installed commit-msg hook → $COMMIT_MSG_DST"
    fi

    # post-commit: atomicity classifier (logic in scripts/hooks/atomicity-check.sh)
    if [ -f "$POST_COMMIT_DST" ]; then
        skip "post-commit hook already exists at $POST_COMMIT_DST"
        skip "Review and merge manually if needed."
    else
        cat >"$POST_COMMIT_DST" <<'HOOK'
#!/usr/bin/env bash
# post-commit — atomicity marker (logic in scripts/hooks/atomicity-check.sh)
# Re-install after template setup.sh: see scripts/hooks/README.md.
set -e
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[[ -z "$REPO_ROOT" ]] && exit 0
CHECK="$REPO_ROOT/scripts/hooks/atomicity-check.sh"
if [[ -x "$CHECK" ]]; then
    # Advisory: post-commit cannot undo the commit. The sentinel file
    # .git/NON_ATOMIC_COMMIT is the signal consumed by pre-push.
    bash "$CHECK" || true
fi
HOOK
        chmod +x "$POST_COMMIT_DST"
        ok "Installed post-commit hook → $POST_COMMIT_DST"
    fi

    # pre-push: atomicity gate (logic in scripts/hooks/pre-push-atomicity-gate.sh)
    if [ -f "$PRE_PUSH_DST" ]; then
        skip "pre-push hook already exists at $PRE_PUSH_DST"
        skip "Review and merge manually if needed."
    else
        cat >"$PRE_PUSH_DST" <<'HOOK'
#!/usr/bin/env bash
# pre-push — atomicity gate (logic in scripts/hooks/pre-push-atomicity-gate.sh)
# Re-install after template setup.sh: see scripts/hooks/README.md.
set -e
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[[ -z "$REPO_ROOT" ]] && exit 0
GATE="$REPO_ROOT/scripts/hooks/pre-push-atomicity-gate.sh"
if [[ -x "$GATE" ]]; then
    # pre-push receives: <remote-name> <remote-url> as args
    # and <local-ref> <local-sha> <remote-ref> <remote-sha> lines on stdin.
    bash "$GATE" "$@" || exit 1
fi
HOOK
        chmod +x "$PRE_PUSH_DST"
        ok "Installed pre-push hook → $PRE_PUSH_DST"
    fi

    # pre-merge-commit: PR checklist gate (logic in scripts/hooks/pr-checklist-merge-gate.sh)
    if [ -f "$PRE_MERGE_COMMIT_DST" ]; then
        skip "pre-merge-commit hook already exists at $PRE_MERGE_COMMIT_DST"
        skip "Review and merge manually if needed."
    else
        cat >"$PRE_MERGE_COMMIT_DST" <<'HOOK'
#!/usr/bin/env bash
# pre-merge-commit — PR checklist gate (logic in scripts/hooks/pr-checklist-merge-gate.sh)
# Re-install after template setup.sh: see scripts/hooks/README.md.
set -e
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[[ -z "$REPO_ROOT" ]] && exit 0
GATE="$REPO_ROOT/scripts/hooks/pr-checklist-merge-gate.sh"
if [[ -x "$GATE" ]]; then
    bash "$GATE" "$@" || exit 1
fi
HOOK
        chmod +x "$PRE_MERGE_COMMIT_DST"
        ok "Installed pre-merge-commit hook → $PRE_MERGE_COMMIT_DST"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------------------
section "Summary"

echo -e "  ${GREEN}Files copied to ${PROJECT_DIR}${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "  1. Find all required customizations:  ${CYAN}grep -r 'ADAPT' \"$PROJECT_DIR\"/${NC}"
echo ""

case "$LANG" in
    python)
        echo -e "  2. Adapt pyproject.toml: name, requires-python, --cov targets, known-first-party"
        echo -e "  3. Adapt pre-commit-hook.sh top block: SOURCE_DIRS, COV_TARGETS, PIXI_ENV"
        echo -e "  4. Install dev tools: pixi add --feature dev interrogate ruff mypy mdformat"
        ;;
    rust)
        echo -e "  2. Adapt pre-commit-hook.sh top block: CRATE_DIR, CARGO_FEATURES"
        echo -e "  3. Optional: cargo install cargo-deny  (license/advisory gate)"
        ;;
    typescript)
        echo -e "  2. Adapt pre-commit-hook.sh top block: PACKAGE_DIR, VITEST_CONFIG"
        echo -e "  3. npm i -D eslint @typescript-eslint/eslint-plugin prettier vitest"
        ;;
esac

echo ""
echo -e "  5. Adapt .releaserc.yml: branch name, assets list, github vs gitlab plugin"
echo -e "  6. Install gitleaks: https://github.com/gitleaks/gitleaks#installing"
echo -e "  7. Install git-absorb (pre-commit atomicity gate):"
echo -e "       pixi global install git-absorb  OR  cargo install git-absorb  OR  apt install git-absorb"
echo -e "  8. Install Node deps (commitlint): npm install"
echo -e "  9. Post-commit + pre-push atomicity gates are wired automatically."
echo -e "       Sentinel file: .git/NON_ATOMIC_COMMIT  (consumed by pre-push)"
echo -e "       Bypass per-push: ATOMICITY_ACK=1 git push ..."
echo -e " 10. ${BOLD}Enforce rebase-only merges on the remote${NC} (preserves atomic history):"
echo -e "       bash scripts/configure-merge-strategy.sh   # requires gh CLI + admin access"
echo -e "     ${YELLOW}Required follow-up${NC} — branch protection (level 2):"
echo -e "       Enable 'Require linear history' on the default branch. See the"
echo -e "       'Next steps' printout of configure-merge-strategy.sh."
echo -e " 11. PR-checklist gate is wired automatically (pre-merge-commit hook +"
echo -e "       .github/workflows/pr-checklist.yml). Requires ${CYAN}gh${NC} CLI locally."
echo -e "       Bypass per-merge: SKIP_PR_CHECKLIST=1 git merge ..."
echo "  📋 LLM instructions: scripts/project-template/LLM_INSTRUCTIONS.md"
echo ""
echo -e "${GREEN}Setup complete.${NC}"
