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
        self.assertIn('command(["search", value', QML)
        self.assertNotIn("X-Plex-Token", QML)

    def test_setup_uses_shell_quoting(self):
        self.assertIn("Util.shellQuote(helperPath)", QML)

    def test_player_controls_are_present(self):
        for action in ('control("toggle")', 'control("previous")', 'control("next")', 'control("seek"',
                       'control("volume"', 'control("shuffle")', 'control("repeat")'):
            self.assertIn(action, QML)

    def test_library_and_queue_navigation_are_present(self):
        for view in ('"artists"', '"albums"', '"playlists"', '"history"', '"frequent"', '"favorites"', '"queue"'):
            self.assertIn(view, QML)
        self.assertIn('runQueueAction("remove"', QML)
        self.assertIn('"play-next"', QML)
        self.assertGreaterEqual(QML.count("items[selectedIndex].current === true"), 2)

    def test_arrow_keys_switch_library_tabs(self):
        self.assertIn('sequence: "Left"', QML)
        self.assertIn('sequence: "Right"', QML)
        self.assertIn("event.key === Qt.Key_Left", QML)
        self.assertIn("event.key === Qt.Key_Right", QML)
        self.assertIn("root.switchNavigation(-1)", QML)
        self.assertIn("root.switchNavigation(1)", QML)
        self.assertIn("readonly property bool navigationShortcutsEnabled", QML)
        self.assertIn("!searchField.activeFocus", QML)
        self.assertIn("!seekFocus.activeFocus", QML)
        self.assertIn("!volumeFocus.activeFocus", QML)

    def test_complete_keyboard_navigation_contract(self):
        self.assertGreaterEqual(QML.count("focusable: true"), 15)
        self.assertGreaterEqual(QML.count("activeFocusOnTab: true"), 3)
        for contract in ('sequence: "Escape"', 'sequence: "Ctrl+Space"', "root.handleEscape()",
                         "moveQueueSelection", "removeSelectedQueueItem", "Accessible.name"):
            self.assertIn(contract, QML)
        self.assertIn('event.key === Qt.Key_Left && text === ""', QML)
        self.assertIn('event.key === Qt.Key_Right && text === ""', QML)

    def test_keyboard_help_is_available_from_button_and_f1(self):
        self.assertIn("property bool helpVisible: false", QML)
        self.assertIn("readonly property var keyboardHelp", QML)
        self.assertIn('id: helpButton', QML)
        self.assertIn('iconText: "?"', QML)
        self.assertIn('sequence: "F1"', QML)
        self.assertIn('text: root.helpVisible ? "Keyboard map"', QML)
        self.assertNotIn("↑↓ Select  ·  Enter Play", QML)

    def test_plex_login_and_demo_mode_are_present(self):
        self.assertIn('" login"', QML)
        self.assertIn('setting("demoMode", false)', QML)


if __name__ == "__main__":
    unittest.main()
