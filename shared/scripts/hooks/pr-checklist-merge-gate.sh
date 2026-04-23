#!/usr/bin/env bash
# PR checklist merge gate — called from .git/hooks/pre-merge-commit.
#
# Resolves the source branch of an in-progress merge, looks up its open
# GitHub PR, and blocks the merge commit if that PR has an incomplete
# checklist (per scripts/run_pr_checklists.py --fail-on-incomplete).
#
# Auto-skips: no active merge, rebase/cherry-pick/bisect in progress,
#   unresolvable source branch, no open PR, gh missing/unauthenticated.
#
# Bypass:
#   SKIP_PR_CHECKLIST=1 git merge ...
#   PR_CHECKLIST_ACK=1  git merge ...
#
# Re-install after template setup.sh: see scripts/hooks/README.md.

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    NC=$'\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    NC=""
fi

if [[ "${SKIP_PR_CHECKLIST:-}" == "1" || "${PR_CHECKLIST_ACK:-}" == "1" ]]; then
    echo -e "🔍 pr-checklist-gate: skipped (ACK/SKIP set)."
    exit 0
fi

GIT_DIR_PATH="$(git rev-parse --git-dir)"
REPO_ROOT="$(git rev-parse --show-toplevel)"

[[ -f "$GIT_DIR_PATH/MERGE_HEAD" ]] || exit 0

for marker in REBASE_HEAD CHERRY_PICK_HEAD BISECT_LOG rebase-merge rebase-apply; do
    if [[ -e "$GIT_DIR_PATH/$marker" ]]; then
        echo -e "🔍 pr-checklist-gate: skipped (rebase/cherry-pick/bisect)."
        exit 0
    fi
done

MERGE_SHA="$(tr -d '[:space:]' <"$GIT_DIR_PATH/MERGE_HEAD" | head -c 40)"
SOURCE_BRANCH=""
if [[ -n "$MERGE_SHA" ]]; then
    while IFS= read -r ref; do
        ref="${ref#origin/}"
        [[ -z "$ref" || "$ref" == "HEAD" || "$ref" == "master" || "$ref" == "main" ]] && continue
        SOURCE_BRANCH="$ref"
        break
    done < <(git branch -a --contains "$MERGE_SHA" --format='%(refname:short)' 2>/dev/null || true)
fi
if [[ -z "$SOURCE_BRANCH" ]]; then
    echo -e "${YELLOW}⚠️  pr-checklist-gate: cannot resolve source branch, skipping.${NC}" >&2
    exit 0
fi

if ! command -v gh &>/dev/null || ! gh auth status &>/dev/null; then
    echo -e "${YELLOW}⚠️  pr-checklist-gate: gh missing/unauthenticated, skipping (CI is authoritative).${NC}" >&2
    exit 0
fi

PR_JSON="$(gh pr list --head "$SOURCE_BRANCH" --state open --json number,title,url --jq '.[0]' 2>/dev/null || echo "")"
if [[ -z "$PR_JSON" || "$PR_JSON" == "null" ]]; then
    echo -e "ℹ️  pr-checklist-gate: no open PR for '${SOURCE_BRANCH}' — skipping."
    exit 0
fi

PR_NUM="$(echo "$PR_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("number",""))')"
PR_TITLE="$(echo "$PR_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("title","").replace(chr(10)," "))')"
PR_URL="$(echo "$PR_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("url",""))')"

REPORT="/tmp/pr-checklist-premerge-${PR_NUM}.md"
OUT="/tmp/pr-checklist-gate-$$.out"
trap 'rm -f "$OUT"' EXIT

echo -e "🔍 pr-checklist-gate: validating PR #${PR_NUM} (${SOURCE_BRANCH})..."
set +e
python3 "$REPO_ROOT/scripts/run_pr_checklists.py" \
    --pr "$PR_NUM" --fail-on-incomplete --output "$REPORT" >"$OUT" 2>&1
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
    UNCHECKED="$({ grep -oE 'Unchecked \(([0-9]+)\)' "$REPORT" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo 0; })"
    {
        echo ""
        echo -e "${RED}❌ MERGE BLOCKED: PR #${PR_NUM} has an incomplete checklist.${NC}"
        echo "  Title:  ${PR_TITLE}"
        echo "  URL:    ${PR_URL}"
        echo "  Unchecked items: ${UNCHECKED}"
        echo "  Report: ${REPORT}"
        echo ""
        echo -e "${YELLOW}Resolve:${NC} tick remaining items on the PR, or bypass once:"
        echo "    SKIP_PR_CHECKLIST=1 git merge ..."
        echo ""
    } >&2
    exit 1
fi

echo -e "${GREEN}✅ pr-checklist-gate: PR #${PR_NUM} checklist complete.${NC}"
