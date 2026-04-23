#!/usr/bin/env bash
# Pre-push gate — blocks `git push` when any commit being pushed was flagged
# as non-atomic by atomicity-check.sh (see $GIT_DIR/NON_ATOMIC_COMMIT).
#
# Called from .git/hooks/pre-push. Receives git's standard stdin protocol:
#   <local-ref> <local-sha> <remote-ref> <remote-sha>
#
# Bypass:
#   ATOMICITY_ACK=1 git push ...              # acknowledge + clear sentinel entries
#   SKIP_ATOMICITY_GATE=1 git push ...        # skip entirely (discouraged)

set -euo pipefail

RED="${RED:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[0;31m' || echo '')}"
GREEN="${GREEN:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[0;32m' || echo '')}"
YELLOW="${YELLOW:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[1;33m' || echo '')}"
NC="${NC:-$([[ -t 2 && -z "${NO_COLOR:-}" ]] && echo $'\033[0m' || echo '')}"

if [[ "${SKIP_ATOMICITY_GATE:-}" == "1" ]]; then
    echo "🔍 atomicity pre-push gate skipped (SKIP_ATOMICITY_GATE=1)."
    exit 0
fi

GIT_DIR_PATH="$(git rev-parse --git-dir)"
SENTINEL="$GIT_DIR_PATH/NON_ATOMIC_COMMIT"

ZERO_SHA="0000000000000000000000000000000000000000"

# Read pre-push stdin: 4 fields per line.
# We collect every SHA that would land on the remote as part of this push.
push_shas=()
while read -r local_ref local_sha remote_ref remote_sha; do
    [[ -z "${local_ref:-}" ]] && continue
    # Branch deletion: nothing to inspect.
    if [[ "$local_sha" == "$ZERO_SHA" ]]; then
        continue
    fi
    if [[ "$remote_sha" == "$ZERO_SHA" ]]; then
        # New branch on the remote — commits not yet reachable from any remote ref.
        if git rev-parse --verify --quiet refs/remotes >/dev/null 2>&1 ||
            [[ -n "$(git for-each-ref refs/remotes 2>/dev/null)" ]]; then
            mapfile -t range < <(git rev-list "$local_sha" --not --remotes 2>/dev/null || true)
        else
            range=()
        fi
        if [[ "${#range[@]}" -eq 0 ]]; then
            # Fallback: commits on this branch not on master/main.
            local_base=""
            if git rev-parse --verify --quiet master >/dev/null; then
                local_base="master"
            elif git rev-parse --verify --quiet main >/dev/null; then
                local_base="main"
            fi
            if [[ -n "$local_base" ]]; then
                mapfile -t range < <(git rev-list "$local_sha" --not "$local_base" 2>/dev/null || true)
            else
                mapfile -t range < <(git rev-list "$local_sha" 2>/dev/null || true)
            fi
        fi
    else
        mapfile -t range < <(git rev-list "${remote_sha}..${local_sha}" 2>/dev/null || true)
    fi
    for sha in "${range[@]}"; do
        push_shas+=("$sha")
    done
done

if [[ "${#push_shas[@]}" -eq 0 ]]; then
    echo -e "${GREEN}✅ atomicity pre-push gate: no new commits to inspect.${NC}"
    exit 0
fi

if [[ ! -s "$SENTINEL" ]]; then
    echo -e "${GREEN}✅ atomicity pre-push gate: no sentinel, nothing to block.${NC}"
    exit 0
fi

# Intersect pushed commits with the sentinel.
blocked=()
for sha in "${push_shas[@]}"; do
    if grep -q "^${sha}[[:space:]]" "$SENTINEL" 2>/dev/null; then
        blocked+=("$sha")
    fi
done

if [[ "${#blocked[@]}" -eq 0 ]]; then
    echo -e "${GREEN}✅ atomicity pre-push gate: all ${#push_shas[@]} pushed commits are atomic.${NC}"
    exit 0
fi

if [[ "${ATOMICITY_ACK:-}" == "1" ]]; then
    echo -e "${YELLOW}⚠️  atomicity pre-push gate: ACK set — ${#blocked[@]} non-atomic commit(s) will be pushed.${NC}" >&2
    # Drop acknowledged SHAs from the sentinel so they don't keep blocking later pushes.
    tmp="$(mktemp)"
    cp "$SENTINEL" "$tmp"
    for sha in "${blocked[@]}"; do
        grep -v "^${sha}[[:space:]]" "$tmp" >"$tmp.new" || true
        mv "$tmp.new" "$tmp"
    done
    if [[ -s "$tmp" ]]; then
        mv "$tmp" "$SENTINEL"
    else
        rm -f "$tmp" "$SENTINEL"
    fi
    exit 0
fi

{
    echo ""
    echo -e "${RED}❌ PUSH BLOCKED: ${#blocked[@]} non-atomic commit(s) in the push range.${NC}"
    echo ""
    for sha in "${blocked[@]}"; do
        reason="$(grep "^${sha}[[:space:]]" "$SENTINEL" | head -1 | cut -f2-)"
        subject="$(git log -1 --format=%s "$sha" 2>/dev/null || echo '(unknown)')"
        echo "   • ${sha:0:12}  ${subject}"
        echo "       reason: ${reason}"
    done
    echo ""
    echo -e "${YELLOW}Resolve by one of:${NC}"
    echo "   • Split offending commits:      git rebase -i <base>   (edit / split)"
    echo "   • Squash into a coherent unit:  git rebase -i <base>   (if truly one change)"
    echo "   • Acknowledge & push anyway:    ATOMICITY_ACK=1 git push ..."
    echo ""
} >&2
exit 1
