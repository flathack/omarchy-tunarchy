import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
QML = (ROOT / "Panel.qml").read_text(encoding="utf-8")


class QmlContractTests(unittest.TestCase):
    def test_native_panel_contract(self):
        self.assertIn("Panel {", QML)
        self.assertIn('moduleName: "flathack.omaplex-music"', QML)
        self.assertIn("KeyboardPanel {", QML)
        self.assertIn("WidgetButton {", QML)

    def test_helper_uses_argument_array(self):
        self.assertIn('[helperPath, "search", value', QML)
        self.assertNotIn("X-Plex-Token", QML)

    def test_setup_uses_shell_quoting(self):
        self.assertIn("Util.shellQuote(helperPath)", QML)

    def test_player_controls_are_present(self):
        for action in ('control("toggle")', 'control("previous")', 'control("next")', 'control("seek"'):
            self.assertIn(action, QML)


if __name__ == "__main__":
    unittest.main()
