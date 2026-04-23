# Project Template — LLM Usage Instructions

## Purpose

This template system standardizes project configuration across Python, Rust, and TypeScript projects. When asked to "set up a new project" or "align project settings", follow these instructions exactly.

## Template Location

`scripts/project-template/` in the project-PEAK repository, structured as:

```
scripts/project-template/
├── setup.sh                    # Automated installer
├── README.md                   # Human-readable guide
├── LLM_INSTRUCTIONS.md         # This file — AI agent usage guide
├── shared/                     # Language-agnostic configs
│   ├── .releaserc.yml.template
│   ├── package.json.template
│   ├── .gitleaksignore.template
│   ├── .gitignore-additions.template
│   └── .editorconfig.template
├── python/
│   ├── pyproject.toml.template
│   ├── .coveragerc.template
│   └── pre-commit-hook.sh
├── rust/
│   ├── clippy.toml.template
│   ├── rustfmt.toml.template
│   └── pre-commit-hook.sh
└── typescript/
    ├── tsconfig.json.template
    ├── eslint.config.mjs.template
    └── pre-commit-hook.sh
```

## Workflow: New Project Setup

### Step 1 — Detect Language

Determine the primary language by checking for:

- `pyproject.toml` or `pixi.toml` → Python
- `Cargo.toml` → Rust
- `package.json` with `src/**/*.ts` files → TypeScript

If mixed, use the primary language for the hook and merge configs from all relevant directories.

### Step 2 — Run setup.sh (preferred) or Manual Setup

**Automated:**

```bash
bash scripts/project-template/setup.sh --lang <python|rust|typescript> --project-dir /path/to/project
```

**Manual (if setup.sh is unavailable or needs customization):**

1. Copy all files from `shared/` to the project root, removing the `.template` suffix
2. Copy language-specific files from `<lang>/`, removing the `.template` suffix
3. Install the pre-commit hook:
   ```bash
   cp scripts/project-template/<lang>/pre-commit-hook.sh /path/to/project/.git/hooks/pre-commit
   chmod +x /path/to/project/.git/hooks/pre-commit
   ```

### Step 3 — Adapt Templates

Search for all `# ADAPT:` comments in the copied files. Each one is a mandatory customization point — do not leave them as-is.

**Python projects:**

- `pyproject.toml`: Set `known-first-party` to the project's actual package names
- `.coveragerc`: Set `source` to the project's source directories
- `pre-commit-hook.sh`: Update `SOURCE_DIRS`, `TEST_DIR`, `COV_TARGETS`, `COVERAGE_GATE`, `DOCSTRING_GATE`
- `package.json`: Set `name` to the project name (used by semantic-release)
- `.releaserc.yml`: Set `branches` if the default branch is not `main`

**Rust projects:**

- `clippy.toml`: Adjust complexity thresholds if project has justified exceptions
- `pre-commit-hook.sh`: Update `CARGO_TARGETS` and test flags

**TypeScript projects:**

- `tsconfig.json`: Set `paths`, `outDir`, `rootDir` to match the project layout
- `eslint.config.mjs`: Add project-specific rules or disable rules with justification
- `pre-commit-hook.sh`: Update test command and source dirs

### Step 4 — Merge with Existing Config

If the project already has config files (e.g., an existing `pyproject.toml`):

- **NEVER overwrite** — always MERGE
- Read the existing file first
- Add missing tool sections from the template (e.g., `[tool.ruff]`, `[tool.mypy]`)
- Update values to match the template standard (e.g., `line-length = 100`)
- Preserve project-specific overrides (e.g., mypy `[[tool.mypy.overrides]]` for untyped third-party libraries)

### Step 5 — Verify

Run the pre-commit hook manually to confirm everything works before committing:

```bash
cd /path/to/project && .git/hooks/pre-commit
```

Fix every failure before proceeding. A hook that fails on a clean tree means the setup is incomplete.

**Five additional hooks installed by `setup.sh`:**

