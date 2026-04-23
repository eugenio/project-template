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