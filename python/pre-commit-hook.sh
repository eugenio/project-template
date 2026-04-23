#!/usr/bin/env bash
# Pre-commit hook — blocks commit if quality gates fail.
# Gates: ruff lint/format, mypy, mdformat, coverage, test categories, docstrings, UML staleness, secrets.
#
# Install:  cp pre-commit-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
# Bypass a gate once:  SKIP_UML_CHECK=1 git commit ...

set -euo pipefail

# ===========================================================================
# PROJECT CONFIG — ADAPT THESE
# ===========================================================================
SOURCE_DIRS="src"               # space-separated list of source dirs for mypy/docstrings
TEST_DIR="tests"                # test directory for pytest
COV_TARGETS="--cov=src"        # pytest --cov flags (one per source dir)
COVERAGE_GATE=97                # minimum acceptable line+branch coverage %
DOCSTRING_GATE=99.9             # minimum interrogate coverage %
UML_DIR="docs/uml"             # path to UML diagram directory (set empty to disable)
PIXI_ENV="dev"                  # pixi environment that has the dev tools installed
# ===========================================================================

# --- Color helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # no color

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
fail() { echo -e "${RED}❌ COMMIT BLOCKED: $*${NC}"; exit 1; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
info() { echo -e "🔍 $*"; }

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"

STAGED_PY_FILES=$(git diff --cached --name-only --diff-filter=ACMR -- '*.py')

# ---------------------------------------------------------------------------
# 1. Ruff lint + format on staged Python files
# ---------------------------------------------------------------------------
if [ -n "$STAGED_PY_FILES" ]; then
    info "Running ruff lint and format on staged Python files..."
    echo "$STAGED_PY_FILES" | sed 's/^/   /'
    echo ""

    # shellcheck disable=SC2086
    if ! pixi run -e "$PIXI_ENV" ruff check $STAGED_PY_FILES; then
        fail "ruff lint errors on staged files."
    fi

    # shellcheck disable=SC2086
    if ! pixi run -e "$PIXI_ENV" ruff format --check $STAGED_PY_FILES; then
        echo ""
        fail "ruff format errors on staged files. Run: pixi run -e $PIXI_ENV ruff format <files>"
    fi

    ok "Lint and format checks passed."
    echo ""
fi

# ---------------------------------------------------------------------------
# 2. mypy on staged source files (excludes tests)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_PY_FILES" ]; then
    # Build grep pattern from SOURCE_DIRS (e.g. "src utilities" -> "^(src|utilities)/")
    SRC_PATTERN=$(echo "$SOURCE_DIRS" | tr ' ' '|')
    STAGED_SRC_PY=$(echo "$STAGED_PY_FILES" | grep -E "^(${SRC_PATTERN})/" || true)

    if [ -n "$STAGED_SRC_PY" ]; then
        info "Running mypy on staged source files..."
        # shellcheck disable=SC2086
        if ! pixi run -e "$PIXI_ENV" python -m mypy \
            --ignore-missing-imports \
            --disable-error-code=import-untyped \
            --explicit-package-bases \
            $STAGED_SRC_PY; then
            fail "mypy type errors on staged source files."
        fi
        ok "mypy passed."
        echo ""
    fi
fi

# ---------------------------------------------------------------------------
# 3. mdformat on staged Markdown files
# ---------------------------------------------------------------------------
STAGED_MD_FILES=$(git diff --cached --name-only --diff-filter=ACMR -- '*.md')

if [ -n "$STAGED_MD_FILES" ]; then
    info "Formatting staged Markdown files with mdformat..."
    # shellcheck disable=SC2086
    if ! pixi run -e "$PIXI_ENV" mdformat $STAGED_MD_FILES; then
        fail "mdformat failed."
    fi
    # shellcheck disable=SC2086
    git add $STAGED_MD_FILES
    ok "Markdown files formatted and re-staged."
    echo ""
fi

# ---------------------------------------------------------------------------
# 4. Coverage gate
# ---------------------------------------------------------------------------
info "Running tests with coverage gate (>= ${COVERAGE_GATE}%)..."

# shellcheck disable=SC2086
if ! pixi run -e "$PIXI_ENV" pytest "$TEST_DIR" -q \
    $COV_TARGETS \
    --cov-report=term-missing \
    --cov-fail-under="$COVERAGE_GATE" \
    --tb=short 2>&1; then
    fail "test coverage below ${COVERAGE_GATE}% or tests failed. Fix before committing."
fi

ok "Coverage gate passed (>= ${COVERAGE_GATE}%)."
echo ""

# ---------------------------------------------------------------------------
# 5. Mandatory test category existence check
# ---------------------------------------------------------------------------
# Every project MUST have: integration, e2e, smoke, edge_cases tests.
# See shared/TESTING_DIRECTIVE.md for the full policy.
info "Checking mandatory test categories exist..."
MISSING_CATS=""
for cat in integration e2e smoke edge_cases; do
    cat_dir="$TEST_DIR/$cat"
    if [ "$cat" = "integration" ]; then
        # integration tests may be in a single file or a directory
        if [ ! -d "$cat_dir" ] && ! find "$TEST_DIR" -maxdepth 2 -name "*integration*" -type f 2>/dev/null | grep -q .; then
            MISSING_CATS="$MISSING_CATS $cat"
        fi
    elif [ ! -d "$cat_dir" ] || [ -z "$(find "$cat_dir" -name 'test_*.py' -type f 2>/dev/null)" ]; then
        MISSING_CATS="$MISSING_CATS $cat"
    fi
done

if [ -n "$MISSING_CATS" ]; then
    fail "Missing mandatory test categories:$MISSING_CATS. See docs/TESTING_DIRECTIVE.md."
fi
ok "All mandatory test categories present (integration, e2e, smoke, edge_cases)."
echo ""

# ---------------------------------------------------------------------------
# 6. Docstring coverage gate
# ---------------------------------------------------------------------------
if [ -n "$STAGED_PY_FILES" ]; then
    info "Running interrogate docstring check (gate: ${DOCSTRING_GATE}%)..."
    # shellcheck disable=SC2086
    if ! pixi run -e "$PIXI_ENV" interrogate \
        --fail-under "$DOCSTRING_GATE" \
        -v \
        $SOURCE_DIRS 2>&1; then
        fail "docstring coverage below ${DOCSTRING_GATE}%. Add missing docstrings."
    fi
    ok "Docstring coverage gate passed (>= ${DOCSTRING_GATE}%)."
    echo ""
fi

# ---------------------------------------------------------------------------
# 7. UML staleness check
# ---------------------------------------------------------------------------
if [ -n "$UML_DIR" ] && [ -d "$UML_DIR" ]; then
    info "Checking UML diagram freshness..."

    SRC_PATTERN=$(echo "$SOURCE_DIRS" | tr ' ' '|')
    STAGED_SRC=$(echo "$STAGED_PY_FILES" | grep -E "^(${SRC_PATTERN})/" || true)

    LATEST_SRC_COMMIT=$(git log -1 --format=%ct -- $SOURCE_DIRS 2>/dev/null || echo 0)
    LATEST_UML_COMMIT=$(git log -1 --format=%ct -- "$UML_DIR/" 2>/dev/null || echo 0)

    if [ -n "$STAGED_SRC" ] && [ "$LATEST_SRC_COMMIT" -gt "$LATEST_UML_COMMIT" ]; then
        warn "UML diagrams may be stale."
        echo "   Source changed more recently than $UML_DIR/."
        echo "   Run /uml-agent to regenerate, or set SKIP_UML_CHECK=1 to bypass once."
        echo ""
        echo "   Last source commit: $(git log -1 --format='%h %s' -- $SOURCE_DIRS)"
        echo "   Last UML commit:    $(git log -1 --format='%h %s' -- "$UML_DIR/")"
        echo ""
        if [ "${SKIP_UML_CHECK:-0}" != "1" ]; then
            fail "UML diagrams are stale. Update or set SKIP_UML_CHECK=1."
        fi
    else
        ok "UML diagrams are up to date."
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# 8. Gitleaks secret scan
# ---------------------------------------------------------------------------
if command -v gitleaks &>/dev/null; then
    info "Scanning staged files for secrets with gitleaks..."
    if ! gitleaks detect --staged --no-banner 2>&1; then
        fail "potential secrets detected by gitleaks. Remove before committing."
    fi
    ok "No secrets detected."
    echo ""
else
    warn "gitleaks not found — skipping secret scan."
    echo "   Install: https://github.com/gitleaks/gitleaks"
    echo ""
fi

# ---------------------------------------------------------------------------
# 9. git-absorb atomicity gate (logic in scripts/hooks/git-absorb-gate.sh)
# Re-install after template setup.sh: see scripts/hooks/README.md.
# ---------------------------------------------------------------------------
ABSORB_GATE="$(git rev-parse --show-toplevel)/scripts/hooks/git-absorb-gate.sh"
if [[ -x "$ABSORB_GATE" ]]; then
    RED="$RED" GREEN="$GREEN" YELLOW="$YELLOW" NC="$NC" \
        bash "$ABSORB_GATE" || exit 1
    echo ""
else
    warn "atomicity gate script missing: $ABSORB_GATE"
    echo ""
fi
