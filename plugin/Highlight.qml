import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Read-along highlighting: one transparent, click-through overlay per
// monitor, driven by Service's speakd watch stream.
//
// Mode "text" draws a marker-pen rectangle over the word being spoken, at
// the position omalexia-locate found it on this screen. Mode "bar" shows
// the sentence in a card along the bottom with the spoken word held in an
// accent pill. The overlay reserves no space and ignores all input.
PanelWindow {
  id: root

  property var service: null
  property var bar: null

  readonly property string mode: service ? service.highlightMode : "off"
  readonly property string style: service ? service.highlightStyle : "word"
  readonly property string sentence: service ? String(service.highlightSentence || "") : ""
  readonly property int sentenceStart: service ? Number(service.highlightSentenceStart) : -1
  readonly property int wordStart: service ? Number(service.highlightWordStart) : -1
  readonly property var box: service ? service.highlightBox : null
  readonly property bool reduced: service && service.look ? service.look.reducedMotion === true : false

  readonly property real screenX: screen ? screen.x : 0
  readonly property real screenY: screen ? screen.y : 0
  readonly property bool boxOnScreen: box !== null && screen !== null
    && box.x + box.w > screenX && box.x < screenX + screen.width
    && box.y + box.h > screenY && box.y < screenY + screen.height

  readonly property bool showMarker: mode === "text" && boxOnScreen
  readonly property bool showBar: mode === "bar" && sentence !== ""

  // Stay mapped for the whole reading: unmapping and remapping a layer
  // surface on every marker gap is exactly the flicker it should not have.
  visible: (service !== null && service.speaking === true && mode !== "off")
           || showMarker || showBar

  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omalexia-read-along"
  WlrLayershell.layer: WlrLayer.Overlay
  color: "transparent"
  mask: Region {}
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // A themed accent works as a marker only when it actually has a hue;
  // grayscale themes get a classic highlighter yellow instead.
  readonly property color markerBase: Color.accent.hslSaturation > 0.35 ? Color.accent : "#f2c744"

  // ---- mode "text": sentence wash + marker over the word ---------------

  // The whole sentence being read gets a steady wash; with the word pill
  // riding on top ("both", faint) or standing alone ("sentence", stronger,
  // since it is then the only cue). It appears the moment a sentence
  // starts and absorbs the odd word the matcher could not place, so the
  // highlight never blinks. Style "word" shows the pill only.
  Repeater {
    model: root.mode === "text" && root.style !== "word" && root.service
           ? root.service.highlightSentenceRects : []
    Rectangle {
      required property var modelData
      x: modelData.x0 - root.screenX - 3
      y: modelData.y - root.screenY - 2
      width: modelData.x1 - modelData.x0 + 6
      height: modelData.h + 4
      radius: Style.space(4)
      color: Qt.alpha(root.markerBase, root.style === "sentence" ? 0.26 : 0.12)
      border.width: root.style === "sentence" ? 1 : 0
      border.color: Qt.alpha(root.markerBase, 0.5)
    }
  }

  // The last known box keeps the pill's geometry stable while it fades
  // out; binding the geometry to a vanished box would snap it to zero.
  property var lastBox: null
  onBoxChanged: if (box !== null) lastBox = box

  Rectangle {
    id: marker
    visible: root.mode === "text" && root.style !== "sentence" && root.lastBox !== null
    opacity: root.showMarker ? 1.0 : 0.0
    x: root.lastBox ? root.lastBox.x - root.screenX - 3 : 0
    y: root.lastBox ? root.lastBox.y - root.screenY - 2 : 0
    width: root.lastBox ? root.lastBox.w + 6 : 0
    height: root.lastBox ? root.lastBox.h + 4 : 0
    radius: Style.space(4)
    color: Qt.alpha(root.markerBase, 0.32)
    border.width: 1
    border.color: Qt.alpha(root.markerBase, 0.6)

    // Glide between words; appear and vanish with a soft fade rather than
    // a pop. Size snaps instantly: a pill that stretches while it moves
    // reads as wobble. The glide is brisk on purpose: at reading speed a
    // short word owns the pill for barely 120 ms, and a slow glide would
    // swallow that visit whole, which reads as a skipped word.
    Behavior on opacity { NumberAnimation { duration: 130 } }
    Behavior on x { enabled: marker.opacity > 0 && !root.reduced; NumberAnimation { duration: 65; easing.type: Easing.OutQuad } }
    Behavior on y { enabled: marker.opacity > 0 && !root.reduced; NumberAnimation { duration: 65; easing.type: Easing.OutQuad } }
  }

  // ---- mode "bar": sentence card with the word in a pill ---------------

  // One entry per whitespace-separated word, same split the daemon uses,
  // carrying the same global char offsets as its word events.
  readonly property var words: {
    if (mode !== "bar") return []
    var list = []
    var re = /\S+/g
    var m
    while ((m = re.exec(sentence)) !== null)
      list.push({ text: m[0], start: sentenceStart + m.index })
    return list
  }

  readonly property color cardBackground: Color.popups.background
  readonly property color textColor: Color.popups.text
  readonly property string readingFont: {
    var look = service ? service.look : null
    if (look && look.font && look.font !== "default" && look.fontLabel) return String(look.fontLabel)
    return bar ? bar.fontFamily : Style.font.family
  }
  readonly property int textPx: Math.round(Style.font.heading * 1.25)
  readonly property real textWidth: {
    var sw = screen ? screen.width : 1920
    return Math.min(sw * 0.62, Style.space(640))
  }

  Rectangle {
    id: card
    visible: root.showBar
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(36)
    width: root.textWidth + Style.space(32)
    height: wordFlow.implicitHeight + Style.space(24)
    radius: Style.space(12)
    color: root.cardBackground
    border.width: 1
    border.color: Qt.alpha(Color.popups.border, 0.4)

    Flow {
      id: wordFlow
      x: Style.space(16)
      y: Style.space(12)
      width: root.textWidth
      spacing: 0

      Repeater {
        model: root.words
        Item {
          id: wordCell
          required property var modelData
          readonly property bool active: modelData.start === root.wordStart
          width: wordText.implicitWidth + Style.space(10)
          height: wordText.implicitHeight + Style.space(6)

          Rectangle {
            anchors.fill: parent
            radius: Style.space(5)
            color: Color.accent
            visible: wordCell.active
          }

          Text {
            id: wordText
            anchors.centerIn: parent
            text: wordCell.modelData.text
            color: wordCell.active ? root.cardBackground : root.textColor
            font.family: root.readingFont
            font.pixelSize: root.textPx
          }
        }
      }
    }
  }
}
