# Template Roadmap — Post-Setup Follow-Ups

Tracked follow-up work that `setup.sh` intentionally does NOT automate,
usually because the operation affects the remote repo (requires admin +
`gh` auth) or an organization-level setting (requires owner permission).

Each entry lists the current state, the target state, and a concrete
implementation plan so a future LLM or human can finish it without
re-discovering the context.

## branch-protection (level 2)

**Context.** The commit-atomicity gates (commit-msg + pre-commit +
post-commit + pre-push) protect atomic history locally. The rebase-only
merge strategy (`scripts/configure-merge-strategy.sh` + the PR template
block) is **level 1 + 4** and protects atomic history at PR-merge time.

What's missing is **level 2** — branch protection on the default branch
so that nobody can bypass the gates (not even admins) by pushing directly
or clicking a non-rebase merge button if the repo settings were later
relaxed.

**Current state.** `configure-merge-strategy.sh` prints a reminder to the
operator but does NOT call the GitHub protection API. Branch protection
must be enabled manually via Settings → Branches → Branch protection
rules.

**Target state.** A single idempotent command that configures the default
branch with:

- `required_linear_history = true` — rebase-only; mirrors the merge
  strategy constraint at the branch-protection layer so re-enabling
  squash-merge in repo settings still cannot land non-linear history.
- `required_pull_request_reviews.required_approving_review_count >= 1`
  (tunable).
- `required_status_checks.strict = true` with an initial empty `contexts`
  list (CI jobs are added as the project grows).
- `enforce_admins = true` — nobody bypasses the gate, not even admins.
- `restrictions = null` — any collaborator can open PRs.

**Implementation plan.**

1. Extend `shared/scripts/configure-merge-strategy.sh` with a new flag
   `--protect-branch <branch>` (default: the repo's default branch).
2. When the flag is set, after the `gh repo edit` call, issue:

   ```bash
   gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
     -f required_linear_history=true \
     -f enforce_admins=true \
     -f required_pull_request_reviews='{"required_approving_review_count":1}' \
     -f restrictions=null \
     -f required_status_checks='{"strict":true,"contexts":[]}'
   ```

3. Validate by re-reading the protection with
   `gh api "repos/$REPO/branches/$BRANCH/protection" --jq .required_linear_history.enabled`.
4. Update `LLM_INSTRUCTIONS.md` "Why rebase-only merges matter" section
   to drop the "not yet automated" caveat and point at the new flag.
5. Update `.github/PULL_REQUEST_TEMPLATE.md.template` to note that the
   level-2 protection is active (optional — the UI already reflects it).

**Caveats.**

- `required_linear_history` is supported only on GitHub (not GitLab).
  For GitLab the equivalent is "Fast-forward merge" under Settings →
  Merge requests; plan to add a branch in the script to detect remote
  type and issue the appropriate call.
- Private repos on a Free plan cannot set branch protection; the script
  must detect that case and fall back to a warning.
- Applying protection on a repo that has no CI yet sets `contexts=[]`.
  When CI jobs are added later, the list must be updated — not a
  concern for `setup.sh` itself, but worth flagging in the script's
  help text.