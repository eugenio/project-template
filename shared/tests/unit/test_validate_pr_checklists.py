"""Tests for scripts/validate_pr_checklists.py — the template's reference test suite."""

import sys
from pathlib import Path

import pytest

# Scope sys.path insertion to this test file only (not via conftest).
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import validate_pr_checklists as vpc  # noqa: E402, I001


# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------


def make_item(text: str, checked: bool, line: int) -> vpc.ChecklistItem:
    """Build a ChecklistItem for use in tests."""
    return vpc.ChecklistItem(text=text, checked=checked, line=line)


def make_result(
    number: int = 1,
    title: str = "Test PR",
    state: str = "open",
    url: str = "https://github.com/org/repo/pull/1",
    status: str = "complete",
    total: int = 2,
    checked: int = 2,
    unchecked_texts: list[str] | None = None,
) -> dict:
    """Build a PR result dict for format_report tests."""
    return {
        "number": number,
        "title": title,
        "state": state,
        "url": url,
        "status": status,
        "total": total,
        "checked": checked,
        "unchecked_texts": unchecked_texts or [],
    }


# ---------------------------------------------------------------------------
# parse_checklist — basic cases
# ---------------------------------------------------------------------------


def test_parse_checklist_empty_string_returns_empty_list() -> None:
    """Empty string produces no checklist items."""
    assert vpc.parse_checklist("") == []


def test_parse_checklist_no_task_list_syntax_returns_empty_list() -> None:
    """Body with no task-list markers produces no items."""
    body = "This is a normal PR description.\n\nSome *markdown* content."
    assert vpc.parse_checklist(body) == []


def test_parse_checklist_unchecked_item_text_and_line() -> None:
    """'- [ ] foo' on line 1 yields one unchecked item with text 'foo' and line=1."""
    items = vpc.parse_checklist("- [ ] foo")
    assert len(items) == 1
    assert items[0].text == "foo"
    assert items[0].checked is False
    assert items[0].line == 1


def test_parse_checklist_checked_item_lowercase_x() -> None:
    """'- [x] bar' is parsed as checked."""
    items = vpc.parse_checklist("- [x] bar")
    assert len(items) == 1
    assert items[0].checked is True
    assert items[0].text == "bar"


@pytest.mark.parametrize("marker", ["x", "X"])
def test_parse_checklist_checked_case_insensitive(marker: str) -> None:
    """Both lowercase and uppercase 'x' inside brackets are treated as checked."""
    body = f"- [{marker}] baz"
    items = vpc.parse_checklist(body)
    assert len(items) == 1
    assert items[0].checked is True


def test_parse_checklist_indented_item_is_counted() -> None:
    """Items indented with spaces (e.g. '  - [ ] nested') are counted."""
    body = "  - [ ] nested"
    items = vpc.parse_checklist(body)
    assert len(items) == 1
    assert items[0].text == "nested"
    assert items[0].checked is False


def test_parse_checklist_line_numbers_are_one_indexed_after_blank_lines() -> None:
    """Line numbers are 1-indexed and account for blank lines between items."""
    body = "- [ ] first\n\n- [x] third"
    items = vpc.parse_checklist(body)
    assert len(items) == 2
    assert items[0].line == 1
    assert items[1].line == 3


# ---------------------------------------------------------------------------
# parse_checklist — items inside code fences are ignored
# ---------------------------------------------------------------------------


def test_parse_checklist_ignores_items_inside_backtick_fence() -> None:
    """Task-list items inside a triple-backtick code block are ignored."""
    body = "```\n- [ ] inside fence\n```"
    assert vpc.parse_checklist(body) == []


def test_parse_checklist_ignores_items_inside_tilde_fence() -> None:
    """Task-list items inside a triple-tilde code block are ignored."""
    body = "~~~\n- [ ] inside tilde fence\n~~~"
    assert vpc.parse_checklist(body) == []


def test_parse_checklist_counts_items_outside_fence_but_not_inside() -> None:
    """Only items outside fenced blocks are counted; items inside are skipped."""
    body = "- [ ] before\n```\n- [ ] inside\n```\n- [x] after"
    items = vpc.parse_checklist(body)
    assert len(items) == 2
    texts = {i.text for i in items}
    assert "before" in texts
    assert "after" in texts
    assert "inside" not in texts


def test_parse_checklist_unclosed_fence_treats_rest_as_code() -> None:
    """A fence opened without a closing line causes everything after to be treated as code."""
    body = "- [ ] visible\n```\n- [ ] hidden because unclosed"
    items = vpc.parse_checklist(body)
    assert len(items) == 1
    assert items[0].text == "visible"


# ---------------------------------------------------------------------------
# parse_checklist — items inside HTML comments are ignored
# ---------------------------------------------------------------------------


def test_parse_checklist_ignores_items_inside_single_line_html_comment() -> None:
    """Task-list item embedded in a single-line HTML comment is ignored."""
    body = "<!-- - [ ] hidden -->"
    assert vpc.parse_checklist(body) == []


def test_parse_checklist_ignores_items_inside_multiline_html_comment() -> None:
    """Task-list items inside a multi-line HTML comment are ignored."""
    body = "<!--\n- [ ] hidden line 1\n- [ ] hidden line 2\n-->"
    assert vpc.parse_checklist(body) == []


