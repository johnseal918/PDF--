"""
PDF/image load and export helpers.
"""

from pathlib import Path
from typing import Optional

import fitz  # PyMuPDF
from PIL import Image

SUPPORTED_PDF = {".pdf"}
SUPPORTED_IMAGE = {".png", ".jpg", ".jpeg", ".bmp", ".tiff", ".tif"}
SUPPORTED_ALL = SUPPORTED_PDF | SUPPORTED_IMAGE


class DocumentModel:
    """Unified document model (every source becomes a list of PIL pages)."""

    A4_WIDTH_PX = 2480
    A4_HEIGHT_PX = 3508
    EXPORT_JPEG_QUALITY = 82
    JPEG_PICK_THRESHOLD = 0.85

    def __init__(self):
        self._pages: list[Image.Image] = []
        self._original_pages: list[Image.Image] = []
        self._source_path: Optional[str] = None
        self._is_pdf: bool = False
        self._dpi: int = 300

    @property
    def page_count(self) -> int:
        return len(self._pages)

    @property
    def source_path(self) -> Optional[str]:
        return self._source_path

    @property
    def is_pdf(self) -> bool:
        return self._is_pdf

    def load(self, file_path: str) -> bool:
        path = Path(file_path)
        suffix = path.suffix.lower()
        if suffix not in SUPPORTED_ALL:
            return False

        self._source_path = file_path
        self._pages.clear()
        self._original_pages.clear()

        if suffix in SUPPORTED_PDF:
            self._is_pdf = True
            return self._load_pdf(file_path)
        self._is_pdf = False
        return self._load_image(file_path)

    @staticmethod
    def _normalize_to_a4_canvas(img: Image.Image) -> Image.Image:
        """
        Force every page onto an A4 canvas first, then continue processing.
        Keep aspect ratio and center the content on a white background.
        """
        src = img.convert("RGB")
        src_w, src_h = src.size
        if src_w <= 0 or src_h <= 0:
            return Image.new("RGB", (DocumentModel.A4_WIDTH_PX, DocumentModel.A4_HEIGHT_PX), (255, 255, 255))

        scale = min(DocumentModel.A4_WIDTH_PX / float(src_w), DocumentModel.A4_HEIGHT_PX / float(src_h))
        draw_w = max(1, int(round(src_w * scale)))
        draw_h = max(1, int(round(src_h * scale)))
        resized = src.resize((draw_w, draw_h), Image.Resampling.LANCZOS)

        canvas = Image.new("RGB", (DocumentModel.A4_WIDTH_PX, DocumentModel.A4_HEIGHT_PX), (255, 255, 255))
        x0 = (DocumentModel.A4_WIDTH_PX - draw_w) // 2
        y0 = (DocumentModel.A4_HEIGHT_PX - draw_h) // 2
        canvas.paste(resized, (x0, y0))
        return canvas

    def _load_pdf(self, file_path: str) -> bool:
        try:
            doc = fitz.open(file_path)
            zoom = self._dpi / 72.0
            mat = fitz.Matrix(zoom, zoom)

            for page_num in range(len(doc)):
                page = doc[page_num]
                pix = page.get_pixmap(matrix=mat, alpha=False)
                img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
                a4_img = DocumentModel._normalize_to_a4_canvas(img)
                self._pages.append(a4_img)
                self._original_pages.append(a4_img.copy())

            doc.close()
            return True
        except Exception as e:
            print(f"[pdf_engine] load pdf failed: {e}")
            return False

    def _load_image(self, file_path: str) -> bool:
        try:
            img = Image.open(file_path).convert("RGB")
            a4_img = DocumentModel._normalize_to_a4_canvas(img)
            self._pages.append(a4_img)
            self._original_pages.append(a4_img.copy())
            return True
        except Exception as e:
            print(f"[pdf_engine] load image failed: {e}")
            return False

    def get_page(self, index: int) -> Optional[Image.Image]:
        if 0 <= index < len(self._pages):
            return self._pages[index]
        return None

    def get_original_page(self, index: int) -> Optional[Image.Image]:
        if 0 <= index < len(self._original_pages):
            return self._original_pages[index]
        return None

    def set_page(self, index: int, img: Image.Image):
        if 0 <= index < len(self._pages):
            self._pages[index] = img

    def reset_page(self, index: int):
        if 0 <= index < len(self._original_pages):
            self._pages[index] = self._original_pages[index].copy()

    def delete_page(self, index: int):
        if 0 <= index < len(self._pages):
            self._pages.pop(index)
            self._original_pages.pop(index)

    def move_page(self, from_index: int, to_index: int):
        if 0 <= from_index < len(self._pages) and 0 <= to_index < len(self._pages):
            page = self._pages.pop(from_index)
            orig = self._original_pages.pop(from_index)
            self._pages.insert(to_index, page)
            self._original_pages.insert(to_index, orig)

    def export_pdf(self, output_path: str, dpi: int = 300):
        if not self._pages:
            return
        DocumentModel.export_pdf_from_images(self._pages, output_path, dpi)

    @staticmethod
    def export_pdf_from_images(images: list[Image.Image], output_path: str, dpi: int = 300):
        if not images:
            return

        doc = fitz.open()
        for page_img in images:
            stream_bytes = DocumentModel._encode_page_stream_for_pdf(page_img)

            a4_width_pt = 595.276
            a4_height_pt = 841.890
            page = doc.new_page(width=a4_width_pt, height=a4_height_pt)

            img_w, img_h = page_img.size
            if img_w > 0 and img_h > 0:
                scale = min(a4_width_pt / img_w, a4_height_pt / img_h)
                draw_w = img_w * scale
                draw_h = img_h * scale
                x0 = (a4_width_pt - draw_w) / 2
                y0 = (a4_height_pt - draw_h) / 2
                rect = fitz.Rect(x0, y0, x0 + draw_w, y0 + draw_h)
            else:
                rect = fitz.Rect(0, 0, a4_width_pt, a4_height_pt)

            page.insert_image(rect, stream=stream_bytes)

        # Compact xref/resources to avoid unnecessary PDF bloat.
        doc.save(output_path, garbage=4, deflate=True, clean=True)
        doc.close()

    @staticmethod
    def _encode_page_stream_for_pdf(page_img: Image.Image) -> bytes:
        """Encode a page as PNG/JPEG and choose the smaller practical payload."""
        import io

        rgb = page_img.convert("RGB")

        png_buf = io.BytesIO()
        rgb.save(png_buf, format="PNG", optimize=True, compress_level=9)
        png_bytes = png_buf.getvalue()

        jpeg_bytes = b""
        try:
            jpg_buf = io.BytesIO()
            rgb.save(
                jpg_buf,
                format="JPEG",
                quality=DocumentModel.EXPORT_JPEG_QUALITY,
                optimize=True,
                progressive=True,
                subsampling=1,
            )
            jpeg_bytes = jpg_buf.getvalue()
        except Exception:
            jpeg_bytes = b""

        if jpeg_bytes and len(jpeg_bytes) < (len(png_bytes) * DocumentModel.JPEG_PICK_THRESHOLD):
            return jpeg_bytes
        return png_bytes

    def export_image(self, output_path: str, page_index: int = 0):
        if 0 <= page_index < len(self._pages):
            self._pages[page_index].save(output_path)
