#!/usr/bin/env bash
# Configure the GitHub repo so only "Rebase and Merge" is allowed.
#
# Why: the commit-atomicity gates (git-absorb + post-commit classifier +
# pre-push gate) only preserve atomic history if the merge strategy keeps
# individual commits. Squash-merge collapses them to one; a merge commit
# inserts extra noise. Rebase-and-merge is the only option that preserves
# the atomic commits the gates were designed to protect.
#
# This script is OPT-IN. It edits the remote repo settings, so it requires:
#   - `gh` CLI authenticated with a token that has "admin:repo" scope
#   - admin access on the target repository
#
# Usage (from inside a cloned repo):
#   bash scripts/configure-merge-strategy.sh
#
# Usage (explicit repo):
#   bash scripts/configure-merge-strategy.sh <owner>/<repo>
#
# Re-run safe: the `gh repo edit` call is idempotent.

set -euo pipefail

RED="${RED:-$([[ -t 2 ]] && echo $'\033[0;31m' || echo '')}"
GREEN="${GREEN:-$([[ -t 2 ]] && echo $'\033[0;32m' || echo '')}"
YELLOW="${YELLOW:-$([[ -t 2 ]] && echo $'\033[1;33m' || echo '')}"
BOLD="${BOLD:-$([[ -t 2 ]] && echo $'\033[1m' || echo '')}"
NC="${NC:-$([[ -t 2 ]] && echo $'\033[0m' || echo '')}"

die() {
    echo -e "${RED}❌ $*${NC}" >&2
    exit 1
}

if ! command -v gh &>/dev/null; then
    die "gh CLI not found. Install: https://cli.github.com/"
fi

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
    # Detect from current repo's origin URL.
    if ! REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"; then
        die "Could not detect <owner>/<repo>. Run inside a clone or pass explicitly: bash $0 <owner>/<repo>"
    fi
fi

echo -e "${BOLD}Configuring merge strategy for:${NC} $REPO"
echo "  • allow-squash-merge  →  false"
echo "  • allow-merge-commit  →  false"
echo "  • allow-rebase-merge  →  true"
echo "  • delete-branch-on-merge → true  (keeps branch list tidy)"
echo ""

read -r -p "Proceed? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# gh repo edit does not expose --allow-squash-merge/--allow-merge-commit/
# --allow-rebase-merge on all gh versions (the flags are gh >= 2.43 on some
# builds, and the boolean `=false` form is not always parsed). Use the REST
# API directly — the PATCH endpoint is stable and idempotent.
gh api --method PATCH "repos/$REPO" \
    -F allow_squash_merge=false \
    -F allow_merge_commit=false \
    -F allow_rebase_merge=true \
    -F delete_branch_on_merge=true \
    --jq '"squash=\(.allow_squash_merge)  merge-commit=\(.allow_merge_commit)  rebase=\(.allow_rebase_merge)  delete-branch=\(.delete_branch_on_merge)"'

echo ""
echo -e "${GREEN}✅ Merge strategy enforced: only Rebase-and-Merge is allowed.${NC}"
echo ""
echo -e "${YELLOW}Next steps — highly recommended (branch protection, level 2):${NC}"
echo "  Require linear history on the default branch. GitHub UI:"
echo "    Settings → Branches → Branch protection rules → (master/main) →"
echo "      ✔ Require a pull request before merging"
echo "      ✔ Require linear history"
echo "      ✔ Require status checks to pass before merging"
echo "  Or via gh api (example, pinning protection on 'master'):"
echo "    gh api -X PUT repos/$REPO/branches/master/protection \\"
echo "      -f required_linear_history=true \\"
echo "      -f enforce_admins=true \\"
echo "      -f required_pull_request_reviews='{\"required_approving_review_count\":1}' \\"
echo "      -f restrictions=null \\"
echo "      -f required_status_checks='{\"strict\":true,\"contexts\":[]}'"
echo ""
echo "  See also: TEMPLATE_ROADMAP.md entry 'branch-protection (level 2)'."