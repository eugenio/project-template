#!/usr/bin/env bash
# Configure the GitHub repo so only "Rebase and Merge" is allowed, and
# optionally pin branch protection on the default branch.
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
# Usage:
#   bash scripts/configure-merge-strategy.sh [<owner>/<repo>] [flags]
#
# Flags:
#   --protect-branch [BRANCH]   After setting the merge strategy, pin branch
#                               protection on BRANCH (default: the repo's
#                               default branch). Requires admin.
#                               Applies: required_linear_history=true,
#                                        enforce_admins=true,
#                                        required_status_checks strict=true,
#                                        restrictions=null.
#   --min-reviews N             With --protect-branch, require N approving
#                               reviews per PR. Default: 0 (solo-dev friendly).
#   --dry-run                   Print the payloads that would be sent and
#                               exit — do NOT call the GitHub API.
#   -h, --help                  Show this help.
#
# Re-run safe: both the repo-settings PATCH and the branch-protection PUT
# are idempotent.

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

show_help() {
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
REPO=""
PROTECT_BRANCH=""       # empty when --protect-branch not given
PROTECT_REQUESTED=0     # 1 after we see --protect-branch (even without value)
MIN_REVIEWS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --protect-branch)
            PROTECT_REQUESTED=1
            # Optional branch name: consume it if the next arg isn't another flag.
            if [[ $# -ge 2 && ! "$2" =~ ^-- && ! "$2" =~ / ]]; then
                PROTECT_BRANCH="$2"
                shift 2
            else
                shift
            fi
            ;;
        --min-reviews)
            [[ $# -ge 2 ]] || die "--min-reviews needs an integer"
            MIN_REVIEWS="$2"
            [[ "$MIN_REVIEWS" =~ ^[0-9]+$ ]] || die "--min-reviews must be a non-negative integer, got: $MIN_REVIEWS"
            shift 2
            ;;
        -*)
            die "Unknown flag: $1  (run with --help)"
            ;;
        */*)
            REPO="$1"
            shift
            ;;
        *)
            die "Unknown positional argument: $1  (expected <owner>/<repo>)"
            ;;
    esac
done

if ! command -v gh &>/dev/null; then
    die "gh CLI not found. Install: https://cli.github.com/"
fi

if [[ -z "$REPO" ]]; then
    # Detect from current repo's origin URL.
    if [[ "$DRY_RUN" -eq 1 ]]; then
        die "--dry-run requires an explicit <owner>/<repo> argument (cannot auto-detect reliably)"
    fi
    if ! REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"; then
        die "Could not detect <owner>/<repo>. Run inside a clone or pass explicitly: bash $0 <owner>/<repo>"
    fi
fi

# Resolve branch for --protect-branch if not given explicitly.
if [[ "$PROTECT_REQUESTED" -eq 1 && -z "$PROTECT_BRANCH" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        # In dry-run mode with a fake repo, default to "master" so the payload
        # is inspectable; real runs still resolve from the API.
        PROTECT_BRANCH="master"
    else
        PROTECT_BRANCH="$(gh api "repos/$REPO" --jq .default_branch 2>/dev/null)" \
            || die "Could not resolve default branch for $REPO"
    fi
fi

# ---------------------------------------------------------------------------
# Print plan + confirm (skipped in dry-run)
# ---------------------------------------------------------------------------
echo -e "${BOLD}Configuring merge strategy for:${NC} $REPO"
echo "  • allow_squash_merge       →  false"
echo "  • allow_merge_commit       →  false"
echo "  • allow_rebase_merge       →  true"
echo "  • delete_branch_on_merge   →  true"
if [[ "$PROTECT_REQUESTED" -eq 1 ]]; then
    echo ""
    echo -e "${BOLD}Branch protection (level 2) on:${NC} $PROTECT_BRANCH"
    echo "  • required_linear_history  →  true"
    echo "  • enforce_admins           →  true"
    echo "  • required_status_checks   →  { strict: true, contexts: [] }"
    echo "  • restrictions             →  null (anyone can open PRs)"
    if [[ "$MIN_REVIEWS" -gt 0 ]]; then
        echo "  • required_approving_review_count  →  $MIN_REVIEWS"
    else
        echo "  • pull-request reviews             →  not enforced (count=0)"
    fi
fi
echo ""

if [[ "$DRY_RUN" -eq 0 ]]; then
    read -r -p "Proceed? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# 1. Merge strategy — idempotent PATCH on the repo endpoint
# ---------------------------------------------------------------------------
MERGE_PAYLOAD='{
  "allow_squash_merge": false,
  "allow_merge_commit": false,
  "allow_rebase_merge": true,
  "delete_branch_on_merge": true
}'

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo -e "${YELLOW}[dry-run] would PATCH repos/$REPO${NC}"
    echo "$MERGE_PAYLOAD"
    echo ""
else
    echo "$MERGE_PAYLOAD" \
        | gh api --method PATCH "repos/$REPO" --input - \
            --jq '"squash=\(.allow_squash_merge)  merge-commit=\(.allow_merge_commit)  rebase=\(.allow_rebase_merge)  delete-branch=\(.delete_branch_on_merge)"'
    echo -e "${GREEN}✅ Merge strategy enforced: only Rebase-and-Merge is allowed.${NC}"
fi

# ---------------------------------------------------------------------------
# 2. Branch protection — PUT on the protection endpoint
# ---------------------------------------------------------------------------
if [[ "$PROTECT_REQUESTED" -eq 1 ]]; then
    # GitHub's PUT /branches/:branch/protection REQUIRES all four top-level
    # fields. To disable a constraint, send null rather than omitting the key.
    # MIN_REVIEWS=0 → null so solo-dev repos aren't locked out; MIN_REVIEWS>0
    # → enforce the count.
    if [[ "$MIN_REVIEWS" -gt 0 ]]; then
        PR_REVIEWS_VALUE="{\"required_approving_review_count\": $MIN_REVIEWS}"
    else
        PR_REVIEWS_VALUE="null"
    fi

    PROTECTION_PAYLOAD="{
  \"required_linear_history\": true,
  \"enforce_admins\": true,
  \"restrictions\": null,
  \"required_status_checks\": {\"strict\": true, \"contexts\": []},
  \"required_pull_request_reviews\": $PR_REVIEWS_VALUE
}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo -e "${YELLOW}[dry-run] would PUT repos/$REPO/branches/$PROTECT_BRANCH/protection${NC}"
        echo "$PROTECTION_PAYLOAD"
        echo ""
    else
        echo ""
        echo -e "${BOLD}Applying branch protection on $PROTECT_BRANCH…${NC}"
        echo "$PROTECTION_PAYLOAD" \
            | gh api --method PUT "repos/$REPO/branches/$PROTECT_BRANCH/protection" --input - \
                --jq '"linear_history=\(.required_linear_history.enabled)  enforce_admins=\(.enforce_admins.enabled)  strict_status=\(.required_status_checks.strict)"' \
            || die "Branch protection PUT failed. Check token scope (admin:repo) and repo plan (linear_history requires Pro/Team on private repos)."
        echo -e "${GREEN}✅ Branch protection applied on $PROTECT_BRANCH.${NC}"
    fi
fi

# ---------------------------------------------------------------------------
# Final guidance
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 0 && "$PROTECT_REQUESTED" -eq 0 ]]; then
    echo ""
    echo -e "${YELLOW}Optional follow-up — branch protection (level 2):${NC}"
    echo "  Re-run with --protect-branch to enforce required_linear_history + enforce_admins:"
    echo "    bash $0 $REPO --protect-branch"
    echo ""
    echo "  See also: TEMPLATE_ROADMAP.md entry 'branch-protection (level 2)'."
fi