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
  moduleName: "flathack.omaplex-music"
  ipcTarget: "flathack.omaplex-music"

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

  readonly property url helperUrl: Qt.resolvedUrl("bin/omarchy-omaplex-music")
  readonly property url logoUrl: Qt.resolvedUrl("assets/omaplex.svg")
  readonly property string helperPath: decodeURIComponent(String(helperUrl).replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var activeTrack: player && player.track ? player.track : null
  readonly property bool configured: player && player.configured === true
  readonly property string barText: Model.barLabel(player)
  readonly property bool demoMode: setting("demoMode", false) === true

  function command(args) {
    var result = [helperPath]
    if (demoMode) result.push("--demo")
    for (var index = 0; index < args.length; index++) result.push(String(args[index]))
    return result
  }

  function open() {
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
    if (nextView === "queue") runData("queue", command(["queue"]))
    else {
      var limit = nextView === "recent" ? setting("recentAlbumCount", 20) : setting("libraryItemCount", 100)
      runData(nextView, command(["library", nextView, "--limit", String(limit)]))
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
    backStack = [{ view: view, title: currentParentTitle }]
    currentParentKey = String(item.key || "")
    currentParentKind = String(item.type || "album")
    currentParentTitle = String(item.title || "Collection")
    view = "children"
    runData("children", command(["children", currentParentKind, currentParentKey]))
  }

  function goBack() {
    if (query.trim() !== "") { searchNow(); return }
    var previous = backStack.length > 0 ? backStack[backStack.length - 1] : { view: "recent" }
    loadView(previous.view || "recent")
  }

  function handleData(raw) {
    var parsed = parseJson(raw, null)
    loading = false
    if (!parsed) { errorText = "Plex returned unreadable data."; return }
    items = Model.safeArray(parsed.items)
    if (parsed.stale === true) errorText = parsed.warning || "Showing cached library data while Plex is offline."
    selectedIndex = 0
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
    enabled: root.opened && (root.configured || root.demoMode)
    onActivated: root.switchNavigation(-1)
  }

  Shortcut {
    sequence: "Right"
    context: Qt.ApplicationShortcut
    enabled: root.opened && (root.configured || root.demoMode)
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
    fixedWidth: root.activeTrack ? Style.space(180) : -1
    tooltipText: root.activeTrack ? Model.subtitle(root.activeTrack) : "OmaPlex Music"
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
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(7)

      Image {
        width: Style.space(18)
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        source: root.logoUrl
        fillMode: Image.PreserveAspectFit
        opacity: root.player && root.player.playing ? 1 : 0.78
      }

      Text {
        visible: root.activeTrack !== null
        width: Math.max(0, parent.width - Style.space(34))
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
    focusTarget: searchField
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
            anchors.fill: parent
            source: root.activeTrack ? root.activeTrack.thumb || "" : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: parent.children[0].status !== Image.Ready
            text: ""
          }

          Image {
            anchors.centerIn: parent
            width: Style.space(46)
            height: Style.space(46)
            visible: parent.children[0].status !== Image.Ready
            source: root.logoUrl
            fillMode: Image.PreserveAspectFit
            opacity: 0.8
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(3)

          Text {
            Layout.fillWidth: true
            text: root.activeTrack ? root.activeTrack.title : "OmaPlex Music"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: root.activeTrack ? Model.subtitle(root.activeTrack) : (root.configured ? "Choose something to play" : "Connect your Plex server")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          RowLayout {
            visible: root.activeTrack !== null
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: Model.formatTime(root.player.position)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            PanelSlider {
              Layout.fillWidth: true
              bar: root.bar
              value: Number(root.player.position) || 0
              maximum: Math.max(1, Number(root.player.duration) || 1)
              step: 5
              onReleased: function(next) { root.control("seek", next) }
            }
            Text {
              text: Model.formatTime(root.player.duration)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          RowLayout {
            visible: root.activeTrack !== null
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: "\uf028"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            PanelSlider {
              id: volumeSlider
              Layout.fillWidth: true
              bar: root.bar
              value: Number(root.player.volume) || 0
              minimum: 0
              maximum: 130
              step: 5
              integer: true
              onMoved: function(next) { root.volumeDragging = true }
              onReleased: function(next) { root.volumeDragging = false; root.control("volume", next) }
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
      }

      Row {
        visible: root.activeTrack !== null
        width: parent.width
        spacing: Style.space(16)

        Item { width: Math.max(0, (parent.width - controls.width) / 2); height: 1 }
        Row {
          id: controls
          spacing: Style.space(10)
          PanelActionButton {
            iconText: "\uf074"; tooltipText: root.player && root.player.shuffle ? "Shuffle on" : "Shuffle off"
            foreground: root.player && root.player.shuffle ? Color.urgent : root.foreground
            fontFamily: root.fontFamily; bordered: root.player && root.player.shuffle === true
            onClicked: root.control("shuffle")
          }
          PanelActionButton {
            iconText: "\uf048"; tooltipText: "Previous"; foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.control("previous")
          }
          PanelActionButton {
            size: Style.space(34)
            iconText: root.player && root.player.playing ? "\uf04c" : "\uf04b"
            tooltipText: root.player && root.player.playing ? "Pause" : "Play"
            foreground: root.foreground; fontFamily: root.fontFamily; bordered: true
            onClicked: root.control("toggle")
          }
          PanelActionButton {
            iconText: "\uf051"; tooltipText: "Next"; foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.control("next")
          }
          PanelActionButton {
            iconText: root.player && root.player.repeat === "one" ? "\uf366" : "\uf363"
            tooltipText: root.player && root.player.repeat === "one" ? "Repeat one" : (root.player && root.player.repeat === "all" ? "Repeat all" : "Repeat off")
            foreground: root.player && root.player.repeat !== "off" ? Color.urgent : root.foreground
            fontFamily: root.fontFamily; bordered: root.player && root.player.repeat !== "off"
            onClicked: root.control("repeat")
          }
        }
      }

      PanelActionButton {
        visible: !root.configured && !root.demoMode
        width: parent.width
        height: Style.space(38)
        iconText: "\uf1c0  Connect with Plex"
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.connectPlex()
      }

      CursorSurface {
        visible: !root.health.ok && root.health.code !== "unconfigured" && !root.demoMode
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
            onClicked: root.retryCurrent()
          }
          PanelActionButton {
            visible: root.health.code === "unauthorized" || root.health.code === "library-missing"
            iconText: "\uf013"; tooltipText: "Reconnect"; foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.connectPlex()
          }
        }
      }

      Flickable {
        visible: root.configured || root.demoMode
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
              hasCursor: root.view === modelData.id || (root.view === "children" && root.backStack.length > 0 && root.backStack[0].view === modelData.id)
              foreground: root.foreground

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
        visible: (root.configured || root.demoMode) && root.view !== "queue"
        width: parent.width
        placeholderText: "Search Plex…"
        foreground: root.foreground
        font.family: root.fontFamily
        text: root.query
        onTextChanged: {
          root.query = text
          if (!root.suppressSearch) searchDebounce.restart()
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Left) { root.switchNavigation(-1); event.accepted = true }
          else if (event.key === Qt.Key_Right) { root.switchNavigation(1); event.accepted = true }
          else if (event.key === Qt.Key_Down) { root.moveSelection(1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { root.moveSelection(-1); event.accepted = true }
          else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.items.length > 0) {
            root.activateItem(root.items[root.selectedIndex]); event.accepted = true
          } else if (event.key === Qt.Key_Escape && text !== "") { text = ""; event.accepted = true }
        }
      }

      RowLayout {
        visible: root.configured || root.demoMode
        width: parent.width

        PanelActionButton {
          visible: root.view === "children"
          iconText: "\uf060"
          tooltipText: "Back"
          foreground: root.foreground
          fontFamily: root.fontFamily
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
          onClicked: root.playCollection(false)
        }
        PanelActionButton {
          visible: root.view === "children" && (root.currentParentKind === "album" || root.currentParentKind === "playlist")
          iconText: "\uf074"; tooltipText: "Shuffle collection"; foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.playCollection(true)
        }
        PanelActionButton {
          visible: root.view === "queue" && root.items.length > 0
          iconText: "\uf2ed"; tooltipText: "Clear upcoming"; foreground: root.foreground; fontFamily: root.fontFamily
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
        visible: root.errorText !== ""
        width: parent.width
        text: root.errorText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        visible: (root.configured || root.demoMode) && !root.loading && root.errorText === "" && root.items.length === 0
        width: parent.width
        text: root.view === "search" ? "No matches." : "Nothing here yet."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      ListView {
        id: itemList
        visible: (root.configured || root.demoMode) && root.items.length > 0
        width: parent.width
        height: Math.min(contentHeight, Style.space(330))
        spacing: Style.space(5)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.items
        currentIndex: root.selectedIndex

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: CursorSurface {
          id: mediaRow
          required property var modelData
          required property int index
          width: ListView.view.width
          height: Style.space(54)
          hasCursor: root.selectedIndex === index
          foreground: root.foreground

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
              onClicked: root.playNext(mediaRow.modelData)
            }
            Row {
              visible: (mediaRow.modelData.type === "album" || mediaRow.modelData.type === "playlist") && root.view !== "queue"
              spacing: Style.space(3)
              PanelActionButton {
                iconText: "\uf04b"; tooltipText: "Play"; foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: root.playItemCollection(mediaRow.modelData, false)
              }
              PanelActionButton {
                iconText: "\uf074"; tooltipText: "Shuffle"; foreground: root.foreground; fontFamily: root.fontFamily
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
                onClicked: root.runQueueAction("move", Number(mediaRow.modelData.queueIndex), Math.max(0, Number(mediaRow.modelData.queueIndex) - 1))
              }
              PanelActionButton {
                visible: !mediaRow.modelData.current
                iconText: "\uf063"; tooltipText: "Move down"; foreground: root.foreground; fontFamily: root.fontFamily
                enabled: mediaRow.index < root.items.length - 1
                onClicked: root.runQueueAction("move", Number(mediaRow.modelData.queueIndex), Math.min(root.items.length - 1, Number(mediaRow.modelData.queueIndex) + 1))
              }
              PanelActionButton {
                visible: !mediaRow.modelData.current
                iconText: "\uf00d"; tooltipText: "Remove"; foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: root.runQueueAction("remove", Number(mediaRow.modelData.queueIndex))
              }
            }
          }
        }
      }

      Text {
        visible: root.configured || root.demoMode
        width: parent.width
        text: "Enter to open/play  ·  Middle-click to pause  ·  Right-click for manual setup"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
