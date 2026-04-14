"""
pdf_engine.py — PDF/图片统一加载与导出引擎

基于 PyMuPDF (fitz)，将 PDF 和图片统一抽象为"页面列表"。
提供渲染、页面管理、扁平化导出等核心能力。
"""

import fitz  # PyMuPDF
from PIL import Image
from pathlib import Path
from typing import Optional


# 支持的文件格式
SUPPORTED_PDF = {'.pdf'}
SUPPORTED_IMAGE = {'.png', '.jpg', '.jpeg', '.bmp', '.tiff', '.tif'}
SUPPORTED_ALL = SUPPORTED_PDF | SUPPORTED_IMAGE


class DocumentModel:
    """统一文档模型：无论 PDF 还是图片，都被表示为 List[PIL.Image]。"""

    def __init__(self):
        self._pages: list[Image.Image] = []
        self._original_pages: list[Image.Image] = []  # 保留原始副本用于撤销/重置
        self._source_path: Optional[str] = None
        self._is_pdf: bool = False
        self._dpi: int = 300  # 渲染分辨率

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
        """加载文件。成功返回 True。

        Args:
            file_path: PDF 或图片的文件路径。
        """
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
        else:
            self._is_pdf = False
            return self._load_image(file_path)

    def _load_pdf(self, file_path: str) -> bool:
        """使用 PyMuPDF 将 PDF 每页渲染为 PIL Image。"""
        try:
            doc = fitz.open(file_path)
            zoom = self._dpi / 72.0  # PDF 默认 72 DPI
            mat = fitz.Matrix(zoom, zoom)

            for page_num in range(len(doc)):
                page = doc[page_num]
                pix = page.get_pixmap(matrix=mat, alpha=False)
                # fitz Pixmap → PIL Image
                img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
                self._pages.append(img)
                self._original_pages.append(img.copy())

            doc.close()
            return True
        except Exception as e:
            print(f"[pdf_engine] 加载 PDF 失败: {e}")
            return False

    def _load_image(self, file_path: str) -> bool:
        """将单张图片加载为"单页文档"。"""
        try:
            img = Image.open(file_path).convert("RGB")
            self._pages.append(img)
            self._original_pages.append(img.copy())
            return True
        except Exception as e:
            print(f"[pdf_engine] 加载图片失败: {e}")
            return False

    def get_page(self, index: int) -> Optional[Image.Image]:
        """获取指定页面的当前状态（可能已被去色等处理修改）。"""
        if 0 <= index < len(self._pages):
            return self._pages[index]
        return None

    def get_original_page(self, index: int) -> Optional[Image.Image]:
        """获取指定页面的原始未修改版本。"""
        if 0 <= index < len(self._original_pages):
            return self._original_pages[index]
        return None

    def set_page(self, index: int, img: Image.Image):
        """替换指定页面（如去色后的结果）。"""
        if 0 <= index < len(self._pages):
            self._pages[index] = img

    def reset_page(self, index: int):
        """将指定页面重置为原始状态。"""
        if 0 <= index < len(self._original_pages):
            self._pages[index] = self._original_pages[index].copy()

    def delete_page(self, index: int):
        """删除指定页面。"""
        if 0 <= index < len(self._pages):
            self._pages.pop(index)
            self._original_pages.pop(index)

    def move_page(self, from_index: int, to_index: int):
        """移动页面顺序。"""
        if 0 <= from_index < len(self._pages) and 0 <= to_index < len(self._pages):
            page = self._pages.pop(from_index)
            orig = self._original_pages.pop(from_index)
            self._pages.insert(to_index, page)
            self._original_pages.insert(to_index, orig)

    def export_pdf(self, output_path: str, dpi: int = 300):
        """将所有页面扁平化导出为 PDF（每页作为单一光栅化图片）。

        这确保印章无法被 PDF 编辑器分离。
        """
        if not self._pages:
            return
        DocumentModel.export_pdf_from_images(self._pages, output_path, dpi)

    @staticmethod
    def export_pdf_from_images(images: list[Image.Image], output_path: str, dpi: int = 300):
        """以静态方法接收合成图像组并生成纯图PDF"""
        if not images:
            return
        doc = fitz.open()
        for page_img in images:
            import io
            img_bytes = io.BytesIO()
            page_img.save(img_bytes, format="PNG")
            img_bytes.seek(0)
            
            # 使用 A4 比例（ISO 210x297mm）。用户特别要求默认A4尺寸。
            # 或者，按照原图的图片比例按缩放拟合，但用户强调"我们的PDF、图片的尺寸默认都是A4的尺寸"。
            # A4 在 72dpi 下的标准 pt 是 595.28 x 841.89。一般取 595 x 842。
            # 我们将所有的输出都强制锚定在 A4 画布上。如果原图不同，居中绘制或者拉伸。为了不变形，应该适配。
            # 但其实更好的办法是强制 PDF page 为 A4 固定尺寸。
            a4_width_pt = 595.276
            a4_height_pt = 841.890

            page = doc.new_page(width=a4_width_pt, height=a4_height_pt)
            img_w, img_h = page_img.size
            if img_w > 0 and img_h > 0:
                # Fit image into A4 while keeping aspect ratio; center on page.
                scale = min(a4_width_pt / img_w, a4_height_pt / img_h)
                draw_w = img_w * scale
                draw_h = img_h * scale
                x0 = (a4_width_pt - draw_w) / 2
                y0 = (a4_height_pt - draw_h) / 2
                rect = fitz.Rect(x0, y0, x0 + draw_w, y0 + draw_h)
            else:
                rect = fitz.Rect(0, 0, a4_width_pt, a4_height_pt)
            page.insert_image(rect, stream=img_bytes.read())

        doc.save(output_path)
        doc.close()

    def export_image(self, output_path: str, page_index: int = 0):
        """导出指定页面为图片文件。"""
        if 0 <= page_index < len(self._pages):
            self._pages[page_index].save(output_path)
