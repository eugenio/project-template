#!/usr/bin/env bash
# Pre-commit hook for Rust projects.
# Gates: clippy, rustfmt --check, cargo test, cargo deny check, gitleaks.
#
# Install:  cp pre-commit-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -euo pipefail

# ===========================================================================
# PROJECT CONFIG — ADAPT THESE
# ===========================================================================
# ADAPT: set to the crate/workspace root if different from repo root
CRATE_DIR="."
# ADAPT: add or remove feature flags (e.g. "--features full")
CARGO_FEATURES=""
# ADAPT: set your target triple if cross-compiling (leave empty for native)
CARGO_TARGET=""
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
cd "$PROJECT_ROOT/$CRATE_DIR"

STAGED_RS=$(git diff --cached --name-only --diff-filter=ACMR -- '*.rs')

if [ -z "$STAGED_RS" ]; then
    exit 0  # nothing Rust-related staged
fi

# ---------------------------------------------------------------------------
# 1. rustfmt --check
# ---------------------------------------------------------------------------
info "Checking Rust formatting with rustfmt..."
if ! cargo fmt -- --check 2>&1; then
    fail "rustfmt found formatting issues. Run: cargo fmt"
fi
ok "rustfmt check passed."
echo ""

# ---------------------------------------------------------------------------
# 2. clippy
# ---------------------------------------------------------------------------
info "Running clippy..."
CLIPPY_ARGS=()
[ -n "$CARGO_FEATURES" ] && CLIPPY_ARGS+=(--features "$CARGO_FEATURES")
[ -n "$CARGO_TARGET"   ] && CLIPPY_ARGS+=(--target "$CARGO_TARGET")

if ! cargo clippy "${CLIPPY_ARGS[@]}" -- -D warnings 2>&1; then
    fail "clippy found lint errors. Fix warnings before committing."
fi
ok "clippy passed."
echo ""

# ---------------------------------------------------------------------------
# 3. cargo test
# ---------------------------------------------------------------------------
info "Running cargo test..."
TEST_ARGS=()
[ -n "$CARGO_FEATURES" ] && TEST_ARGS+=(--features "$CARGO_FEATURES")
[ -n "$CARGO_TARGET"   ] && TEST_ARGS+=(--target "$CARGO_TARGET")

if ! cargo test "${TEST_ARGS[@]}" 2>&1; then
    fail "cargo test failed. Fix failing tests before committing."
fi
ok "All tests passed."
echo ""

# ---------------------------------------------------------------------------
# 4. cargo deny check (optional — skipped if cargo-deny not installed)
# ---------------------------------------------------------------------------
if command -v cargo-deny &>/dev/null || cargo deny --version &>/dev/null 2>&1; then
    info "Running cargo deny check..."
    if ! cargo deny check 2>&1; then
        fail "cargo deny check failed. Review license/advisory violations."
    fi
    ok "cargo deny check passed."
    echo ""
else
    warn "cargo-deny not installed — skipping license/advisory check."
    echo "   Install: cargo install cargo-deny"
    echo ""
fi

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
