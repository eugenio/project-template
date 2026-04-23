"""Validate GitHub PR checklist completion from parsed PR body markdown.

Public API
----------
ChecklistItem : dataclass
    A single task-list item extracted from a PR body.
parse_checklist(body) -> list[ChecklistItem]
    Parse task-list items from a GitHub PR markdown body.
classify(items) -> str
    Classify a list of items as "empty", "complete", or "incomplete".
format_report(results) -> str
    Render a markdown validation report for a list of PR result dicts.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class ChecklistItem:
    """A single GitHub task-list item extracted from a PR body.

    Attributes:
        text: The item label text (everything after the bracket marker).
        checked: True when the marker is ``[x]`` or ``[X]``, False for ``[ ]``.
        line: 1-indexed line number in the original body string.
    """

    text: str
    checked: bool
    line: int


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

# Matches the task-list syntax at the start of a line (after optional spaces).
_TASK_RE = re.compile(r"^\s*- \[( |x|X)\] (.+)$")

# Detects the opening of a fenced code block: 3+ identical fence chars.
_FENCE_OPEN_RE = re.compile(r"^(`{3,}|~{3,})")


def _fence_char(line: str) -> tuple[str, int] | None:
    """Return the fence character and its run length if *line* opens a fence.

    Args:
        line: A single line of text (no trailing newline required).

    Returns:
        A ``(char, length)`` tuple when *line* starts a fence, or ``None``.
    """
    m = _FENCE_OPEN_RE.match(line)
    if m:
        token = m.group(1)
        return token[0], len(token)
    return None


def _strip_html_comments(line: str, in_comment: bool) -> tuple[str, bool]:
    """Remove HTML comment spans from *line*, tracking multiline comment state.

    The function handles ``<!-- ... -->`` comments that may span multiple lines.
    Text outside comment regions is preserved.  If a line contains both an
    opening ``<!--`` and a closing ``-->`` on the same line, only the text
    between them is consumed.

    Args:
        line: The raw line to process.
        in_comment: Whether we are already inside an open HTML comment.

    Returns:
        A ``(cleaned_line, still_in_comment)`` tuple where *cleaned_line* has
        all comment spans replaced with spaces (preserving character positions
        so that the regex match still works on the original line structure)
        and *still_in_comment* reflects the comment state after this line.
    """
    result: list[str] = []
    i = 0
    length = len(line)

    while i < length:
        if in_comment:
            end = line.find("-->", i)
            if end == -1:
                # Whole remainder is inside the comment.
                return "".join(result), True
            # Close comment; skip the "-->" itself.
            i = end + 3
            in_comment = False
        else:
            start = line.find("<!--", i)
            if start == -1:
                result.append(line[i:])
                break
            result.append(line[i:start])
            in_comment = True
            i = start + 4  # skip past "<!--"

    return "".join(result), in_comment


# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------


def parse_checklist(body: str) -> list[ChecklistItem]:
    """Parse GitHub task-list items from a PR markdown body.

    Rules applied in order:
    * Lines inside fenced code blocks (triple-backtick or triple-tilde) are
      ignored.  An unclosed fence causes the rest of the body to be treated
      as code.
    * Lines inside HTML comments (``<!-- ... -->``) are ignored.  Comments
      may span multiple lines; a single-line comment on a line causes only
      the commented portion to be blanked.
    * The task-list pattern ``^\\s*- \\[( |x|X)\\] (.+)$`` must match the line
      after comment stripping.  A marker appearing mid-line is not a task.
    * Line numbers are 1-indexed and correspond to the original *body* string.

    Args:
        body: The raw markdown text of a GitHub pull-request body.

    Returns:
        A list of :class:`ChecklistItem` instances in document order.
    """
    items: list[ChecklistItem] = []
    lines = body.splitlines()

    in_fence = False
    fence_char: str = ""
    fence_len: int = 0
    in_comment = False

    for lineno, raw_line in enumerate(lines, start=1):
        # --- Fenced code block tracking ---
        if in_fence:
            info = _fence_char(raw_line)
            # A closing fence must use the same character and be at least as
            # long as the opening fence.
            if info and info[0] == fence_char and info[1] >= fence_len:
                in_fence = False
            continue  # Inside fence: skip task detection entirely.

        info = _fence_char(raw_line)
        if info:
            fence_char, fence_len = info
            in_fence = True
            continue

        # --- HTML comment stripping ---
        cleaned, in_comment = _strip_html_comments(raw_line, in_comment)

        # --- Task-list detection on the cleaned line ---
        m = _TASK_RE.match(cleaned)
        if m:
            marker, text = m.group(1), m.group(2)
            items.append(
                ChecklistItem(
                    text=text,
                    checked=marker.lower() == "x",
                    line=lineno,
                )
            )

    return items


def classify(items: list[ChecklistItem]) -> Literal["empty", "complete", "incomplete"]:
    """Classify a list of checklist items by completion status.

    Args:
        items: The items returned by :func:`parse_checklist`.

    Returns:
        * ``"empty"`` when *items* is empty.
        * ``"complete"`` when every item is checked.
        * ``"incomplete"`` when at least one item is unchecked.
    """
    if not items:
        return "empty"
    if all(item.checked for item in items):
        return "complete"
    return "incomplete"


def format_report(results: list[dict]) -> str:
    """Render a markdown validation report for a collection of PR results.

    Each element of *results* is a dict with these keys:

    * ``number`` (int): PR number.
    * ``title`` (str): PR title.
    * ``state`` (str): GitHub PR state (e.g. ``"open"``).
    * ``url`` (str): Web URL of the PR.
    * ``status`` (str): ``"complete"``, ``"incomplete"``, or ``"empty"``.
    * ``total`` (int): Total checklist items found.
    * ``checked`` (int): Number of checked items.
    * ``unchecked_texts`` (list[str]): Labels of unchecked items.

    The report contains:

    1. An H1 header.
    2. A summary table with ``Status | Count`` rows for each bucket
       (``complete``, ``incomplete``, ``empty``).  Buckets with zero PRs
       are still shown with count ``0``.
    3. A per-PR detail section for incomplete PRs only.  When no PRs are
       incomplete, the section is replaced with ``"All PRs complete."``.

    Args:
        results: List of PR result dicts as described above.

    Returns:
        A multi-line markdown string.
    """
    lines: list[str] = []

    # --- Header ---
    lines.append("# PR Checklist Validation Report")
    lines.append("")

    # --- Summary table ---
    counts: dict[str, int] = {"complete": 0, "incomplete": 0, "empty": 0}
    for pr in results:
        status = pr.get("status", "empty")
        counts[status] = counts.get(status, 0) + 1

    lines.append("## Summary")
    lines.append("")
    lines.append("| Status | Count |")
    lines.append("|--------|-------|")
    for bucket in ("complete", "incomplete", "empty"):
        lines.append(f"| {bucket} | {counts.get(bucket, 0)} |")
    lines.append("")

    # --- Per-PR detail section (incomplete only) ---
    incomplete_prs = [pr for pr in results if pr.get("status") == "incomplete"]

    if not incomplete_prs:
        lines.append("All PRs complete.")
    else:
        lines.append("## Incomplete PRs")
        lines.append("")
        for pr in incomplete_prs:
            number = pr.get("number", "?")
            title = pr.get("title", "")
            state = pr.get("state", "")
            url = pr.get("url", "")
            unchecked = pr.get("unchecked_texts", [])

            lines.append(f"## PR #{number} — {title}")
            lines.append(f"- State: {state}")
            lines.append(f"- URL: {url}")
            lines.append(f"- Unchecked ({len(unchecked)}):")
            for text in unchecked:
                lines.append(f"  - {text}")
            lines.append("")

    return "\n".join(lines)
