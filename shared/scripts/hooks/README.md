# Git hook extensions

Version-controlled hook logic that complements the pre-commit hook installed
by `setup.sh` into `.git/hooks/pre-commit`. Content here is tracked in the
project repository; `.git/hooks/` is not tracked — so if `setup.sh` is re-run
and overwrites the hook, re-apply the one-liner below.

## `git-absorb-gate.sh`

Atomicity gate (final step of pre-commit). Runs `git-absorb --dry-run` on
staged changes and blocks the commit if the change looks like a fixup of a
previous commit on the branch. See the script header for bypass flags.

### What the gate does

1. Calls `git-absorb --dry-run --base <origin/master|master>` on the staged diff.
2. If git-absorb reports a fixup candidate it prints the candidate and blocks
   the commit (`exit 1`).
3. You then choose to either absorb the change into the correct commit with
   `git-absorb --and-rebase` or acknowledge that it really is a new commit.

### Bypass env vars

| Variable | Effect |
|---|---|
| `ABSORB_ACK=1` | This IS a new atomic commit — I verified manually. Gate passes. |
| `SKIP_ABSORB_CHECK=1` | Disable the gate entirely for this commit. Discouraged. |

Both are single-commit bypasses (env vars are not persisted).

### Auto-skips

The gate automatically skips when:

- `git-absorb` binary is not installed (`pixi global install git-absorb` or
  `cargo install git-absorb` or `apt install git-absorb`)
- A merge, rebase, or cherry-pick is in progress
- The current branch is `master` (direct master commits bypass by design)
- No `origin/master` or `master` ref exists yet (e.g. fresh repo before first push)

### Install / re-install after `setup.sh`

`setup.sh` installs this gate automatically. If you re-run `setup.sh` and the
pre-commit hook is regenerated, the gate step is already baked in — no manual
action is required.

If you ever need to re-append the gate step manually (e.g. after a manual hook
edit that lost the last block), add this to the end of `.git/hooks/pre-commit`:

```bash
# ---------------------------------------------------------------------------
# N. git-absorb atomicity gate (logic in scripts/hooks/git-absorb-gate.sh)
# Re-install after template setup.sh: see scripts/hooks/README.md.
# ---------------------------------------------------------------------------
ABSORB_GATE="$(git rev-parse --show-toplevel)/scripts/hooks/git-absorb-gate.sh"
if [[ -x "$ABSORB_GATE" ]]; then
    RED="$RED" GREEN="$GREEN" YELLOW="$YELLOW" NC="$NC" \
        bash "$ABSORB_GATE" || exit 1
    echo ""
else
    echo -e "\033[1;33m⚠️  atomicity gate script missing: $ABSORB_GATE\033[0m"
    echo ""
fi
```

## `atomicity-check.sh` (post-commit)

Post-commit classifier. Complements the pre-commit `git-absorb-gate.sh`:
where the absorb gate catches *fixups* (one small change that belongs in an
earlier commit), this check catches *wide* commits (one commit that bundles
unrelated changes).

### What the check does

1. Runs on every commit via `.git/hooks/post-commit`.
2. Classifies each path changed by `HEAD` into a logical area:
   `plugin:<name>` (for `plugins/<name>/…` or `tests/unit/<name>/…`),
   `workers`, `gateway`, `docs`, `scripts`, `infra`, `ci`, `tests-misc`,
   or `root-config` (top-level files).
3. Counts *independent* areas — support areas (`docs`, `scripts`, `ci`,
   `infra`, `root-config`) don't contribute. Threshold is `3`
   (override with `ATOMICITY_THRESHOLD=<N>`).
4. If the commit spans ≥ threshold independent areas, appends
   `<sha>\t<reason>` to `.git/NON_ATOMIC_COMMIT` and prints a warning.
   The post-commit hook never aborts the commit — it already landed —
   but the sentinel becomes the signal the pre-push gate consumes.
5. On an atomic commit, any existing sentinel row for that SHA is pruned.

### Bypass env vars (atomicity check)

| Variable                  | Effect                                                       |
| ------------------------- | ------------------------------------------------------------ |
| `SKIP_ATOMICITY_CHECK=1`  | Disable the check for this commit. Discouraged.              |
| `ATOMICITY_THRESHOLD=<N>` | Override the default independence threshold (3).             |

### Auto-skips (atomicity check)

- Current branch is `master` or `main`.
- Initial commit (no parent) or merge commit (multiple parents).
- A merge, rebase, or cherry-pick is in progress.

## `pre-push-atomicity-gate.sh` (pre-push)

Pre-push gate. Reads git's standard pre-push stdin protocol, computes every
commit that would land on the remote, intersects them with
`.git/NON_ATOMIC_COMMIT`, and **blocks the push** if any pushed commit is
flagged. Each blocked commit is printed with its subject and the reason the
post-commit check recorded.

### Bypass env vars (pre-push gate)

| Variable                 | Effect                                                                                              |
| ------------------------ | --------------------------------------------------------------------------------------------------- |
| `ATOMICITY_ACK=1`        | Push anyway. Acknowledged SHAs are removed from the sentinel so they stop blocking future pushes.   |
| `SKIP_ATOMICITY_GATE=1`  | Disable the gate entirely for this push. Discouraged.                                               |

### Install / re-install the post-commit and pre-push hooks

`setup.sh` installs both `.git/hooks/post-commit` and `.git/hooks/pre-push`
automatically. If you ever need to restore them manually:

```bash
# .git/hooks/post-commit
cat >.git/hooks/post-commit <<'HOOK'
#!/usr/bin/env bash
set -e
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[[ -z "$REPO_ROOT" ]] && exit 0
CHECK="$REPO_ROOT/scripts/hooks/atomicity-check.sh"
[[ -x "$CHECK" ]] && bash "$CHECK" || true
HOOK
chmod +x .git/hooks/post-commit

# .git/hooks/pre-push
cat >.git/hooks/pre-push <<'HOOK'
#!/usr/bin/env bash
set -e
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[[ -z "$REPO_ROOT" ]] && exit 0
GATE="$REPO_ROOT/scripts/hooks/pre-push-atomicity-gate.sh"
[[ -x "$GATE" ]] && bash "$GATE" "$@" || exit 1
HOOK
chmod +x .git/hooks/pre-push
```