import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.flathack.tunarchy"
  ipcTarget: "io.github.flathack.tunarchy"

  property var player: ({ configured: false, playing: false, track: null, position: 0, duration: 0, volume: 100, shuffle: false, repeat: "off" })
  property var items: []
  property var health: ({ ok: false, code: "unconfigured", message: "Connect your Plex account to start listening." })
  property var backStack: []
  property string view: "recent"
  property string currentParentKey: ""
  property string currentParentKind: ""
  property string currentParentTitle: ""
  property string query: ""
  property string errorText: ""
  property bool loading: false
  property int selectedIndex: 0
  property string pendingDataMode: "recent"
  property bool volumeDragging: false
  property bool suppressSearch: false
  property int pendingSelectedIndex: -1
  property bool helpVisible: false

  readonly property var navigation: [
    { id: "recent", label: "Home", icon: "\uf015" },
    { id: "artists", label: "Artists", icon: "\uf0c0" },
    { id: "albums", label: "Albums", icon: "\uf51f" },
    { id: "playlists", label: "Lists", icon: "\uf03a" },
    { id: "history", label: "Recent", icon: "\uf1da" },
    { id: "frequent", label: "Top", icon: "\uf201" },
    { id: "favorites", label: "Favs", icon: "\uf004" },
    { id: "queue", label: "Queue", icon: "\uf03b" }
  ]

  readonly property var keyboardHelp: [
    { keys: "← / →", action: "Switch library tabs" },
    { keys: "↑ / ↓", action: "Select a list item" },
    { keys: "Enter", action: "Open or play" },
    { keys: "Tab / Shift+Tab", action: "Move keyboard focus" },
    { keys: "Ctrl+Enter", action: "Play a collection" },
    { keys: "Shift+Enter", action: "Shuffle or play next" },
    { keys: "Ctrl+↑ / ↓", action: "Move a Queue item" },
    { keys: "Delete", action: "Remove a Queue item" },
    { keys: "Ctrl+Space", action: "Play or pause" },
    { keys: "Home / End", action: "Set a slider to its limit" },
    { keys: "Esc", action: "Clear, go back, or close" },
    { keys: "F1", action: "Toggle this help" }
  ]

  readonly property url helperUrl: Qt.resolvedUrl("bin/tunarchy")
  readonly property url tunaBrandUrl: Qt.resolvedUrl("assets/tuna-brand.png")
  readonly property url tuna18Url: Qt.resolvedUrl("assets/tuna-ui-18.png")
  readonly property url tuna24Url: Qt.resolvedUrl("assets/tuna-ui-24.png")
  readonly property url tuna64Url: Qt.resolvedUrl("assets/tuna-ui-64.png")
  readonly property rect tuna18Clip: Qt.rect(520, 325, 500, 360)
  readonly property rect tuna24Clip: Qt.rect(350, 250, 850, 525)
  readonly property rect tuna64Clip: Qt.rect(60, 35, 1440, 900)
  readonly property string helperPath: decodeURIComponent(String(helperUrl).replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var activeTrack: player && player.track ? player.track : null
  readonly property string activeThumb: activeTrack ? String(activeTrack.thumb || "") : ""
  readonly property bool configured: player && player.configured === true
  readonly property string barText: Model.barLabel(player)
  readonly property bool demoMode: setting("demoMode", false) === true
  readonly property bool navigationShortcutsEnabled: opened && (configured || demoMode)
    && !helpVisible && !searchField.activeFocus && !seekFocus.activeFocus && !volumeFocus.activeFocus

  function command(args) {
    var result = [helperPath]
    if (demoMode) result.push("--demo")
    for (var index = 0; index < args.length; index++) result.push(String(args[index]))
    return result
  }

  function open() {
    helpVisible = false
    controller.show()
    refreshStatus()
    refreshHealth()
    if (configured || demoMode) loadView("recent")
    Qt.callLater(searchField.forceActiveFocus)
  }

  function close() {
    controller.hide()
    query = ""
    errorText = ""
    helpVisible = false
  }

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "{}")) }
    catch (error) { return fallback }
  }

  function errorMessage(raw, fallback) {
    var value = String(raw || "").trim()
    var parsed = parseJson(value, null)
    return parsed && parsed.message ? String(parsed.message) : (value || fallback)
  }

  function refreshStatus() {
    statusProc.command = command(["status"])
    if (!statusProc.running) statusProc.running = true
  }

  function refreshHealth() {
    healthProc.command = command(["health"])
    if (!healthProc.running) healthProc.running = true
  }

  function retryCurrent() {
    refreshHealth()
    if (view === "queue") runData("queue", command(["queue"]))
    else if (view === "children") runData("children", command(["children", currentParentKind, currentParentKey]))
    else if (view === "search") searchNow()
    else loadView(view)
  }

  function applyStatus(raw) {
    var parsed = parseJson(raw, null)
    if (parsed) {
      var wasConfigured = configured
      player = parsed
      if (opened && !wasConfigured && (parsed.configured === true || demoMode) && items.length === 0 && !loading)
        loadView("recent")
    }
  }

  function runData(mode, command) {
    if (dataProc.running) dataProc.running = false
    pendingDataMode = mode
    loading = true
    errorText = ""
    dataProc.command = command
    dataProc.running = true
  }

  function loadView(nextView) {
    suppressSearch = true
    query = ""
    searchDebounce.stop()
    Qt.callLater(function() { root.suppressSearch = false })
    view = nextView
    currentParentKey = ""
    currentParentKind = ""
    currentParentTitle = ""
    backStack = []
    if (nextView === "queue") {
      runData("queue", command(["queue"]))
      Qt.callLater(itemList.forceActiveFocus)
    }
    else {
      var limit = nextView === "recent" ? setting("recentAlbumCount", 20) : setting("libraryItemCount", 100)
      runData(nextView, command(["library", nextView, "--limit", String(limit)]))
      Qt.callLater(searchField.forceActiveFocus)
    }
  }

  function searchNow() {
    var value = query.trim()
    if (value === "") { loadView("recent"); return }
    view = "search"
    currentParentKey = ""
    currentParentKind = ""
    currentParentTitle = ""
    runData("search", command(["search", value, "--limit", "35"]))
  }

  function openContainer(item) {
    backStack = [{ view: view, title: currentParentTitle, query: query }]
    suppressSearch = true
    query = ""
    searchDebounce.stop()
    Qt.callLater(function() { root.suppressSearch = false })
    currentParentKey = String(item.key || "")
    currentParentKind = String(item.type || "album")
    currentParentTitle = String(item.title || "Collection")
    view = "children"
    runData("children", command(["children", currentParentKind, currentParentKey]))
  }

  function goBack() {
    var previous = backStack.length > 0 ? backStack[backStack.length - 1] : { view: "recent" }
    if (previous.view === "search" && String(previous.query || "").trim() !== "") {
      query = String(previous.query)
      searchNow()
    } else loadView(previous.view || "recent")
  }

  function handleEscape() {
    if (helpVisible) {
      helpVisible = false
      Qt.callLater(helpButton.forceActiveFocus)
    } else if (query.trim() !== "") {
      suppressSearch = true
      query = ""
      searchDebounce.stop()
      Qt.callLater(function() { root.suppressSearch = false })
      loadView("recent")
    } else if (view === "children") goBack()
    else close()
  }

  function handleData(raw) {
    var parsed = parseJson(raw, null)
    loading = false
    if (!parsed) { errorText = "Plex returned unreadable data."; return }
    items = Model.safeArray(parsed.items)
    if (parsed.stale === true) errorText = parsed.warning || "Showing cached library data while Plex is offline."
    selectedIndex = pendingSelectedIndex >= 0
      ? Math.max(0, Math.min(items.length - 1, pendingSelectedIndex)) : 0
    pendingSelectedIndex = -1
  }

  function activateItem(item) {
    if (!item || actionProc.running) return
    if (item.type === "album" || item.type === "artist" || item.type === "playlist") { openContainer(item); return }
    if (view === "queue") { runQueueAction("play", Number(item.queueIndex)); return }
    var args = ["play", String(item.key)]
    if (view === "children" && currentParentKind === "album") args.push("--album", currentParentKey)
    if (view === "children" && currentParentKind === "playlist") args.push("--playlist", currentParentKey)
    runAction(command(args))
  }

  function runAction(command) {
    if (actionProc.running) return
    actionProc.command = command
    actionProc.running = true
  }

  function control(action, value) {
    var args = ["control", action]
    if (value !== undefined) args.push(String(value))
    runAction(command(args))
  }

  function connectPlex() {
    close()
    if (bar) bar.run("omarchy launch floating terminal with presentation " + Util.shellQuote(helperPath) + " login")
  }

  function manualSetup() {
    close()
    if (bar) bar.run("omarchy launch floating terminal with presentation " + Util.shellQuote(helperPath) + " configure")
  }

  function playCollection(shuffle) {
    if (currentParentKind !== "album" && currentParentKind !== "playlist") return
    var args = ["play-collection", currentParentKind, currentParentKey]
    if (shuffle) args.push("--shuffle")
    runAction(command(args))
  }

  function playItemCollection(item, shuffle) {
    if (!item || (item.type !== "album" && item.type !== "playlist")) return
    var args = ["play-collection", item.type, String(item.key)]
    if (shuffle) args.push("--shuffle")
    runAction(command(args))
  }

  function runQueueAction(action, index, destination) {
    var args = ["queue-action", action]
    if (index !== undefined) args.push("--index", String(index))
    if (destination !== undefined) args.push("--to", String(destination))
    runData("queue", command(args))
  }

  function playNext(item) {
    if (!item) return
    if (!activeTrack) { activateItem(item); return }
    if (queueEditProc.running) return
    queueEditProc.command = command(["queue-action", "play-next", "--track", String(item.key)])
    queueEditProc.running = true
  }

  function moveSelection(delta) {
    if (items.length === 0) return
    selectedIndex = Math.max(0, Math.min(items.length - 1, selectedIndex + delta))
    Qt.callLater(function() { itemList.positionViewAtIndex(selectedIndex, ListView.Contain) })
  }

  function moveQueueSelection(delta) {
    if (view !== "queue" || items.length === 0) return
    if (items[selectedIndex].current === true) return
    var destination = Math.max(0, Math.min(items.length - 1, selectedIndex + delta))
    if (destination === selectedIndex) return
    pendingSelectedIndex = destination
    runQueueAction("move", Number(items[selectedIndex].queueIndex), destination)
  }

  function removeSelectedQueueItem() {
    if (view !== "queue" || items.length === 0) return
    if (items[selectedIndex].current === true) return
    pendingSelectedIndex = Math.max(0, Math.min(items.length - 2, selectedIndex))
    runQueueAction("remove", Number(items[selectedIndex].queueIndex))
  }

  function activateSelection(modifiers) {
    if (items.length === 0) return
    var item = items[selectedIndex]
    if ((modifiers & Qt.ShiftModifier) && item.type === "track" && view !== "queue") {
      playNext(item); return
    }
    if ((modifiers & Qt.ShiftModifier) && (item.type === "album" || item.type === "playlist")) {
      playItemCollection(item, true); return
    }
    if ((modifiers & Qt.ControlModifier) && (item.type === "album" || item.type === "playlist")) {
      playItemCollection(item, false); return
    }
    activateItem(item)
  }

  function handleListKey(event) {
    if (event.key === Qt.Key_Down) {
      if ((event.modifiers & Qt.ControlModifier) && view === "queue") moveQueueSelection(1)
      else moveSelection(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      if ((event.modifiers & Qt.ControlModifier) && view === "queue") moveQueueSelection(-1)
      else moveSelection(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Delete && view === "queue") {
      removeSelectedQueueItem(); event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activateSelection(event.modifiers); event.accepted = true
    }
  }

  function switchNavigation(delta) {
    if ((!configured && !demoMode) || navigation.length === 0) return
    var activeView = view
    if (view === "children" && backStack.length > 0) activeView = backStack[0].view
    var current = 0
    for (var index = 0; index < navigation.length; index++) {
      if (navigation[index].id === activeView) { current = index; break }
    }
    var next = (current + delta + navigation.length) % navigation.length
    loadView(navigation[next].id)
  }

  Shortcut {
    sequence: "Left"
    context: Qt.ApplicationShortcut
    enabled: root.navigationShortcutsEnabled
    onActivated: root.switchNavigation(-1)
  }

  Shortcut {
    sequence: "Escape"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: root.handleEscape()
  }

  Shortcut {
    sequence: "Ctrl+Space"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.activeTrack !== null
    onActivated: root.control("toggle")
  }

  Shortcut {
    sequence: "F1"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: {
      root.helpVisible = !root.helpVisible
      Qt.callLater(helpButton.forceActiveFocus)
    }
  }

  Shortcut {
    sequence: "Right"
    context: Qt.ApplicationShortcut
    enabled: root.navigationShortcutsEnabled
    onActivated: root.switchNavigation(1)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }

  Process {
    id: queueEditProc
    stderr: StdioCollector { id: queueEditError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = root.errorMessage(queueEditError.text, "Could not update the queue.")
      root.refreshStatus()
    }
  }

  Process {
    id: healthProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseJson(text, null)
        if (parsed) root.health = parsed
      }
    }
  }

  Process {
    id: dataProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleData(text) }
    stderr: StdioCollector { id: dataError; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) root.errorText = root.errorMessage(dataError.text, "Could not load the Plex library.")
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = root.errorMessage(actionError.text, "Player action failed.")
      root.refreshStatus()
      if (root.view === "queue") root.runData("queue", root.command(["queue"]))
    }
  }

  Timer {
    interval: root.opened ? 1000 : 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.refreshHealth()
  }

  Timer {
    id: searchDebounce
    interval: 350
    onTriggered: root.searchNow()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : (root.activeTrack ? Style.space(180) : Style.bar.iconSlot)
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    tooltipText: root.activeTrack
      ? root.activeTrack.title + (Model.subtitle(root.activeTrack) ? " · " + Model.subtitle(root.activeTrack) : "")
      : "Tunarchy"
    active: root.player && root.player.playing === true
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.manualSetup()
      else if (mouseButton === Qt.MiddleButton && root.activeTrack) root.control("toggle")
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (root.activeTrack) root.control(delta > 0 ? "previous" : "next")
    }

    Row {
      id: barContent
      anchors.centerIn: parent
      width: button.vertical ? coverFrame.width : parent.width - Style.space(16)
      height: coverFrame.height
      spacing: Style.space(7)

      Rectangle {
        id: coverFrame
        width: Math.min(Style.space(20), button.barSize - Style.space(8))
        height: width
        anchors.verticalCenter: parent.verticalCenter
        radius: Math.max(2, Style.cornerRadius / 2)
        color: Style.selectedFillFor(button.foreground, Color.accent)
        clip: true
        opacity: root.player && root.player.playing ? 1 : 0.78

        Image {
          id: barCover
          anchors.fill: parent
          source: root.activeThumb
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          visible: root.activeThumb !== "" && status === Image.Ready
        }

        Image {
          anchors.fill: parent
          anchors.margins: Style.space(2)
          source: root.tuna24Url
          sourceClipRect: root.tuna24Clip
          fillMode: Image.PreserveAspectFit
          smooth: false
          mipmap: false
          visible: !barCover.visible
        }
      }

      Text {
        visible: root.activeTrack !== null && !button.vertical
        width: Math.max(0, parent.width - coverFrame.width - parent.spacing)
        anchors.verticalCenter: parent.verticalCenter
        text: root.activeTrack ? root.activeTrack.title : ""
        color: button.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: root.helpVisible ? helpButton : (root.configured || root.demoMode)
      ? (root.view === "queue" ? itemList : searchField) : connectButton
    contentWidth: fittedContentWidth(Style.space(540))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight, Style.space(790))

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(12)

      RowLayout {
        width: parent.width
        spacing: Style.space(12)

        Rectangle {
          Layout.preferredWidth: Style.space(82)
          Layout.preferredHeight: Style.space(82)
          radius: Style.cornerRadius
          color: Style.selectedFillFor(root.foreground, Color.accent)
          clip: true

          Image {
            id: headerCover
            anchors.fill: parent
            source: root.activeTrack ? root.activeTrack.thumb || "" : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: !root.helpVisible && status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: !root.helpVisible && headerCover.status !== Image.Ready
            text: ""
          }

          Image {
            id: helpHeaderLogo
            anchors.centerIn: parent
            width: root.helpVisible ? Style.space(64) : Style.space(46)
            height: width
            visible: root.helpVisible || headerCover.status !== Image.Ready
            source: root.helpVisible ? root.tuna64Url : root.tuna24Url
            sourceClipRect: root.helpVisible ? root.tuna64Clip : root.tuna24Clip
            fillMode: Image.PreserveAspectFit
            smooth: false
            mipmap: false
            opacity: root.helpVisible ? 1 : 0.8
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(3)

          Text {
            Layout.fillWidth: true
            text: root.helpVisible ? "Keyboard map" : (root.activeTrack ? root.activeTrack.title : "Tunarchy")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: root.helpVisible ? "Every control works without a mouse"
              : (root.activeTrack ? Model.subtitle(root.activeTrack) : (root.configured ? "Choose something to play" : "Connect your Plex server"))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          RowLayout {
            visible: root.activeTrack !== null && !root.helpVisible
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: Model.formatTime(root.player.position)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            BorderSurface {
              id: seekFocus
              Layout.fillWidth: true
              Layout.preferredHeight: seekSlider.implicitHeight + Style.space(4)
              radius: Style.cornerRadius
              color: activeFocus ? Style.focusFillFor(root.foreground, Color.accent) : "transparent"
              borderSpec: activeFocus ? Border.controlSpec("focus", root.foreground, Color.accent) : Border.none()
              activeFocusOnTab: true
              Accessible.role: Accessible.Slider
              Accessible.name: "Playback position"
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
                  root.control("seek", Math.max(0, Number(root.player.position) - 5)); event.accepted = true
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
                  root.control("seek", Math.min(Number(root.player.duration) || 0, Number(root.player.position) + 5)); event.accepted = true
                } else if (event.key === Qt.Key_Home) {
                  root.control("seek", 0); event.accepted = true
                } else if (event.key === Qt.Key_End) {
                  root.control("seek", Number(root.player.duration) || 0); event.accepted = true
                }
              }

              PanelSlider {
                id: seekSlider
                anchors.fill: parent
                anchors.margins: Style.space(2)
                bar: root.bar
                value: Number(root.player.position) || 0
                maximum: Math.max(1, Number(root.player.duration) || 1)
                step: 5
                onReleased: function(next) { root.control("seek", next) }
              }
            }
            Text {
              text: Model.formatTime(root.player.duration)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          RowLayout {
            visible: root.activeTrack !== null && !root.helpVisible
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: "\uf028"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            BorderSurface {
              id: volumeFocus
              Layout.fillWidth: true
              Layout.preferredHeight: volumeSlider.implicitHeight + Style.space(4)
              radius: Style.cornerRadius
              color: activeFocus ? Style.focusFillFor(root.foreground, Color.accent) : "transparent"
              borderSpec: activeFocus ? Border.controlSpec("focus", root.foreground, Color.accent) : Border.none()
              activeFocusOnTab: true
              Accessible.role: Accessible.Slider
              Accessible.name: "Volume"
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
                  root.control("volume", Math.max(0, Number(root.player.volume) - 5)); event.accepted = true
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
                  root.control("volume", Math.min(130, Number(root.player.volume) + 5)); event.accepted = true
                } else if (event.key === Qt.Key_Home) {
                  root.control("volume", 0); event.accepted = true
                } else if (event.key === Qt.Key_End) {
                  root.control("volume", 130); event.accepted = true
                }
              }

              PanelSlider {
                id: volumeSlider
                anchors.fill: parent
                anchors.margins: Style.space(2)
                bar: root.bar
                value: Number(root.player.volume) || 0
                minimum: 0
                maximum: 130
                step: 5
                integer: true
                onMoved: function(next) { root.volumeDragging = true }
                onReleased: function(next) { root.volumeDragging = false; root.control("volume", next) }
              }
            }
            Text {
              text: Math.round(root.volumeDragging ? volumeSlider.liveValue : Number(root.player.volume) || 0) + "%"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              Layout.preferredWidth: Style.space(36)
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        PanelActionButton {
          id: helpButton
          Layout.alignment: Qt.AlignTop
          size: Style.space(28)
          iconText: ""
          tooltipText: root.helpVisible ? "Close keyboard help" : "Keyboard help"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          bordered: root.helpVisible
          focusable: true
          Accessible.name: tooltipText
          onClicked: {
            root.helpVisible = !root.helpVisible
            forceActiveFocus()
          }

          Image {
            id: helpButtonLogo
            anchors.centerIn: parent
            width: Style.space(22)
            height: width
            source: root.tuna24Url
            sourceClipRect: root.tuna24Clip
            fillMode: Image.PreserveAspectFit
            smooth: false
            mipmap: false
          }
        }
      }

      BorderSurface {
        visible: root.helpVisible
        width: parent.width
        implicitHeight: helpColumn.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Style.selectedFillFor(root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Column {
          id: helpColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(4)

          Repeater {
            model: root.keyboardHelp
            delegate: RowLayout {
              required property var modelData
              width: helpColumn.width
              spacing: Style.space(10)

              BorderSurface {
                Layout.preferredWidth: Style.space(142)
                Layout.preferredHeight: Style.space(22)
                radius: Style.cornerRadius / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: modelData.keys
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                Layout.fillWidth: true
                text: modelData.action
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      Row {
        visible: root.activeTrack !== null && !root.helpVisible
        width: parent.width
        spacing: Style.space(16)

        Item { width: Math.max(0, (parent.width - controls.width) / 2); height: 1 }
        Row {
          id: controls
          spacing: Style.space(10)
          PanelActionButton {
            iconText: "\uf074"; tooltipText: root.player && root.player.shuffle ? "Shuffle on" : "Shuffle off"
            foreground: root.player && root.player.shuffle ? Color.urgent : root.foreground
            fontFamily: root.fontFamily; bordered: root.player && root.player.shuffle === true; focusable: true
            Accessible.name: tooltipText
            onClicked: root.control("shuffle")
          }
          PanelActionButton {
            iconText: "\uf048"; tooltipText: "Previous"; foreground: root.foreground; fontFamily: root.fontFamily
            focusable: true; Accessible.name: tooltipText
            onClicked: root.control("previous")
          }
          PanelActionButton {
            id: playButton
            size: Style.space(34)
            iconText: ""
            tooltipText: root.player && root.player.playing ? "Pause" : "Play"
            foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; focusable: true
            Accessible.name: tooltipText
            onClicked: root.control("toggle")

            Image {
              id: playButtonTuna
              anchors.centerIn: parent
              width: Style.space(27)
              height: width
              source: root.tuna18Url
              sourceClipRect: root.tuna18Clip
              fillMode: Image.PreserveAspectFit
              smooth: false
              mipmap: false
              opacity: root.player && root.player.playing ? 1 : 0.82
            }
          }
          PanelActionButton {
            iconText: "\uf051"; tooltipText: "Next"; foreground: root.foreground; fontFamily: root.fontFamily
            focusable: true; Accessible.name: tooltipText
            onClicked: root.control("next")
          }
          PanelActionButton {
            iconText: root.player && root.player.repeat === "one" ? "\uf366" : "\uf363"
            tooltipText: root.player && root.player.repeat === "one" ? "Repeat one" : (root.player && root.player.repeat === "all" ? "Repeat all" : "Repeat off")
            foreground: root.player && root.player.repeat !== "off" ? Color.urgent : root.foreground
            fontFamily: root.fontFamily; bordered: root.player && root.player.repeat !== "off"; focusable: true
            Accessible.name: tooltipText
            onClicked: root.control("repeat")
          }
        }
      }

      PanelActionButton {
        id: connectButton
        visible: !root.helpVisible && !root.configured && !root.demoMode
        width: parent.width
        height: Style.space(38)
        iconText: "\uf1c0  Connect with Plex"
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        focusable: true
        Accessible.name: "Connect with Plex"
        onClicked: root.connectPlex()
      }

      CursorSurface {
        visible: !root.helpVisible && !root.health.ok && root.health.code !== "unconfigured" && !root.demoMode
        width: parent.width
        height: healthRow.implicitHeight + Style.space(14)
        foreground: Color.urgent

        RowLayout {
          id: healthRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)
          Text { text: "\uf071"; color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.icon }
          Text {
            Layout.fillWidth: true
            text: root.health.message || "Plex is not reachable."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
          PanelActionButton {
            iconText: "\uf2f1"; tooltipText: "Retry"; foreground: root.foreground; fontFamily: root.fontFamily
            focusable: true; Accessible.name: tooltipText
            onClicked: root.retryCurrent()
          }
          PanelActionButton {
            visible: root.health.code === "unauthorized" || root.health.code === "library-missing"
            iconText: "\uf013"; tooltipText: "Reconnect"; foreground: root.foreground; fontFamily: root.fontFamily
            focusable: true; Accessible.name: tooltipText
            onClicked: root.connectPlex()
          }
        }
      }

      Flickable {
        visible: !root.helpVisible && (root.configured || root.demoMode)
        width: parent.width
        height: Style.space(38)
        contentWidth: navRow.implicitWidth
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
          id: navRow
          spacing: Style.space(4)

          Repeater {
            model: root.navigation
            delegate: CursorSurface {
              id: navItem
              required property var modelData
              width: Style.space(59)
              height: Style.space(34)
              activeFocusOnTab: true
              hasCursor: activeFocus
              current: root.view === modelData.id || (root.view === "children" && root.backStack.length > 0 && root.backStack[0].view === modelData.id)
              foreground: root.foreground
              Accessible.role: Accessible.PageTab
              Accessible.name: modelData.label
              Keys.onReturnPressed: root.loadView(modelData.id)
              Keys.onEnterPressed: root.loadView(modelData.id)
              Keys.onSpacePressed: root.loadView(modelData.id)

              Text {
                id: navLabel
                anchors.centerIn: parent
                text: navItem.modelData.icon + " " + navItem.modelData.label
                color: navItem.hasCursor ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: navItem.hasCursor
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.loadView(navItem.modelData.id)
              }
            }
          }
        }
      }

      TextField {
        id: searchField
        visible: !root.helpVisible && (root.configured || root.demoMode) && root.view !== "queue"
        width: parent.width
        placeholderText: "Search Plex…"
        Accessible.name: "Search Plex music"
        foreground: root.foreground
        font.family: root.fontFamily
        text: root.query
        onTextChanged: {
          root.query = text
          if (!root.suppressSearch) searchDebounce.restart()
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Left && text === "") { root.switchNavigation(-1); event.accepted = true }
          else if (event.key === Qt.Key_Right && text === "") { root.switchNavigation(1); event.accepted = true }
          else if (event.key === Qt.Key_Escape) { root.handleEscape(); event.accepted = true }
          else root.handleListKey(event)
        }
      }

      RowLayout {
        visible: !root.helpVisible && (root.configured || root.demoMode)
        width: parent.width

        PanelActionButton {
          visible: root.view === "children"
          iconText: "\uf060"
          tooltipText: "Back"
          foreground: root.foreground
          fontFamily: root.fontFamily
          focusable: true
          Accessible.name: tooltipText
          onClicked: root.goBack()
        }
        Text {
          Layout.fillWidth: true
          text: root.view === "children" ? root.currentParentTitle
            : (root.view === "search" ? "Search results"
            : (root.view === "queue" ? "Up next"
            : (root.navigation.find(function(entry) { return entry.id === root.view }) || { label: "Library" }).label))
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }
        PanelActionButton {
          visible: root.view === "children" && (root.currentParentKind === "album" || root.currentParentKind === "playlist")
          iconText: "\uf04b"; tooltipText: "Play collection"; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true
          focusable: true; Accessible.name: tooltipText
          onClicked: root.playCollection(false)
        }
        PanelActionButton {
          visible: root.view === "children" && (root.currentParentKind === "album" || root.currentParentKind === "playlist")
          iconText: "\uf074"; tooltipText: "Shuffle collection"; foreground: root.foreground; fontFamily: root.fontFamily
          focusable: true; Accessible.name: tooltipText
          onClicked: root.playCollection(true)
        }
        PanelActionButton {
          visible: root.view === "queue" && root.items.length > 0
          iconText: "\uf2ed"; tooltipText: "Clear upcoming"; foreground: root.foreground; fontFamily: root.fontFamily
          focusable: true; Accessible.name: tooltipText
          onClicked: root.runQueueAction("clear-upcoming")
        }
        Text {
          text: root.loading ? "Loading…" : root.items.length + (root.items.length === 1 ? " item" : " items")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        visible: !root.helpVisible && root.errorText !== ""
        width: parent.width
        text: root.errorText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        visible: !root.helpVisible && (root.configured || root.demoMode) && !root.loading && root.errorText === "" && root.items.length === 0
        width: parent.width
        text: root.view === "search" ? "No matches." : "Nothing here yet."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      ListView {
        id: itemList
        visible: !root.helpVisible && (root.configured || root.demoMode) && root.items.length > 0
        width: parent.width
        height: Math.min(contentHeight, Style.space(330))
        spacing: Style.space(5)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.items
        currentIndex: root.selectedIndex
        activeFocusOnTab: true
        Accessible.role: Accessible.List
        Accessible.name: root.view === "queue" ? "Playback queue" : "Media results"
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.handleEscape(); event.accepted = true }
          else root.handleListKey(event)
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: CursorSurface {
          id: mediaRow
          required property var modelData
          required property int index
          width: ListView.view.width
          height: Style.space(54)
          hasCursor: root.selectedIndex === index
          foreground: root.foreground
          Accessible.role: Accessible.ListItem
          Accessible.name: (modelData.title || "Untitled") + ", " + Model.subtitle(modelData)

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = mediaRow.index
            onClicked: root.activateItem(mediaRow.modelData)
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(10)

            Rectangle {
              Layout.preferredWidth: Style.space(38)
              Layout.preferredHeight: Style.space(38)
              radius: Style.cornerRadius / 2
              color: Style.selectedFillFor(root.foreground, Color.accent)
              clip: true
              Image { anchors.fill: parent; source: mediaRow.modelData.thumb || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1
              Text {
                Layout.fillWidth: true
                text: mediaRow.modelData.title || "Untitled"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                Layout.fillWidth: true
                text: Model.subtitle(mediaRow.modelData)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            Text {
              visible: root.view !== "queue" && mediaRow.modelData.type !== "album" && mediaRow.modelData.type !== "playlist"
              text: mediaRow.modelData.type === "artist" ? mediaRow.modelData.leafCount + " albums" : Model.formatTime(mediaRow.modelData.duration)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            PanelActionButton {
              visible: root.view !== "queue" && mediaRow.modelData.type === "track"
              iconText: "\uf2f9"; tooltipText: "Play next"; foreground: root.foreground; fontFamily: root.fontFamily
              focusable: true; Accessible.name: tooltipText + ": " + (mediaRow.modelData.title || "track")
              onClicked: root.playNext(mediaRow.modelData)
            }
            Row {
              visible: (mediaRow.modelData.type === "album" || mediaRow.modelData.type === "playlist") && root.view !== "queue"
              spacing: Style.space(3)
              PanelActionButton {
                iconText: "\uf04b"; tooltipText: "Play"; foreground: root.foreground; fontFamily: root.fontFamily
                focusable: true; Accessible.name: tooltipText + ": " + (mediaRow.modelData.title || "collection")
                onClicked: root.playItemCollection(mediaRow.modelData, false)
              }
              PanelActionButton {
                iconText: "\uf074"; tooltipText: "Shuffle"; foreground: root.foreground; fontFamily: root.fontFamily
                focusable: true; Accessible.name: tooltipText + ": " + (mediaRow.modelData.title || "collection")
                onClicked: root.playItemCollection(mediaRow.modelData, true)
              }
              Text { text: "\uf054"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
              visible: root.view === "queue"
              spacing: Style.space(2)
              Text {
                visible: mediaRow.modelData.current === true
                text: root.player && root.player.playing ? "\uf04b" : "\uf04c"
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
              PanelActionButton {
                visible: !mediaRow.modelData.current
                iconText: "\uf062"; tooltipText: "Move up"; foreground: root.foreground; fontFamily: root.fontFamily
                enabled: mediaRow.index > 0
                focusable: true; Accessible.name: tooltipText + ": " + (mediaRow.modelData.title || "track")
                onClicked: root.runQueueAction("move", Number(mediaRow.modelData.queueIndex), Math.max(0, Number(mediaRow.modelData.queueIndex) - 1))
              }
              PanelActionButton {
                visible: !mediaRow.modelData.current
                iconText: "\uf063"; tooltipText: "Move down"; foreground: root.foreground; fontFamily: root.fontFamily
                enabled: mediaRow.index < root.items.length - 1
                focusable: true; Accessible.name: tooltipText + ": " + (mediaRow.modelData.title || "track")
                onClicked: root.runQueueAction("move", Number(mediaRow.modelData.queueIndex), Math.min(root.items.length - 1, Number(mediaRow.modelData.queueIndex) + 1))
              }
              PanelActionButton {
                visible: !mediaRow.modelData.current
                iconText: "\uf00d"; tooltipText: "Remove"; foreground: root.foreground; fontFamily: root.fontFamily
                focusable: true; Accessible.name: tooltipText + ": " + (mediaRow.modelData.title || "track")
                onClicked: root.runQueueAction("remove", Number(mediaRow.modelData.queueIndex))
              }
            }
          }
        }
      }

    }
  }
}
