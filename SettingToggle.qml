import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Labeled toggle row with a question-mark help icon and popup explanation bubble.
// Hovering over the ? shows the explanation bubble; clicking ? pins/expands the explanation inline.
BorderSurface {
  id: root

  property string label: ""
  property string description: ""
  property string help: ""
  property bool checked: false
  property bool hasCursor: false
  property bool rounded: Style.cornerRadius > 0
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real titleSize: Style.font.subtitle
  property real descriptionSize: Style.font.caption
  property bool helpExpanded: false

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: true
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Question || event.text === "?") {
      root.helpExpanded = !root.helpExpanded
      event.accepted = true
    }
  }

  implicitHeight: content.implicitHeight + Style.space(16)
  implicitWidth: Style.space(240)
  radius: Style.cornerRadius

  readonly property bool _hot: hasCursor || rowMouse.containsMouse
  readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (_hot ? "hover-cursor" : "normal"), foreground, accent)

  color: Style.controlFill(activeFocus, _hot, foreground, accent)
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 100 } }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    z: 0
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Column {
    id: content
    z: 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.borderLeft + Style.spacing.rowPaddingX
    anchors.rightMargin: root.borderRight + Style.spacing.rowPaddingX
    spacing: Style.space(6)

    Row {
      width: parent.width
      spacing: Style.spacing.rowPaddingX

      Column {
        width: parent.width - track.width - parent.spacing
        spacing: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: root.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.titleSize
            font.bold: true
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }

          Item {
            id: helpIcon
            z: 10
            width: Style.space(20)
            height: Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.help !== ""

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(16)
              height: Style.space(16)
              radius: width / 2
              color: root.helpExpanded
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
                : (helpMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14) : "transparent")
              border.width: 1
              border.color: root.helpExpanded || helpMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.6)

              Behavior on color { ColorAnimation { duration: 100 } }
              Behavior on border.color { ColorAnimation { duration: 100 } }

              Text {
                anchors.centerIn: parent
                text: "󰋖"
                color: root.helpExpanded || helpMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: helpMouse
              anchors.fill: parent
              z: 10
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                root.helpExpanded = !root.helpExpanded
                mouse.accepted = true
              }
            }

            PanelToolTip {
              id: helpTip
              visible: helpMouse.containsMouse && !root.helpExpanded
              delay: 200
              timeout: 12000
              fontFamily: root.fontFamily
              contentItem: Item {
                implicitWidth: Math.min(Style.space(280), tipText.implicitWidth)
                implicitHeight: tipText.implicitHeight

                Text {
                  id: tipText
                  width: Style.space(280)
                  text: root.help
                  color: helpTip.panelForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  lineHeight: 1.25
                  leftPadding: Border.left(helpTip.panelBorderSpec) + Style.spacing.controlPaddingX
                  rightPadding: Border.right(helpTip.panelBorderSpec) + Style.spacing.controlPaddingX
                  topPadding: Border.top(helpTip.panelBorderSpec) + Style.spacing.controlPaddingY
                  bottomPadding: Border.bottom(helpTip.panelBorderSpec) + Style.spacing.controlPaddingY
                }
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.description !== ""
          text: root.description
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: root.descriptionSize
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }

      ToggleSwitch {
        id: track
        checked: root.checked
        rounded: root.rounded
        foreground: root.foreground
        accent: root.accent
        interactive: false
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Item {
      id: helpBoxClip
      width: parent.width
      clip: true
      visible: height > 0
      height: root.helpExpanded ? helpCard.implicitHeight : 0
      opacity: root.helpExpanded ? 1 : 0

      Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

      Rectangle {
        id: helpCard
        width: parent.width
        implicitHeight: helpText.implicitHeight + Style.space(16)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
        radius: Style.cornerRadius > 0 ? Math.max(2, Style.cornerRadius - 2) : 0
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

        Text {
          id: helpText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.space(8)
          text: root.help
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          lineHeight: 1.25
        }
      }
    }
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
