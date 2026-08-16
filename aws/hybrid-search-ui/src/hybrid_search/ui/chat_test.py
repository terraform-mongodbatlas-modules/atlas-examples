from pathlib import Path

from hybrid_search.ui.chat import is_allowed_upload


def test_upload_extension_filter():
    assert is_allowed_upload(Path("doc.pdf"))
    assert is_allowed_upload(Path("notes.TXT"))
    assert not is_allowed_upload(Path("image.png"))
