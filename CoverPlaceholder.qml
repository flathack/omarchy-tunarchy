import QtQuick
import qs.Commons

// A small record glyph that stays legible from the bar slot to the player hero.
Item {
  id: root
  property color foreground: Color.accent
  readonly property real discSize: Math.max(1, Math.min(width, height) * 0.66)

  Rectangle {
    anchors.centerIn: parent
    width: root.discSize
    height: width
    radius: width / 2
    color: "transparent"
    border.color: root.foreground
    border.width: Math.max(1, Math.round(width * 0.1))
    opacity: 0.9

    Rectangle {
      anchors.centerIn: parent
      width: Math.max(2, parent.width * 0.22)
      height: width
      radius: width / 2
      color: root.foreground
    }
  }
}
