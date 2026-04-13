#!/usr/bin/env bash
# Pre-commit hook for TypeScript projects.
# Gates: ESLint, Prettier --check, vitest run, gitleaks.
#
# Install:  cp pre-commit-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -euo pipefail

# ===========================================================================
# PROJECT CONFIG — ADAPT THESE
# ===========================================================================
# ADAPT: set to the package root if your TS project is in a subdirectory
PACKAGE_DIR="."
# ADAPT: vitest config file path (leave empty to use default discovery)
VITEST_CONFIG=""
# ADAPT: prettier patterns to check (space-separated globs)
PRETTIER_PATTERNS="src/**/*.{ts,tsx} *.{json,yml,md}"
# ===========================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
fail() { echo -e "${RED}❌ COMMIT BLOCKED: $*${NC}"; exit 1; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
info() { echo -e "🔍 $*"; }

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT/$PACKAGE_DIR"

STAGED_TS=$(git diff --cached --name-only --diff-filter=ACMR -- '*.ts' '*.tsx' '*.js' '*.jsx')

if [ -z "$STAGED_TS" ]; then
    exit 0  # nothing JS/TS staged
fi

# ---------------------------------------------------------------------------
# 1. ESLint
# ---------------------------------------------------------------------------
info "Running ESLint on staged files..."
echo "$STAGED_TS" | sed 's/^/   /'
echo ""

STAGED_TS_LIST=$(echo "$STAGED_TS" | tr '\n' ' ')
# shellcheck disable=SC2086
if ! npx eslint $STAGED_TS_LIST 2>&1; then
    fail "ESLint found errors. Fix before committing."
fi
ok "ESLint passed."
echo ""

# ---------------------------------------------------------------------------
# 2. Prettier --check
# ---------------------------------------------------------------------------
info "Checking formatting with Prettier..."
# shellcheck disable=SC2086
if ! npx prettier --check $STAGED_TS_LIST 2>&1; then
    fail "Prettier found formatting issues. Run: npx prettier --write <files>"
fi
ok "Prettier check passed."
echo ""

# ---------------------------------------------------------------------------
# 3. vitest run (fast unit test pass)
# ---------------------------------------------------------------------------
info "Running vitest..."
VITEST_ARGS=()
[ -n "$VITEST_CONFIG" ] && VITEST_ARGS+=(--config "$VITEST_CONFIG")

if ! npx vitest run "${VITEST_ARGS[@]}" 2>&1; then
    fail "vitest tests failed. Fix before committing."
fi
ok "All vitest tests passed."
echo ""

# ---------------------------------------------------------------------------
# 4. TypeScript type-check (tsc --noEmit)
# ---------------------------------------------------------------------------
info "Running TypeScript type-check..."
if ! npx tsc --noEmit 2>&1; then
    fail "TypeScript type errors found. Fix before committing."
fi
ok "TypeScript type-check passed."
echo ""

# ---------------------------------------------------------------------------
# 5. Gitleaks secret scan
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
