import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
QML = (ROOT / "Panel.qml").read_text(encoding="utf-8")
MODEL = (ROOT / "Model.js").read_text(encoding="utf-8")


class QmlContractTests(unittest.TestCase):
    def test_native_panel_contract(self):
        self.assertIn("Panel {", QML)
        self.assertIn('moduleName: "io.github.flathack.tunarchy"', QML)
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

    def test_bar_shows_active_album_cover_with_logo_fallback(self):
        self.assertIn("readonly property string activeThumb", QML)
        self.assertIn("id: barCover", QML)
        self.assertIn("source: root.activeThumb", QML)
        self.assertIn("source: root.tuna24Url", QML)
        self.assertIn("visible: !barCover.visible", QML)
        self.assertIn("fixedHeight: vertical ? Style.bar.iconSlot", QML)

    def test_tuna_assets_scale_across_player_ui(self):
        self.assertIn('Qt.resolvedUrl("assets/tuna-ui-24.png")', QML)
        self.assertIn('Qt.resolvedUrl("assets/tuna-ui-64.png")', QML)
        self.assertGreaterEqual(QML.count("smooth: false"), 3)
        self.assertNotIn("sourceClipRect", QML)
        self.assertNotIn("tunaBrandUrl", QML)

    def test_play_button_reflects_playback_state(self):
        self.assertIn("id: playButton", QML)
        self.assertIn('iconText: root.player && root.player.playing ? "\\uf04c" : "\\uf04b"', QML)
        self.assertIn('tooltipText: root.player && root.player.playing ? "Pause" : "Play"', QML)
        self.assertGreaterEqual(QML.count('root.player && root.player.playing ? "\\uf04c" : "\\uf04b"'), 2)
        self.assertIn('status.playing ? "\\uf04c  " : "\\uf04b  "', MODEL)

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

    def test_rapid_tab_switches_only_apply_the_latest_request(self):
        self.assertIn("property int requestedDataRequestId: 0", QML)
        self.assertIn("property int activeDataRequestId: 0", QML)
        self.assertIn("property int queuedDataRequestId: 0", QML)
        self.assertIn("finishedRequestId === requestedDataRequestId", QML)
        self.assertIn("root.finishData(exitCode, dataOutput.text, dataError.text)", QML)
        self.assertNotIn("onStreamFinished: root.handleData(text)", QML)

    def test_nested_navigation_preserves_complete_context(self):
        self.assertIn("Model.navigationState(", QML)
        self.assertIn("backStack.concat", QML)
        self.assertIn("currentParentKey = String(previous.parentKey", QML)
        self.assertIn("currentParentKind = String(previous.parentKind", QML)
        self.assertIn("pendingSelectedIndex = Number(previous.selectedIndex", QML)
        self.assertIn("Model.navigationArgs(previous", QML)
        for field in ("parentKey", "parentKind", "selectedIndex"):
            self.assertIn(field, MODEL)

    def test_player_actions_are_queued_and_slider_updates_coalesced(self):
        self.assertIn("property var pendingActions: []", QML)
        self.assertIn("pendingActions = Model.queueAction(pendingActions, nextCommand)", QML)
        self.assertIn('kind !== "seek" && kind !== "volume"', MODEL)
        self.assertIn("root.pendingActions = root.pendingActions.slice(1)", QML)
        self.assertIn("MAX_PENDING_ACTIONS = 8", MODEL)
        self.assertIn("pendingQueueEdits.length >= 16", QML)
        self.assertNotIn("if (actionProc.running) return", QML)

    def test_volume_updates_optimistically_while_the_slider_moves(self):
        self.assertIn("function setVolume(value)", QML)
        self.assertIn("updated.volume = next", QML)
        self.assertIn("onMoved: function(next) { root.setVolume(next) }", QML)
        self.assertIn("volumeSlider.dragging ? volumeSlider.liveValue", QML)
        self.assertNotIn("property bool volumeDragging", QML)

    def test_status_polling_is_adaptive(self):
        self.assertIn("root.opened ? 3000", QML)
        self.assertIn("root.player && root.player.playing ? 10000", QML)
        self.assertIn("root.activeTrack ? 15000 : 30000", QML)
        self.assertIn("root.advanceProgress()", QML)

    def test_queue_mutations_are_not_sent_through_cancellable_data_process(self):
        queue_function = QML[QML.index("function runQueueAction"):QML.index("function playNext")]
        self.assertIn("runQueueEdit(command(args))", queue_function)
        self.assertNotIn("runData(", queue_function)
        self.assertIn('if (root.view === "queue") root.runData', QML)

    def test_artwork_is_lazy_bounded_and_decode_limited(self):
        self.assertIn('command(["art", activeArtwork])', QML)
        self.assertIn("pendingArtwork.length >= 32", QML)
        self.assertIn("property int artworkGeneration: 0", QML)
        self.assertIn("requestedArtwork[value]", QML)
        self.assertIn("if (artProc.running) artProc.running = false", QML)
        self.assertIn("generation === root.artworkGeneration", QML)
        self.assertIn("resolvedArtworkOrder", QML)
        self.assertIn("while (order.length > 128)", QML)
        self.assertIn("root.artworkThumb(mediaRow.modelData)", QML)
        self.assertNotIn("var nextItems = []", QML)
        self.assertGreaterEqual(QML.count("sourceSize.width:"), 3)
        self.assertIn("maximumLength: 256", QML)

    def test_status_and_health_process_errors_are_visible(self):
        self.assertIn("id: statusError", QML)
        self.assertIn("id: healthError", QML)
        self.assertIn('"Could not refresh player status."', QML)
        self.assertIn('code: "helper-error"', QML)
        self.assertIn("message.length > 400", QML)

    def test_active_artwork_uses_async_frontend_pipeline(self):
        self.assertIn("if (parsed.track) requestArtwork(parsed.track.artSource)", QML)
        self.assertIn("activeTrack ? artworkThumb(activeTrack)", QML)
        self.assertIn("source: root.activeThumb", QML)

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
        self.assertIn('id: helpButtonLogo', QML)
        self.assertIn('id: helpHeaderLogo', QML)
        self.assertIn('width: root.helpVisible ? Style.space(64) : Style.space(46)', QML)
        self.assertNotIn('iconText: "?"', QML)
        self.assertIn('sequence: "F1"', QML)
        self.assertIn('text: root.helpVisible ? "Tunarchy"', QML)
        self.assertIn('text: root.helpVisible ? "Keyboard map · Every control works without a mouse"', QML)
        self.assertNotIn("↑↓ Select  ·  Enter Play", QML)

    def test_plex_login_and_demo_mode_are_present(self):
        self.assertIn('" login"', QML)
        self.assertIn('setting("demoMode", false)', QML)


if __name__ == "__main__":
    unittest.main()
