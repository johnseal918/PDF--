"""
cv_processor.py — 视觉（CV级）基础拟真引擎

封装 OpenCV (cv2) 来执行文档的一键脱灰去白（二值化），
以及渲染基于高斯分发的高频纤维图点（扫描底噪），以打破电子洁净感。
"""

import cv2
import numpy as np


class CVProcessor:
    """视觉处理核心类"""

    @staticmethod
    def _red_ink_mask(image: np.ndarray, strength: float) -> np.ndarray:
        strength = max(0.0, min(1.0, float(strength)))
        if strength <= 0.0:
            return np.zeros(image.shape[:2], dtype=bool)

        hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
        hue = hsv[:, :, 0]
        saturation = hsv[:, :, 1]
        value = hsv[:, :, 2]

        bgr = image.astype(np.int16)
        blue = bgr[:, :, 0]
        green = bgr[:, :, 1]
        red = bgr[:, :, 2]
        red_dominance = red - np.maximum(green, blue)

        red_hue = (hue <= 12) | (hue >= 168)
        saturation_min = int(round(90 - (70 * strength)))
        dominance_min = int(round(55 - (45 * strength)))

        return (
            red_hue
            & (saturation >= saturation_min)
            & (red_dominance >= dominance_min)
            & (value >= 50)
        )

    @staticmethod
    def enhance_document(
        image: np.ndarray,
        background_cleanup: int = 50,
        fine_line_preservation: int = 70,
    ) -> np.ndarray:
        """Clean the background while preserving text, fine lines, and red ink."""
        cleanup = max(0, min(100, int(background_cleanup)))
        fine = max(0, min(100, int(fine_line_preservation)))
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

        strong_threshold = int(round(105 + cleanup * 0.7))
        strong_mask = gray <= strong_threshold

        block_size = 15 + 2 * int(round(fine / 10))
        if block_size % 2 == 0:
            block_size += 1
        c_value = max(1, int(round(8 - fine * 0.1)))
        local_mask = cv2.adaptiveThreshold(
            gray,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY_INV,
            block_size,
            c_value,
        ) > 0
        max_line_gray = int(round(220 + fine * 0.4))
        local_background = cv2.GaussianBlur(gray, (0, 0), sigmaX=7.0)
        local_contrast = local_background.astype(np.int16) - gray.astype(np.int16)
        contrast_threshold = max(1, int(round(10 - fine * 0.14)))
        contrast_mask = (local_contrast >= contrast_threshold) & (gray <= 250)
        content_mask = strong_mask | (local_mask & (gray <= max_line_gray)) | contrast_mask

        result = np.full_like(image, 255)
        result[content_mask] = (0, 0, 0)
        red_mask = CVProcessor._red_ink_mask(image, 1.0)
        result[red_mask] = image[red_mask]
        return result

    @staticmethod
    def decolorize(
        image: np.ndarray,
        threshold: int = 120,
        mode: str = 'otsu',
        red_preserve_strength: float = 0.85,
    ) -> np.ndarray:
        """
        将彩色或带灰底的杂图转换为白底黑字的二值图像扫描件。
        
        Args:
            image: OpenCV 默认读取带来的 BGR numpy 阵列。
            threshold: 在 manual 模式下的二值化分水岭 (0-255)。
            mode: 算法模式，'otsu' / 'adaptive' / 'manual'。
            
        Returns:
            虽然是二值图黑白视觉，为了后续处理统一，强行三通道传回 BGR。
        """
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        red_mask = CVProcessor._red_ink_mask(image, red_preserve_strength)
        
        if mode == 'otsu':
            # Otsu's binarization (自动计算最适阈值，对对比强烈的文档奇效)
            _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        elif mode == 'adaptive':
            # 适应性二值化，对光照不均匀的手机拍版比较好
            binary = cv2.adaptiveThreshold(
                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
                cv2.THRESH_BINARY, 15, 5
            )
        else:
            # 绝对人工配置模式（manual）
            _, binary = cv2.threshold(gray, threshold, 255, cv2.THRESH_BINARY)
            
        # 转回三通道用于叠色及与透明盖章合成
        if red_mask.any():
            binary[red_mask] = 0

        return cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)

    @staticmethod
    def add_paper_noise(image: np.ndarray, intensity: float = 0.03) -> np.ndarray:
        """
        在纸张的白色底膜上注入微观纤维颗粒的高斯扫描噪带。
        
        Args:
            image: BGR 图形矩阵
            intensity: 分部系数（0.0 ~ 0.1 之间比较合理，默认 0.03）
            
        Returns:
            注入杂斑的输出矩阵。
        """
        if intensity <= 0:
            return image
            
        # 根据当前图片长宽尺寸起一张相同分辨率的 3通道 矩阵浮点型空画板，填充自然高斯正态噪声点
        noise = np.random.normal(0, intensity * 255, image.shape).astype(np.float32)
        
        # 为了不破坏黑色的墨水和字体（不然黑字上全是白口水点子），进行一个简单遮罩
        # 提取灰阶度 > 200 的像素点（基本判定为纸张空白区）
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        light_mask = (gray > 200).astype(np.float32)
        
        # 撑满三通道
        light_mask = np.stack([light_mask] * 3, axis=-1)
        
        # 把底噪唯独注入那些很白的区域。使得看起来非常真实地像陈旧纸张或扫描件
        result = image.astype(np.float32) + noise * light_mask
        
        # 裁剪防止溢出黑化
        return np.clip(result, 0, 255).astype(np.uint8)
