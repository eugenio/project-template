# Project Template

Reusable project setup templates based on patterns from `project-PEAK` and `peak-annotator`.
Run `setup.sh` to copy templates into a new project, then adapt the marked sections.

## Quick Start

```bash
bash scripts/project-template/setup.sh \
  --lang python \
  --project-dir /path/to/new-project
```

## File Map

### `setup.sh`
Main setup script. Copies shared + language templates and installs the pre-commit hook.
Arguments: `--lang python|rust|typescript`, `--project-dir <path>`.

### `python/`

| File | Purpose |
|---|---|
| `pyproject.toml.template` | Ruff, mypy, bandit, pytest, coverage, bumpversion config |
| `.coveragerc.template` | Standalone coverage config (alternative to pyproject.toml) |
| `pre-commit-hook.sh` | Full pre-commit gate: lint, types, coverage, docstrings, UML, secrets |

### `shared/`

| File | Purpose |
|---|---|
| `.releaserc.yml.template` | semantic-release config (conventional commits → CHANGELOG) |
| `package.json.template` | Node wrapper for semantic-release tooling only |
| `.gitleaksignore.template` | Empty allowlist for gitleaks false-positive suppressions |
| `.gitignore-additions.template` | Common entries to append to your `.gitignore` |
| `.editorconfig.template` | Editor whitespace/indent config across languages |

### `rust/`

| File | Purpose |
|---|---|
| `clippy.toml.template` | Clippy lint config |
| `rustfmt.toml.template` | Rustfmt style config (edition 2021) |
| `pre-commit-hook.sh` | Rust pre-commit: clippy, fmt --check, test, deny |

### `typescript/`

| File | Purpose |
|---|---|
| `tsconfig.json.template` | Strict TypeScript compiler config |
| `eslint.config.mjs.template` | Flat ESLint config stub |
| `pre-commit-hook.sh` | TS pre-commit: eslint, prettier --check, vitest |

## Features

- **Commit-atomicity gates**: four complementary hooks enforce atomic commits end-to-end.
  - `commit-msg` — commitlint (angular preset) validates the message format.
  - `pre-commit` — `git-absorb --dry-run` blocks commits that look like fixups of an existing branch commit.
  - `post-commit` — `atomicity-check.sh` classifies `HEAD`'s changed paths into logical areas (plugin:X, workers, gateway, docs, …) and appends the SHA to `.git/NON_ATOMIC_COMMIT` when the commit spans ≥ 3 independent areas (threshold configurable).
  - `pre-push` — `pre-push-atomicity-gate.sh` intersects pushed commits with that sentinel and blocks the push until non-atomic commits are split or acknowledged (`ATOMICITY_ACK=1`).

## LLM / AI Agent Usage

If you're using an AI coding assistant (Claude Code, Copilot, Cursor, etc.), see [LLM_INSTRUCTIONS.md](LLM_INSTRUCTIONS.md) for step-by-step instructions the agent can follow to apply this template.

## Adapt Comments

All files mark required per-project customizations with `# ADAPT:` comments (or `// ADAPT:` for JSON).
Search for `ADAPT` after copying to find every place that needs a project-specific value.

```bash
grep -r "ADAPT" /path/to/new-project/
```
