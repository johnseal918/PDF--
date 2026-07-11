import os
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from src.ui.property_panel import PropertyPanel


class PropertyPanelRealtimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._app = QApplication.instance() or QApplication([])

    def test_smart_enhancement_controls_expose_two_live_parameters(self):
        panel = PropertyPanel()
        emitted = []
        panel.decolor_params_changed.connect(emitted.append)

        panel.slider_background_cleanup.setValue(65)
        panel.slider_fine_line.setValue(82)

        self.assertEqual(emitted[-1]["background_cleanup"], 65)
        self.assertEqual(emitted[-1]["fine_line_preservation"], 82)
        self.assertNotIn("mode", emitted[-1])

    def test_smart_enhancement_switch_disables_both_sliders(self):
        panel = PropertyPanel()
        panel.chk_enable_decolor.setChecked(False)
        self.assertFalse(panel.slider_background_cleanup.isEnabled())
        self.assertFalse(panel.slider_fine_line.isEnabled())


if __name__ == "__main__":
    unittest.main()
