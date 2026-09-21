from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
README = ROOT / "README.md"
CLIENT = ROOT / "Sources" / "OpenAPIDynamic" / "Client.swift"


def _integration_section(readme: str) -> str:
    marker = "## Integration with Static Clients"
    assert marker in readme
    rest = readme.split(marker, 1)[1]
    return rest.split("\n## ", 1)[0]


def _class_doc_comment(source: str) -> str:
    marker = "public final class OpenAPIDynamic: Sendable"
    assert marker in source
    before, _, _ = source.partition(marker)
    comment = before.rsplit("import OpenAPIURLSession", 1)[1]
    return comment


def test_readme_documents_sendable_isolation() -> None:
    section = _integration_section(README.read_text(encoding="utf-8"))
    assert "Sendable" in section
    lowered = section.lower()
    assert "actor" in lowered
    assert "isolation" in lowered


def test_type_comment_documents_sendable_isolation() -> None:
    comment = _class_doc_comment(CLIENT.read_text(encoding="utf-8"))
    assert "Sendable" in comment
    lowered = comment.lower()
    assert "actor" in lowered
    assert "isolation" in lowered
