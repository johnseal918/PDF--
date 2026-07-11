import unittest

import numpy as np

from src.core.cv_processor import CVProcessor


class CVProcessorDecolorizeTests(unittest.TestCase):
    def test_smart_enhancement_preserves_fine_lines_and_red_ink(self):
        image = np.full((160, 240, 3), 225, dtype=np.uint8)
        image[30:34, 20:220] = 40
        image[70:72, 20:220] = 190
        image[105:135, 90:150] = (40, 40, 210)

        result = CVProcessor.enhance_document(image, background_cleanup=50, fine_line_preservation=70)

        self.assertLess(result[31, 100].mean(), 40)
        self.assertLess(result[70, 100].mean(), 80)
        self.assertGreater(result[10, 10].mean(), 245)
        self.assertGreater(result[120, 120, 2], 180)
        self.assertLess(result[120, 120, :2].mean(), 80)

    def test_smart_enhancement_is_deterministic(self):
        image = np.full((80, 120, 3), 230, dtype=np.uint8)
        image[20:22, 10:110] = 170
        first = CVProcessor.enhance_document(image, 50, 70)
        second = CVProcessor.enhance_document(image, 50, 70)
        self.assertTrue(np.array_equal(first, second))

    def test_preserves_faint_red_stamp_in_manual_mode(self):
        image = np.full((120, 180, 3), 255, dtype=np.uint8)
        image[40:80, 50:130] = (185, 185, 255)  # BGR: faint red ink

        result = CVProcessor.decolorize(
            image,
            threshold=120,
            mode="manual",
            red_preserve_strength=0.85,
        )

        stamp_area = result[50:70, 70:110, 0]
        self.assertGreater((stamp_area < 128).mean(), 0.95)

    def test_preserves_faint_red_stamp_in_adaptive_mode(self):
        image = np.full((120, 180, 3), 255, dtype=np.uint8)
        image[40:80, 50:130] = (185, 185, 255)  # BGR: faint red ink

        result = CVProcessor.decolorize(
            image,
            threshold=120,
            mode="adaptive",
            red_preserve_strength=0.85,
        )

        stamp_area = result[50:70, 70:110, 0]
        self.assertGreater((stamp_area < 128).mean(), 0.95)

    def test_red_preservation_can_be_disabled(self):
        image = np.full((120, 180, 3), 255, dtype=np.uint8)
        image[40:80, 50:130] = (185, 185, 255)  # BGR: faint red ink

        result = CVProcessor.decolorize(
            image,
            threshold=120,
            mode="manual",
            red_preserve_strength=0.0,
        )

        stamp_area = result[50:70, 70:110, 0]
        self.assertLess((stamp_area < 128).mean(), 0.05)


if __name__ == "__main__":
    unittest.main()
