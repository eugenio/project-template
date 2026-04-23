#!/usr/bin/env bash
# git-absorb atomicity gate — called from .git/hooks/pre-commit (final step).
#
# Runs `git-absorb --dry-run --base <base>` on staged changes. If a fixup
# candidate is found, the commit is blocked and the user is prompted to
# either absorb into history or explicitly acknowledge the new commit.
#
# Bypass:
#   ABSORB_ACK=1 git commit ...          # decided this IS a new atomic commit
#   SKIP_ABSORB_CHECK=1 git commit ...   # skip entirely (discouraged)
#
# Auto-skips on: merge / rebase / cherry-pick in progress, master branch,
# missing git-absorb binary, or no master / origin/master ref.
#
# Install / re-install after template setup.sh:
#   See scripts/hooks/README.md (one-liner to append to .git/hooks/pre-commit).

set -euo pipefail

# Color helpers — only used when stdout is a TTY or parent hook set them.
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
NC="${NC:-\033[0m}"

if [[ "${ABSORB_ACK:-}" == "1" ]] || [[ "${SKIP_ABSORB_CHECK:-}" == "1" ]]; then
    echo -e "🔍 git-absorb check skipped (ACK/SKIP set)."
    exit 0
fi

if ! command -v git-absorb &>/dev/null; then
    echo -e "${YELLOW}⚠️  git-absorb not found — skipping atomicity check.${NC}" >&2
    exit 0
fi

GIT_DIR_PATH="$(git rev-parse --git-dir)"
if [[ -f "$GIT_DIR_PATH/MERGE_HEAD" ]] ||
    [[ -d "$GIT_DIR_PATH/rebase-merge" ]] ||
    [[ -d "$GIT_DIR_PATH/rebase-apply" ]] ||
    [[ -f "$GIT_DIR_PATH/CHERRY_PICK_HEAD" ]]; then
    echo -e "🔍 git-absorb check skipped (merge/rebase/cherry-pick in progress)."
    exit 0
fi

ABSORB_BASE=""
if git rev-parse --verify --quiet origin/master >/dev/null; then
    ABSORB_BASE="origin/master"
elif git rev-parse --verify --quiet master >/dev/null; then
    ABSORB_BASE="master"
fi
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"

if [[ -z "$ABSORB_BASE" ]]; then
    echo -e "🔍 git-absorb check skipped (no master/origin/master ref)."
    exit 0
fi
if [[ "$CURRENT_BRANCH" == "master" ]]; then
    echo -e "🔍 git-absorb check skipped (on master branch)."
    exit 0
fi

echo -e "🔍 Running git-absorb --dry-run against $ABSORB_BASE..."
ABSORB_OUT="$(git-absorb --dry-run --base "$ABSORB_BASE" 2>&1 || true)"

if echo "$ABSORB_OUT" | grep -qiE 'would have committed|would absorb|fixup:'; then
    {
        echo ""
        echo -e "${RED}❌ COMMIT BLOCKED: git-absorb found a fixup candidate.${NC}"
        echo ""
        echo "The staged change looks like it belongs in a previous commit on this branch:"
        echo ""
        echo "$ABSORB_OUT" | sed 's/^/    /'
        echo ""
        echo -e "${YELLOW}Decide:${NC}"
        echo "  • Absorb into history (preserves atomic commits):"
        echo "      git-absorb --and-rebase --base $ABSORB_BASE"
        echo "  • OR this is genuinely a new atomic commit — acknowledge:"
        echo "      ABSORB_ACK=1 git commit ..."
    } >&2
    exit 1
fi

echo -e "${GREEN}✅ No absorb candidates — change looks like a genuine new commit.${NC}"