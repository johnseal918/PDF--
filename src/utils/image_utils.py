"""
image_utils.py — 图像格式转换桥接工具

负责 QImage ↔ PIL Image ↔ numpy ndarray 三方互转，
确保 UI 层与 Core 层完全解耦。
"""

import numpy as np
from PIL import Image
from PySide6.QtGui import QImage, QPixmap


def pil_to_qimage(pil_img: Image.Image) -> QImage:
    """将 PIL Image 转换为 QImage。"""
    pil_img = pil_img.convert("RGBA")
    data = pil_img.tobytes("raw", "RGBA")
    qimg = QImage(data, pil_img.width, pil_img.height, QImage.Format.Format_RGBA8888)
    # 必须复制，因为 data 是临时 bytes 对象
    return qimg.copy()


def pil_to_qpixmap(pil_img: Image.Image) -> QPixmap:
    """将 PIL Image 转换为 QPixmap（可直接用于 QGraphicsPixmapItem）。"""
    return QPixmap.fromImage(pil_to_qimage(pil_img))


def qimage_to_pil(qimg: QImage) -> Image.Image:
    """将 QImage 转换为 PIL Image。"""
    qimg = qimg.convertToFormat(QImage.Format.Format_RGBA8888)
    width = qimg.width()
    height = qimg.height()

    # PySide6 中 bits() 返回的是 memoryview
    ptr = qimg.bits()
    arr = np.frombuffer(ptr, dtype=np.uint8).reshape((height, width, 4)).copy()
    return Image.fromarray(arr, "RGBA")


def numpy_to_pil(arr: np.ndarray) -> Image.Image:
    """将 numpy ndarray (BGR 或 RGB) 转换为 PIL Image (RGB)。"""
    if arr.ndim == 2:
        # 灰度图
        return Image.fromarray(arr, "L")
    if arr.shape[2] == 3:
        # 默认 OpenCV 输出为 BGR，需要转为 RGB
        import cv2
        arr_rgb = cv2.cvtColor(arr, cv2.COLOR_BGR2RGB)
        return Image.fromarray(arr_rgb, "RGB")
    elif arr.shape[2] == 4:
        import cv2
        arr_rgba = cv2.cvtColor(arr, cv2.COLOR_BGRA2RGBA)
        return Image.fromarray(arr_rgba, "RGBA")
    return Image.fromarray(arr)


def pil_to_numpy(pil_img: Image.Image) -> np.ndarray:
    """将 PIL Image 转换为 numpy ndarray (BGR 格式，兼容 OpenCV)。"""
    import cv2
    pil_rgb = pil_img.convert("RGB")
    arr = np.array(pil_rgb)
    return cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)
