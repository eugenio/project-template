#!/usr/bin/env python3
"""CLI runner that validates GitHub PR checklists using the ``gh`` CLI.

Shells out to the authenticated ``gh`` CLI (never ``curl``, never
``shell=True``) to fetch PR metadata and delegates parsing, classification,
and report formatting to :mod:`validate_pr_checklists`.

Usage:
    * ``run_pr_checklists.py --pr N`` -- validate a single PR.
    * ``run_pr_checklists.py --all`` -- validate every PR.
    * ``run_pr_checklists.py --pr N --fail-on-incomplete`` -- CI gate mode.

Produces a markdown report (and optionally a JSON sidecar) plus a one-line
summary on stdout.  In gate mode the exit code is ``1`` iff at least one PR
is ``incomplete``; PRs with no checklist at all never fail the gate.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import cast

sys.path.insert(0, str(Path(__file__).parent))
from validate_pr_checklists import (  # noqa: E402  (sys.path set above)
    classify,
    format_report,
    parse_checklist,
)

DEFAULT_REPORT_PATH = "qa-artifacts/pr-checklist-report.md"
PR_FIELDS = "number,title,state,url,body"


def _run_gh(args: list[str]) -> str:
    """Run ``gh`` with *args* and return captured stdout (raises on non-zero)."""
    completed = subprocess.run(
        ["gh", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def fetch_single_pr(number: int) -> dict:
    """Return PR metadata (``number,title,state,url,body``) for PR *number*."""
    stdout = _run_gh(["pr", "view", str(number), "--json", PR_FIELDS])
    return cast(dict, json.loads(stdout))


def fetch_all_prs(state: str) -> list[dict]:
    """Return PR metadata for every PR matching *state* (single ``gh`` call)."""
    stdout = _run_gh(
        [
            "pr",
            "list",
            "--state",
            state,
            "--limit",
            "500",
            "--json",
            PR_FIELDS,
        ]
    )
    return cast(list[dict], json.loads(stdout))


def build_result(pr: dict) -> dict:
    """Classify *pr* and return a result dict consumed by ``format_report``."""
    body = pr.get("body") or ""
    items = parse_checklist(body)
    status = classify(items)
    return {
        "number": pr.get("number"),
        "title": pr.get("title", ""),
        "state": pr.get("state", ""),
        "url": pr.get("url", ""),
        "status": status,
        "total": len(items),
        "checked": sum(1 for item in items if item.checked),
        "unchecked_texts": [item.text for item in items if not item.checked],
    }


def build_parser() -> argparse.ArgumentParser:
    """Return the configured argparse parser for the CLI."""
    parser = argparse.ArgumentParser(
        description="Validate GitHub PR checklists via the gh CLI.",
    )
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--pr", type=int, help="Validate a single PR by number.")
    target.add_argument(
        "--all",
        action="store_true",
        help="Validate all PRs (combine with --state to filter).",
    )
    parser.add_argument(
        "--state",
        choices=("open", "closed", "merged", "all"),
        default="all",
        help="PR state filter when --all is used (default: all).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(DEFAULT_REPORT_PATH),
        help=f"Markdown report output path (default: {DEFAULT_REPORT_PATH}).",
    )
    parser.add_argument(
        "--json",
        dest="json_path",
        type=Path,
        default=None,
        help="Optional JSON sidecar with raw results.",
    )
    parser.add_argument(
        "--fail-on-incomplete",
        action="store_true",
        help="Exit 1 if any PR is incomplete (empty PRs never fail).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the CLI; return the process exit code (``0`` ok, ``1`` on gate fail)."""
    args = build_parser().parse_args(argv)

    prs = [fetch_single_pr(args.pr)] if args.pr is not None else fetch_all_prs(args.state)
    results = [build_result(pr) for pr in prs]

    report = format_report(results)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(report, encoding="utf-8")

    if args.json_path is not None:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(
            json.dumps(results, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    counts = {"complete": 0, "incomplete": 0, "empty": 0}
    for result in results:
        counts[result["status"]] = counts.get(result["status"], 0) + 1

    print(
        f"Validated {len(results)} PRs -> "
        f"{counts['complete']} complete, "
        f"{counts['incomplete']} incomplete, "
        f"{counts['empty']} empty. "
        f"Report: {args.output}"
    )

    if args.fail_on_incomplete and counts["incomplete"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
