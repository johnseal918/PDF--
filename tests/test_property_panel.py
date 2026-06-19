import os
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from src.ui.property_panel import PropertyPanel


class PropertyPanelRealtimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._app = QApplication.instance() or QApplication([])

    def test_red_preserve_slider_emits_params_while_changing(self):
        panel = PropertyPanel()
        emitted = []
        panel.decolor_params_changed.connect(emitted.append)

        panel.slider_red_preserve.setValue(72)

        self.assertTrue(emitted)
        self.assertEqual(emitted[-1]["red_preserve_strength"], 0.72)

    def test_threshold_slider_is_adjustable_and_switches_to_manual(self):
        panel = PropertyPanel()
        emitted = []
        panel.decolor_params_changed.connect(emitted.append)

        panel.combo_mode.setCurrentText("otsu")
        self.assertTrue(panel.slider_thresh.isEnabled())

        panel.slider_thresh.setValue(160)

        self.assertEqual(panel.combo_mode.currentText(), "manual")
        self.assertTrue(emitted)
        self.assertEqual(emitted[-1]["mode"], "manual")
        self.assertEqual(emitted[-1]["threshold"], 160)


if __name__ == "__main__":
    unittest.main()
