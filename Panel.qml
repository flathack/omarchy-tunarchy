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

  property var player: ({ configured: false, playing: false, track: null, position: 0, duration: 0, volume: 100 })
  property var items: []
  property string view: "recent"
  property string currentAlbum: ""
  property string currentAlbumTitle: ""
  property string query: ""
  property string errorText: ""
  property bool loading: false
  property int selectedIndex: 0
  property string pendingDataMode: "recent"

  readonly property url helperUrl: Qt.resolvedUrl("bin/omarchy-omaplex-music")
  readonly property string helperPath: decodeURIComponent(String(helperUrl).replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var activeTrack: player && player.track ? player.track : null
  readonly property bool configured: player && player.configured === true
  readonly property string barText: Model.barLabel(player)

  function open() {
    controller.show()
    refreshStatus()
    if (configured) loadRecent()
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

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(raw) {
    var parsed = parseJson(raw, null)
    if (parsed) player = parsed
  }

  function runData(mode, command) {
    if (dataProc.running) dataProc.running = false
    pendingDataMode = mode
    loading = true
    errorText = ""
    dataProc.command = command
    dataProc.running = true
  }

  function loadRecent() {
    view = "recent"
    currentAlbum = ""
    currentAlbumTitle = ""
    runData("recent", [helperPath, "recent", "--limit", String(setting("recentAlbumCount", 20))])
  }

  function searchNow() {
    var value = query.trim()
    if (value === "") { loadRecent(); return }
    view = "search"
    currentAlbum = ""
    currentAlbumTitle = ""
    runData("search", [helperPath, "search", value, "--limit", "35"])
  }

  function openAlbum(item) {
    currentAlbum = String(item.key || "")
    currentAlbumTitle = String(item.title || "Album")
    view = "album"
    runData("album", [helperPath, "tracks", currentAlbum])
  }

  function handleData(raw) {
    var parsed = parseJson(raw, null)
    loading = false
    if (!parsed) { errorText = "Plex returned unreadable data."; return }
    items = Model.safeArray(parsed.items)
    selectedIndex = 0
  }

  function activateItem(item) {
    if (!item || actionProc.running) return
    if (item.type === "album") { openAlbum(item); return }
    var command = [helperPath, "play", String(item.key)]
    if (view === "album" && currentAlbum !== "") command.push("--album", currentAlbum)
    runAction(command)
  }

  function runAction(command) {
    if (actionProc.running) return
    actionProc.command = command
    actionProc.running = true
  }

  function control(action, value) {
    var command = [helperPath, "control", action]
    if (value !== undefined) command.push(String(value))
    runAction(command)
  }

  function setup() {
    close()
    if (bar) bar.run("omarchy launch floating terminal with presentation " + Util.shellQuote(helperPath) + " configure")
  }

  function moveSelection(delta) {
    if (items.length === 0) return
    selectedIndex = Math.max(0, Math.min(items.length - 1, selectedIndex + delta))
    Qt.callLater(function() { itemList.positionViewAtIndex(selectedIndex, ListView.Contain) })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: [root.helperPath, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }

  Process {
    id: dataProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleData(text) }
    stderr: StdioCollector { id: dataError; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) root.errorText = String(dataError.text || "Could not load the Plex library.").trim()
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = String(actionError.text || "Player action failed.").trim()
      root.refreshStatus()
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
      if (mouseButton === Qt.RightButton) root.setup()
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

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.player && root.player.playing ? "\uf04b" : "\uf001"
        color: root.player && root.player.playing ? button.activeColor : button.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        visible: root.activeTrack !== null
        width: Math.max(0, parent.width - Style.space(30))
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
    contentWidth: fittedContentWidth(Style.space(470))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

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
            text: "\uf001"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
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
        }
      }

      PanelActionButton {
        visible: !root.configured
        width: parent.width
        height: Style.space(38)
        iconText: "\uf1c0  Configure Plex"
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.setup()
      }

      TextField {
        id: searchField
        visible: root.configured
        width: parent.width
        placeholderText: "Search Plex…"
        foreground: root.foreground
        font.family: root.fontFamily
        text: root.query
        onTextChanged: { root.query = text; searchDebounce.restart() }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Down) { root.moveSelection(1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { root.moveSelection(-1); event.accepted = true }
          else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.items.length > 0) {
            root.activateItem(root.items[root.selectedIndex]); event.accepted = true
          } else if (event.key === Qt.Key_Escape && text !== "") { text = ""; event.accepted = true }
        }
      }

      RowLayout {
        visible: root.configured
        width: parent.width

        PanelActionButton {
          visible: root.view === "album"
          iconText: "\uf060"
          tooltipText: "Back"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.query.trim() === "" ? root.loadRecent() : root.searchNow()
        }
        Text {
          Layout.fillWidth: true
          text: root.view === "album" ? root.currentAlbumTitle : (root.view === "search" ? "Search results" : "Recently added")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
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
        visible: root.configured && !root.loading && root.errorText === "" && root.items.length === 0
        width: parent.width
        text: root.view === "search" ? "No matches." : "Nothing here yet."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      ListView {
        id: itemList
        visible: root.configured && root.items.length > 0
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
              text: mediaRow.modelData.type === "album" ? "\uf054" : Model.formatTime(mediaRow.modelData.duration)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Text {
        visible: root.configured
        width: parent.width
        text: "Enter to open/play  ·  Middle-click bar to pause  ·  Right-click to configure"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
