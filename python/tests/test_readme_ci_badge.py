from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
README = ROOT / "README.md"
DELETED_WORKFLOW = ROOT / ".github" / "workflows" / "daily_test.yml"
BROKEN_BADGE = (
    "https://github.com/mikolaj92/swift-openapi-dynamic"
    "/actions/workflows/daily_test.yml/badge.svg"
)


def test_readme_does_not_point_at_deleted_daily_test_workflow() -> None:
    readme = README.read_text(encoding="utf-8")
    assert BROKEN_BADGE not in readme
    assert "daily_test.yml" not in readme


def test_deleted_daily_test_workflow_is_absent() -> None:
    assert not DELETED_WORKFLOW.exists()
