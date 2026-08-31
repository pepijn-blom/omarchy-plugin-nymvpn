import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// NymVPN brand mark: the geometric "N" from the official app icon
// (https://nym.com/icons/App-Icon-16x16.svg), drawn as a solid glyph so
// it stays crisp and recognizable at bar sizes — no thin rings to
// collapse into noise.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false
  property bool active: false
  property bool connecting: false
  property bool mixnet: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real glyphOpacity: root.connecting
    ? 0.5 + 0.5 * (0.5 - 0.5 * Math.cos(root.pulse * Math.PI * 2))
    : root.active ? 1.0 : 0.75

  property real pulse: 0
  property real mixProgress: 0

  // Official N path, normalized from the 16x16 app-icon viewBox.
  readonly property string unitPath:
    "M 0.2323 0.2967 C 0.2323 0.2709 0.2532 0.2500 0.2789 0.2500 " +
    "H 0.4486 C 0.4787 0.2500 0.5051 0.2703 0.5129 0.2995 " +
    "L 0.6213 0.7059 C 0.6233 0.7134 0.6344 0.7119 0.6344 0.7042 " +
    "V 0.2500 H 0.7675 V 0.7033 C 0.7675 0.7291 0.7467 0.7500 0.7209 0.7500 " +
    "H 0.5500 C 0.5199 0.7500 0.4936 0.7298 0.4857 0.7007 " +
    "L 0.3785 0.3039 C 0.3765 0.2964 0.3655 0.2979 0.3655 0.3057 " +
    "V 0.7500 H 0.2323 Z"

  property string glyphPath: scaledGlyph()

  function scaledGlyph() {
    return root.unitPath.replace(/-?\d*\.?\d+/g, function(m) {
      return (parseFloat(m) * root.iconSize).toFixed(2)
    })
  }

  onIconSizeChanged: glyphPath = scaledGlyph()

  // The N itself.
  Shape {
    anchors.fill: parent
    antialiasing: true
    opacity: root.glyphOpacity

    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      PathSvg {
        path: root.glyphPath
      }
    }
  }

  // One packet dot nudges along the N's diagonal while connected;
  // mixnet adds a second, dimmer cover-traffic dot going the other way.
  Repeater {
    model: root.active && !root.connecting ? (root.mixnet ? 2 : 1) : 0

    Rectangle {
      readonly property real t: index === 0
        ? root.mixProgress
        : (root.mixProgress + 0.5) % 1
      readonly property bool cover: root.mixnet && index === 1

      width: Math.max(2, root.iconSize * 0.07)
      height: width
      radius: width / 2
      x: (0.512 + 0.110 * t) * root.iconSize - width / 2
      y: (0.300 + 0.404 * t) * root.iconSize - height / 2
      color: cover ? Qt.darker(root.color, 2.2) : root.color
      opacity: cover ? 0.35 : 0.8
    }
  }

  NumberAnimation {
    target: root
    property: "mixProgress"
    from: 0
    to: 1
    duration: root.mixnet ? 2200 : 1300
    loops: Animation.Infinite
    running: root.active && !root.connecting
    easing.type: Easing.InOutQuad
  }

  NumberAnimation {
    id: pulseAnim
    target: root
    property: "pulse"
    from: 0
    to: 1
    duration: 900
    loops: Animation.Infinite
    running: root.connecting
    easing.type: Easing.Linear
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(7, parent.width * 0.62)
      font.bold: true
    }
  }
}