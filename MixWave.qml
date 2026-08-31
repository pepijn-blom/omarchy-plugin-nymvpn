import QtQuick
import qs.Commons

// Horizontal rule that idles as a 1px divider and, while the tunnel is
// up, jitters into a noisy soundwave — cover traffic as static.
Item {
  id: root

  property color foreground: Color.foreground
  property bool active: false
  property bool connecting: false
  property bool mixnet: false
  property bool playing: false

  readonly property bool live: active || connecting
  readonly property real strength: live ? (mixnet ? 0.4 : 0.3) : 0.12

  implicitWidth: 100
  implicitHeight: live ? Style.space(16) : 1
  width: parent ? parent.width : implicitWidth
  height: implicitHeight

  property int tick: 0

  Behavior on implicitHeight {
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  function noise(x, t) {
    var v = Math.sin(x * 12.9898 + t * 78.233) * 43758.5453
    return v - Math.floor(v)
  }

  function paintColor() {
    var c = root.foreground
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
      + Math.round(c.b * 255) + "," + root.strength + ")"
  }

  Timer {
    interval: root.connecting ? 110 : (root.mixnet ? 42 : 68)
    running: root.playing && root.live
    repeat: true
    onTriggered: {
      root.tick = (root.tick + 1) % 4096
      wave.requestPaint()
    }
  }

  onLiveChanged: wave.requestPaint()
  onPlayingChanged: if (playing) wave.requestPaint()
  onWidthChanged: wave.requestPaint()
  onHeightChanged: wave.requestPaint()
  onForegroundChanged: wave.requestPaint()
  onMixnetChanged: wave.requestPaint()

  Canvas {
    id: wave
    anchors.fill: parent
    antialiasing: false

    onPaint: {
      var ctx = getContext("2d")
      var w = Math.ceil(width)
      var h = Math.ceil(height)
      if (w < 1 || h < 1) return
      ctx.clearRect(0, 0, w, h)
      ctx.fillStyle = root.paintColor()
      if (!root.live || h <= 2) {
        ctx.fillRect(0, 0, w, 1)
        return
      }
      var mid = h / 2
      var step = root.mixnet ? 1 : 2
      var amp = root.connecting ? h * 0.26 : (root.mixnet ? h * 0.48 : h * 0.36)
      var t = root.tick
      ctx.fillRect(0, Math.floor(mid), w, 1)
      for (var x = 0; x < w; x += step) {
        if (root.mixnet && root.noise(x + 17, t + 3) < 0.1) continue
        var env = Math.sin((x / Math.max(1, w - 1)) * Math.PI)
        env = env * env
        var mag = amp * env * (0.2 + 0.8 * root.noise(x, t))
        ctx.fillRect(x, mid - mag, 1, Math.max(1, mag * 2))
      }
    }
  }
}
