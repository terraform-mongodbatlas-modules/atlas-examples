from pathlib import Path

import yaml

URLS_YAML = Path(__file__).resolve().parent / "urls.yaml"


def test_pins_nist_pdfs_and_owasp_markdown():
    pins = yaml.safe_load(URLS_YAML.read_text())
    assert [item["filename"] for item in pins["nist"]["files"]] == [
        "NIST.AI.100-1.pdf",
        "NIST.AI.600-1.pdf",
    ]
    assert pins["owasp"]["commit"] == "7bbe0f06f468cdcc61fa73e1752183c6cfd23987"
    names = pins["owasp"]["files"]
    assert names[0] == "LLM00_Preface.md"
    assert "LLM01_PromptInjection.md" in names
    assert "LLM10_ImproperOutputHandling.md" in names
    assert not any(name.startswith("Appendix_") for name in names)