def test_parse_checklist_counts_items_outside_html_comment() -> None:
    """Items outside an HTML comment block are counted normally."""
    body = "- [ ] real\n<!--\n- [ ] hidden\n-->\n- [x] also real"
    items = vpc.parse_checklist(body)
    assert len(items) == 2
    texts = {i.text for i in items}
    assert "real" in texts
    assert "also real" in texts
    assert "hidden" not in texts


# ---------------------------------------------------------------------------
# parse_checklist — inline task markers that are NOT at the start of a line
# ---------------------------------------------------------------------------


def test_parse_checklist_ignores_task_marker_not_at_line_start() -> None:
    """A '- [ ]' appearing mid-line (not at optional leading whitespace) is ignored."""
    body = "some text - [ ] not-a-task"
    assert vpc.parse_checklist(body) == []


# ---------------------------------------------------------------------------
# classify
# ---------------------------------------------------------------------------


def test_classify_empty_list_returns_empty() -> None:
    """An empty list of items is classified as 'empty'."""
    assert vpc.classify([]) == "empty"


def test_classify_all_checked_returns_complete() -> None:
    """All checked items are classified as 'complete'."""
    items = [make_item("a", True, 1), make_item("b", True, 2)]
    assert vpc.classify(items) == "complete"


def test_classify_any_unchecked_returns_incomplete() -> None:
    """A mix of checked and unchecked items is classified as 'incomplete'."""
    items = [make_item("a", True, 1), make_item("b", False, 2)]
    assert vpc.classify(items) == "incomplete"


def test_classify_all_unchecked_returns_incomplete() -> None:
    """All unchecked items are classified as 'incomplete' (not 'empty')."""
    items = [make_item("a", False, 1), make_item("b", False, 2)]
    assert vpc.classify(items) == "incomplete"


# ---------------------------------------------------------------------------
# format_report
# ---------------------------------------------------------------------------


def test_format_report_returns_string() -> None:
    """format_report always returns a str, never None."""
    result = vpc.format_report([make_result()])
    assert isinstance(result, str)


def test_format_report_contains_header() -> None:
    """The returned markdown starts with the required H1 header."""
    report = vpc.format_report([make_result()])
    assert "# PR Checklist Validation Report" in report


def test_format_report_summary_table_shows_complete_count() -> None:
    """The summary table reflects the count of complete PRs."""
    results = [make_result(status="complete", total=2, checked=2)]
    report = vpc.format_report(results)
    # The table must mention the 'complete' bucket with at least count 1
    assert "complete" in report.lower()


def test_format_report_summary_table_shows_incomplete_count() -> None:
    """The summary table reflects the count of incomplete PRs."""
    results = [
        make_result(
            number=2,
            status="incomplete",
            total=2,
            checked=1,
            unchecked_texts=["Deploy docs"],
        )
    ]
    report = vpc.format_report(results)
    assert "incomplete" in report.lower()


def test_format_report_summary_table_shows_empty_count() -> None:
    """The summary table reflects the count of empty PRs."""
    results = [make_result(number=3, status="empty", total=0, checked=0)]
    report = vpc.format_report(results)
    assert "empty" in report.lower()


def test_format_report_complete_prs_not_in_per_pr_section() -> None:
    """Complete PRs do not appear in the per-PR detail section."""
    complete_pr = make_result(number=10, title="Fully done PR", status="complete")
    report = vpc.format_report([complete_pr])
    # The title should NOT appear as a detail section entry
    # (it may appear in the summary table, so we check for heading patterns)
    lines = report.splitlines()
    heading_lines = [ln for ln in lines if ln.startswith("##") and "Fully done PR" in ln]
    assert heading_lines == []


def test_format_report_incomplete_prs_listed_with_unchecked_bullets() -> None:
    """Incomplete PRs appear in the per-PR section with their unchecked items as bullets."""
    incomplete_pr = make_result(
        number=7,
        title="Partial PR",
        status="incomplete",
        total=3,
        checked=1,
        unchecked_texts=["Write tests", "Update changelog"],
    )
    report = vpc.format_report([incomplete_pr])
    assert "Write tests" in report
    assert "Update changelog" in report


def test_format_report_all_complete_omits_or_labels_per_pr_section() -> None:
    """When all PRs are complete the per-PR section is absent or says 'All PRs complete'."""
    results = [
        make_result(number=1, status="complete"),
        make_result(number=2, status="complete"),
    ]
    report = vpc.format_report(results)
    # Either no per-PR heading at all, or the report says all are complete
    has_incomplete_section = any(
        "incomplete" in line.lower() and line.startswith("##") for line in report.splitlines()
    )
    signals_all_complete = "all prs complete" in report.lower()
    assert not has_incomplete_section or signals_all_complete


def test_format_report_multiple_buckets_in_summary() -> None:
    """Summary table covers all three status buckets when each has at least one PR."""
    results = [
        make_result(number=1, status="complete"),
        make_result(number=2, status="incomplete", unchecked_texts=["todo"]),
        make_result(number=3, status="empty"),
    ]
    report = vpc.format_report(results)
    lower = report.lower()
    assert "complete" in lower
    assert "incomplete" in lower
    assert "empty" in lower