- **`commit-msg`** (`shared/commit-msg-hook.sh` → `.git/hooks/commit-msg`): runs
  `npx commitlint --edit "$1"` to validate the commit message against the angular
  preset (matching `.releaserc.yml`). Requires `npm install` after `setup.sh` to
  pull in `@commitlint/cli` and `@commitlint/config-angular`.
- **`scripts/hooks/git-absorb-gate.sh`** (called from the final step of `.git/hooks/pre-commit`):
  runs `git-absorb --dry-run` on staged changes and blocks the commit if the change
  looks like a fixup of a previous branch commit, enforcing atomic commit discipline.
  Requires `git-absorb` binary: `pixi global install git-absorb` (or `cargo install
  git-absorb` / `apt install git-absorb`).
- **`scripts/hooks/atomicity-check.sh`** (called from `.git/hooks/post-commit`):
  classifies `HEAD`'s changed paths into logical areas and flags the commit as
  non-atomic when it spans ≥ 3 independent areas (plugin:X, workers, gateway, …;
  support areas like docs/scripts/ci/infra/root-config don't contribute). Flagged
  SHAs are appended to `.git/NON_ATOMIC_COMMIT`. The hook never aborts the commit
  (post-commit cannot) — the sentinel is the signal consumed by pre-push.
  Complements the absorb gate: absorb catches *fixups*, this catches *wide*
  commits that bundle unrelated changes.
- **`scripts/hooks/pre-push-atomicity-gate.sh`** (called from `.git/hooks/pre-push`):
  reads git's pre-push stdin, intersects pushed commits with
  `.git/NON_ATOMIC_COMMIT`, and **blocks the push** if any pushed commit is
  flagged. Acknowledging with `ATOMICITY_ACK=1` clears the SHAs from the sentinel.
- **`scripts/hooks/pr-checklist-merge-gate.sh`** (called from `.git/hooks/pre-merge-commit`):
  resolves the merge source branch, looks up its open GitHub PR via `gh`, and
  **blocks the merge commit** when the PR's checklist has unchecked items
  (`scripts/run_pr_checklists.py --fail-on-incomplete`). Auto-skips when `gh`
  is missing/unauthenticated, when no open PR exists, or during rebase /
  cherry-pick / bisect. Mirrored server-side by `.github/workflows/pr-checklist.yml`.
  Bypass with `SKIP_PR_CHECKLIST=1` or `PR_CHECKLIST_ACK=1`.

**Bypass env vars (per-commit / per-push, not persisted):**

| Variable                  | Gate         | Meaning                                                                |
| ------------------------- | ------------ | ---------------------------------------------------------------------- |
| `ABSORB_ACK=1`            | pre-commit   | This IS a new atomic commit — I verified manually. Absorb gate passes. |
| `SKIP_ABSORB_CHECK=1`     | pre-commit   | Disable the absorb gate entirely. Discouraged.                         |
| `SKIP_ATOMICITY_CHECK=1`  | post-commit  | Skip classifying HEAD's areas for this commit.                         |
| `ATOMICITY_THRESHOLD=<N>` | post-commit  | Override the default independence threshold (3).                       |
| `ATOMICITY_ACK=1`         | pre-push     | Push flagged commits anyway; clears their sentinel entries.            |
| `SKIP_ATOMICITY_GATE=1`   | pre-push     | Disable the pre-push gate entirely. Discouraged.                       |
| `SKIP_PR_CHECKLIST=1`     | pre-merge-commit | Disable the PR-checklist gate entirely for this merge. Discouraged. |
| `PR_CHECKLIST_ACK=1`      | pre-merge-commit | Acknowledge incomplete PR checklist and proceed with merge.         |

**Prerequisites after `setup.sh`:**

```bash
# 1. Install git-absorb (choose one)
pixi global install git-absorb
# cargo install git-absorb
# apt install git-absorb

# 2. Install Node deps for commitlint
npm install

# 3. Enforce rebase-only merges on the GitHub remote (preserves atomic history).
#    Requires gh CLI + admin access on the target repo. Opt-in, one-time:
bash scripts/configure-merge-strategy.sh
```

### Why rebase-only merges matter

The four atomicity gates (commit-msg + pre-commit + post-commit + pre-push) only
preserve atomic history if the PR merge strategy keeps individual commits.

- **Rebase and merge** — commits preserved 1:1. **Required** by the atomicity gates.
- **Squash and merge** — collapses every commit into one. **Forbidden**; defeats every gate.
- **Create merge commit** — preserves commits but adds one noisy merge commit. Tolerable, not preferred.

`shared/scripts/configure-merge-strategy.sh` disables squash and merge-commit
modes on the remote repo via `gh repo edit`, leaving only "Rebase and Merge"
available in the GitHub UI. This is **level 1** enforcement.

**Level 4** (user-facing nudge) is the
`shared/.github/PULL_REQUEST_TEMPLATE.md.template` header block, which is
copied to `.github/PULL_REQUEST_TEMPLATE.md` by `setup.sh` and tells PR
authors/reviewers to use "Rebase and Merge".

**Level 2** (branch protection — linear history, required status checks,
enforce-admins) is automated via the same script's `--protect-branch` flag:

```bash
# Enforce merge strategy + branch protection on the default branch in one shot:
bash scripts/configure-merge-strategy.sh --protect-branch
# Customise:
bash scripts/configure-merge-strategy.sh <owner>/<repo> --protect-branch master --min-reviews 1
# Preview without calling the API:
bash scripts/configure-merge-strategy.sh <owner>/<repo> --protect-branch master --dry-run
```

This `PUT`s `required_linear_history=true`, `enforce_admins=true`, strict
required status checks (empty contexts list to start), and `restrictions=null`.
`--min-reviews` defaults to 0 so solo-dev repos aren't locked out of
merging their own PRs; set ≥ 1 on team repos.

### Step 6 — Commit

```bash
git add -p  # review changes
git commit -m "chore: align project config with standard template"
```

## Workflow: Align Existing Project

When asked to "apply settings from X to Y" or "align project config":

1. Read the source project's configs to understand the reference pattern
2. Read the target project's existing configs
3. MERGE — do not overwrite; preserve project-specific customizations
4. Use the templates as the baseline standard for any value not already set
5. Run lint, tests, and build after changes to confirm nothing broke
6. Commit with: `chore: align project config with <source> standards`

## Configuration Standards

| Setting | Python | Rust | TypeScript |
|---|---|---|---|
| Line length | 100 | 100 | 100 (prettier) |
| Formatter | ruff format | rustfmt | prettier |
| Linter | ruff + mypy + bandit | clippy + cargo deny | eslint |
| Test framework | pytest | cargo test | vitest |
| Coverage gate | 97%+ | — | 80%+ |
| Docstring gate | 99.9% (interrogate) | `#[deny(missing_docs)]` | tsdoc |
| Secret scanning | gitleaks | gitleaks | gitleaks |
| Release | semantic-release (angular) | semantic-release (angular) | semantic-release (angular) |
| Commit format | `<type>(<scope>): <desc>` commitlint (angular) | same | same |
| Pre-commit hook | ruff, mypy, coverage, docstrings, UML, gitleaks, absorb gate | clippy, rustfmt, cargo test, cargo deny, gitleaks, absorb gate | eslint, prettier, vitest, tsc, gitleaks, absorb gate |
| Post-commit hook | atomicity-check (classifies HEAD's areas, appends `.git/NON_ATOMIC_COMMIT` if ≥3 independent areas) | same | same |
| Pre-push hook | pre-push-atomicity-gate (blocks push when sentinel intersects push range) | same | same |
| Pre-merge-commit hook | pr-checklist-merge-gate (blocks local merge when source branch's PR has incomplete checklist) | same | same |
| PR checklist gate | pre-merge-commit hook + `.github/workflows/pr-checklist.yml` | same | same |

## Anti-Patterns — Never Do These

- **Overwriting existing configs** — always read first, then merge
- **Skipping verification** — always run the hook after setup to catch issues
- **Hardcoding paths in hooks** — use the configurable variables at the top of each hook script
- **Ignoring `# ADAPT:` comments** — these mark mandatory customization points; leaving them as-is breaks the setup
- **Applying Python configs to Rust/TS projects** — use the correct language subdirectory
- **Committing without running the hook** — the hook exists to catch problems before they reach CI

## Decision Tree

```
User asks to set up / align a project
│
├── Is the template system available (scripts/project-template/ exists)?
│   ├── YES → Use setup.sh or manual copy from templates
│   └── NO  → Read an aligned reference project via gh API and replicate its configs
│
├── Does the project already have config files?
│   ├── YES → MERGE mode: read existing, add missing sections, update values
│   └── NO  → COPY mode: copy templates, resolve all # ADAPT: comments
│
└── What language?
    ├── Python     → python/ + shared/
    ├── Rust       → rust/ + shared/
    └── TypeScript → typescript/ + shared/
```

## Quick Reference — File Destinations

All paths are relative to the target project root.

| Template file | Destination |
|---|---|
| `shared/.releaserc.yml.template` | `.releaserc.yml` |
| `shared/package.json.template` | `package.json` |
| `shared/.gitleaksignore.template` | `.gitleaksignore` |
| `shared/.gitignore-additions.template` | append to `.gitignore` |
| `shared/.editorconfig.template` | `.editorconfig` |
| `python/pyproject.toml.template` | `pyproject.toml` (merge) |
| `python/.coveragerc.template` | `.coveragerc` |
| `python/pre-commit-hook.sh` | `.git/hooks/pre-commit` |
| `rust/clippy.toml.template` | `.cargo/config.toml` (merge) |
| `rust/rustfmt.toml.template` | `rustfmt.toml` |
| `rust/pre-commit-hook.sh` | `.git/hooks/pre-commit` |
| `typescript/tsconfig.json.template` | `tsconfig.json` (merge) |
| `typescript/eslint.config.mjs.template` | `eslint.config.mjs` (merge) |
| `typescript/pre-commit-hook.sh` | `.git/hooks/pre-commit` |

> `.git/hooks/pre-commit` must be executable (`chmod +x`). setup.sh handles this automatically.

## Testing Directive — Mandatory Test Categories

Every project set up with this template **MUST** implement four test categories. The pre-commit hook (gate 5) enforces their existence at commit time.

| Category | Marker | Directory | Coverage Gate | Purpose |
|---|---|---|---|---|
| **Integration** | `@pytest.mark.integration` | `tests/integration/` or `tests/test_integration.py` | 99%+ | Module boundaries, service interactions, DB queries |
| **E2E** | `@pytest.mark.e2e` | `tests/e2e/` | 99%+ | Full user workflows through the public API |
| **Smoke** | `@pytest.mark.smoke` | `tests/smoke/` | 99%+ | Quick deployment health checks (< 30s) |
| **Edge Case** | `@pytest.mark.edge_case` | `tests/edge_cases/` | No gate | Boundary values, injection, Unicode, overflow, empty inputs |

### Coverage rules

- Integration, E2E, and Smoke tests share the **same 99%+ coverage gate** as unit tests
- Edge case tests are **exempt** from the coverage gate — their value is catching regressions at boundaries, not covering new lines

### When setting up a new project

After copying templates (Step 2), create the test directories:

```bash
mkdir -p tests/{integration,e2e,smoke,edge_cases}
touch tests/{integration,e2e,smoke,edge_cases}/__init__.py
```

Add the `edge_case` marker to `pyproject.toml` `[tool.pytest.ini_options].markers`:

```toml
markers = [
    # ... existing markers ...
    "edge_case: marks edge case / boundary value tests",
]
```

Exclude non-default categories from default test runs in `addopts`:

```toml
addopts = [
    "-m", "not integration and not e2e and not smoke and not benchmark and not edge_case",
    # ... other flags ...
]
```

See `shared/TESTING_DIRECTIVE.md` for the full policy including what each category must test.
