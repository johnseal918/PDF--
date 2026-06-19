import unittest

import numpy as np

from src.core.cv_processor import CVProcessor


class CVProcessorDecolorizeTests(unittest.TestCase):
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
