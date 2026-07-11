from PIL import Image
import fitz
from pathlib import Path
from uuid import uuid4

from src.core.pdf_engine import DocumentModel


def test_normalize_uses_source_orientation():
    portrait = DocumentModel._normalize_to_a4_canvas(Image.new("RGB", (600, 900), "white"))
    landscape = DocumentModel._normalize_to_a4_canvas(Image.new("RGB", (900, 600), "white"))

    assert portrait.size == (2480, 3508)
    assert landscape.size == (3508, 2480)


def test_set_page_landscape_switches_current_and_original_page():
    model = DocumentModel()
    page = DocumentModel._normalize_to_a4_canvas(Image.new("RGB", (600, 900), "white"))
    model._pages = [page]
    model._original_pages = [page.copy()]

    assert model.set_page_landscape(0, True) is True
    assert model.get_page(0).size == (3508, 2480)
    assert model.get_original_page(0).size == (3508, 2480)
    assert model.set_page_landscape(0, True) is False


def test_export_keeps_landscape_page_direction():
    output = Path(".pytest_cache") / f"landscape-{uuid4().hex}.pdf"
    output.parent.mkdir(exist_ok=True)
    try:
        DocumentModel.export_pdf_from_images(
            [Image.new("RGB", (3508, 2480), "white")],
            str(output),
        )
        with fitz.open(output) as document:
            assert document[0].rect.width > document[0].rect.height
    finally:
        output.unlink(missing_ok=True)
