# Testing Directive

Every project MUST implement **all four** mandatory test categories. The pre-commit hook enforces their existence and the CI pipeline enforces their coverage gates.

## Mandatory Test Categories

| Category | Marker | Directory | Coverage Gate | Runs By Default | Purpose |
|---|---|---|---|---|---|
| **Integration** | `@pytest.mark.integration` | `tests/integration/` or `tests/test_integration.py` | 99%+ | No (`INTEGRATION_TESTS=1`) | Verify module boundaries, service interactions, database queries |
| **E2E** | `@pytest.mark.e2e` | `tests/e2e/` | 99%+ | No (`E2E_TESTS=1`) | Full user workflows through the public API as a black box |
| **Smoke** | `@pytest.mark.smoke` | `tests/smoke/` | 99%+ | No (`SMOKE_TESTS=1`) | Quick deployment health checks (< 30s total) |
| **Edge Case** | `@pytest.mark.edge_case` | `tests/edge_cases/` | No gate | No (explicit `-m edge_case`) | Boundary values, type coercion, injection, Unicode, overflow, empty inputs |

## Coverage Gates

All test categories **except edge cases** share the same coverage gate as unit tests: **99%+** line+branch coverage measured across the source directories.

Edge case tests are exempt from the coverage gate because they exercise boundary conditions that may not map to linear code paths. Their value is in catching regressions at system boundaries, not in covering new lines.

### How coverage is enforced

```bash
# Unit tests (default) — 99%+ gate
pixi run -e dev pytest tests/ --cov-fail-under=99

# Integration tests — 99%+ gate
INTEGRATION_TESTS=1 pixi run -e dev pytest tests/ -m integration --cov-fail-under=99

# E2E tests — 99%+ gate (against running services)
E2E_TESTS=1 pixi run -e dev pytest tests/e2e/ --cov-fail-under=99

# Smoke tests — 99%+ gate (against running services)
SMOKE_TESTS=1 pixi run -e dev pytest tests/smoke/ --cov-fail-under=99

# Edge case tests — no coverage gate
pixi run -e dev pytest tests/edge_cases/ -m edge_case --no-cov
```

## Pre-Commit Hook Enforcement

The pre-commit hook (gate 5) verifies that all four test category directories exist and contain at least one `test_*.py` file. If any category is missing, the commit is blocked.

## What Each Category Must Test

### Integration Tests

Test the boundaries between components:

- Gateway → Redis queue → Worker round-trip
- Dashboard → Gateway API calls
- Database read/write cycles (MongoDB, Redis)
- External API integrations (mocked at the HTTP boundary)
- Authentication / authorization flows across services

### E2E Tests

Test complete user workflows end-to-end:

- Submit job → poll status → retrieve results
- Create project → assign jobs → list by project
- Pipeline definition → run pipeline → verify stage outputs
- Multi-step workflows that span multiple services

### Smoke Tests

Quick sanity checks after deployment:

- All service health endpoints return 200
- Key API endpoints accept valid input and return expected shape
- Database connectivity verified
- Queue connectivity verified
- Critical UI pages render without error

### Edge Case Tests

Boundary value and adversarial input testing:

- Empty, null, whitespace inputs
- Type boundary values (0, -1, MAX_INT, NaN, Infinity)
- Unicode, special characters, emoji in string fields
- Extremely long inputs (10MB sequences, 10000-char names)
- SQL/NoSQL injection patterns in user inputs
- Concurrent request edge cases
- Clock skew, timezone boundary values
- Floating point precision boundaries

## Adding Tests to a New Module

When adding a new module to the project:

1. Add unit tests in `tests/unit/test_<module>.py` (as always)
2. Add integration tests exercising the module's boundaries
3. Add at least one E2E workflow that includes the new module
4. Add smoke checks for the module's health/status endpoints
5. Add edge case tests for the module's input validation and parsing

## Enforcement Timeline

- **Pre-commit hook**: Blocks commits if any category directory is missing
- **CI pipeline**: Runs all categories with coverage gates on every PR
- **Sprint close**: All four categories must pass as part of Definition of Done
