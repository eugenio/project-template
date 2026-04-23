# Template Roadmap — Post-Setup Follow-Ups

Tracked follow-up work that `setup.sh` intentionally does NOT automate,
usually because the operation affects the remote repo (requires admin +
`gh` auth) or an organization-level setting (requires owner permission).

Each entry lists the current state, the target state, and a concrete
implementation plan so a future LLM or human can finish it without
re-discovering the context.

## ✅ branch-protection (level 2) — completed

**Status.** Implemented in `shared/scripts/configure-merge-strategy.sh`
via the `--protect-branch [BRANCH]` flag. Default branch is resolved
automatically through the GitHub API. Configurable review count via
`--min-reviews N` (default 0, solo-dev friendly). Dry-run preview via
`--dry-run`.

**What it configures (PUT on `repos/$REPO/branches/$BRANCH/protection`).**

- `required_linear_history = true` — rebase-only at the branch layer,
  so re-enabling squash-merge in repo settings still cannot land
  non-linear history.
- `enforce_admins = true` — nobody bypasses the gate, not even admins.
- `required_status_checks = {strict: true, contexts: []}` — strict mode
  ensures the branch is up-to-date with base before merge.
- `restrictions = null` — any collaborator can open PRs.
- `required_pull_request_reviews` — only emitted when `--min-reviews > 0`,
  so solo-dev repos (where you cannot review your own PR) aren't locked
  out of merging.

**Remaining caveats (see also the script header).**

- GitHub-only. GitLab equivalent ("Fast-forward merge" under Settings
  → Merge requests) is not yet wired; would need remote-type detection
  in the script. Tracked as a future follow-up.
- Private repos on a Free plan cannot set branch protection at all;
  the script surfaces the GitHub error in that case.
- `required_status_checks.contexts=[]` is intentional — the list is
  appended as CI jobs are introduced. Nothing for `setup.sh` to do.
