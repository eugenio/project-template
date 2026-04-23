#!/usr/bin/env bash
# Post-commit atomicity check — classifies HEAD's changed paths into logical
# areas and flags the commit as non-atomic if it spans 3+ independent areas.
# Non-atomic commits are appended to $GIT_DIR/NON_ATOMIC_COMMIT; the pre-push
# gate (pre-push-atomicity-gate.sh) consumes that sentinel to block pushes.
#
# Bypass:
#   SKIP_ATOMICITY_CHECK=1 git commit ...   # disable this run
#
# Auto-skips on: master branch, merge commits, initial commit, and
# merge/rebase/cherry-pick in progress. Exit code is advisory (0/1) for use
# outside the post-commit hook; the installed hook never aborts on its own
# because post-commit cannot undo the commit.

set -euo pipefail

RED="${RED:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[0;31m' || echo '')}"
GREEN="${GREEN:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[0;32m' || echo '')}"
YELLOW="${YELLOW:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[1;33m' || echo '')}"
NC="${NC:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[0m' || echo '')}"

if [[ "${SKIP_ATOMICITY_CHECK:-}" == "1" ]]; then
    echo "🔍 atomicity check skipped (SKIP_ATOMICITY_CHECK=1)."
    exit 0
fi

GIT_DIR_PATH="$(git rev-parse --git-dir)"
if [[ -f "$GIT_DIR_PATH/MERGE_HEAD" ]] ||
    [[ -d "$GIT_DIR_PATH/rebase-merge" ]] ||
    [[ -d "$GIT_DIR_PATH/rebase-apply" ]] ||
    [[ -f "$GIT_DIR_PATH/CHERRY_PICK_HEAD" ]]; then
    echo "🔍 atomicity check skipped (merge/rebase/cherry-pick in progress)."
    exit 0
fi

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "main" ]]; then
    echo "🔍 atomicity check skipped (on $CURRENT_BRANCH branch)."
    exit 0
fi

HEAD_SHA="$(git rev-parse HEAD)"

# Initial commit? No parents → skip; nothing to compare against.
PARENT_COUNT="$(git cat-file -p "$HEAD_SHA" | grep -c '^parent ' || true)"
if [[ "$PARENT_COUNT" -eq 0 ]]; then
    echo "🔍 atomicity check skipped (initial commit)."
    exit 0
fi
if [[ "$PARENT_COUNT" -gt 1 ]]; then
    echo "🔍 atomicity check skipped (merge commit, $PARENT_COUNT parents)."
    exit 0
fi

# List paths changed by HEAD (vs its sole parent).
mapfile -t CHANGED_FILES < <(git diff-tree --no-commit-id --name-only -r "$HEAD_SHA")

if [[ "${#CHANGED_FILES[@]}" -eq 0 ]]; then
    echo "🔍 atomicity check: commit has no file changes, nothing to classify."
    exit 0
fi

# Classify each file into a logical area. Support areas (docs/scripts/ci/
# root-config) are returned but filtered out when counting independence.
classify() {
    local path="$1"
    case "$path" in
        plugins/*/*)
            # plugins/<name>/...
            local name="${path#plugins/}"
            name="${name%%/*}"
            printf 'plugin:%s' "$name"
            return
            ;;
        tests/unit/*/*)
            local name="${path#tests/unit/}"
            name="${name%%/*}"
            printf 'plugin:%s' "$name"
            return
            ;;
        tests/integration/test_*)
            local base="${path#tests/integration/test_}"
            local name="${base%%_*}"
            name="${name%.py}"
            printf 'plugin:%s' "$name"
            return
            ;;
        workers/*) printf 'workers' ;;
        gateway/*) printf 'gateway' ;;
        docs/*) printf 'docs' ;;
        scripts/*) printf 'scripts' ;;
        infra/*) printf 'infra' ;;
        .github/*) printf 'ci' ;;
        tests/*) printf 'tests-misc' ;;
        */*)
            # Other nested paths: use the top-level component as area.
            printf '%s' "${path%%/*}"
            ;;
        *)
            # Root-level file (pixi.lock, pyproject.toml, .gitignore, etc.).
            printf 'root-config'
            ;;
    esac
}

# Areas we treat as "support" — they do not count as an independent logical
# area on their own. A commit may bundle them with a real change area.
is_support_area() {
    case "$1" in
        docs | scripts | ci | root-config | infra) return 0 ;;
        *) return 1 ;;
    esac
}

declare -A AREAS=()
declare -A SUPPORT_AREAS=()
for f in "${CHANGED_FILES[@]}"; do
    area="$(classify "$f")"
    if is_support_area "$area"; then
        SUPPORT_AREAS["$area"]=1
    else
        AREAS["$area"]=1
    fi
done

INDEPENDENT_COUNT="${#AREAS[@]}"
AREAS_LIST="$(printf '%s\n' "${!AREAS[@]}" | sort | paste -sd ', ' -)"

# Threshold: 3+ independent areas in a single commit is strong evidence that
# multiple logical changes were bundled together. Two areas are often legit
# (e.g. plugin + its direct consumer in workers/). We stay conservative.
THRESHOLD="${ATOMICITY_THRESHOLD:-3}"

SENTINEL="$GIT_DIR_PATH/NON_ATOMIC_COMMIT"

if [[ "$INDEPENDENT_COUNT" -ge "$THRESHOLD" ]]; then
    REASON="touches $INDEPENDENT_COUNT independent areas: $AREAS_LIST"
    {
        echo ""
        echo -e "${RED}❌ NON-ATOMIC COMMIT DETECTED${NC}"
        echo "   commit: $HEAD_SHA"
        echo "   reason: $REASON"
        echo ""
        echo -e "${YELLOW}The commit will remain in history but is marked as non-atomic.${NC}"
        echo "   A pre-push gate will block \`git push\` until resolved."
        echo ""
        echo -e "${YELLOW}Resolve by one of:${NC}"
        echo "   • Split the commit:        git reset --soft HEAD~1 && git commit -p ..."
        echo "   • Rewrite via interactive: git rebase -i HEAD~1   (edit / split)"
        echo "   • Acknowledge this push:   ATOMICITY_ACK=1 git push ..."
        echo ""
    } >&2

    # Append to sentinel: one line per offending commit.
    printf '%s\t%s\n' "$HEAD_SHA" "$REASON" >>"$SENTINEL"
    exit 1
fi

# Atomic — if the sentinel lists this SHA for some reason, drop the entry.
if [[ -f "$SENTINEL" ]]; then
    tmp="$(mktemp)"
    grep -v "^${HEAD_SHA}[[:space:]]" "$SENTINEL" >"$tmp" || true
    if [[ -s "$tmp" ]]; then
        mv "$tmp" "$SENTINEL"
    else
        rm -f "$tmp" "$SENTINEL"
    fi
fi

echo -e "${GREEN}✅ atomicity check: commit spans ${INDEPENDENT_COUNT} independent area(s)${AREAS_LIST:+ ($AREAS_LIST)}.${NC}"
exit 0
