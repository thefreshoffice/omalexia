import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Omalexia in the bar: an open book that lights up while reading aloud and
// turns urgent while dictation is listening. Left click opens the panel,
// right click reads the selection (or stops), middle click toggles dictation.
BarWidget {
  id: root
  moduleName: "thefreshoffice.omalexia"

  readonly property var service: panelLoader.item ? panelLoader.item.service : null
  readonly property bool speaking: service ? service.speaking : false
  readonly property bool recording: service ? service.recording : false
  readonly property bool transcribing: service ? service.transcribing : false
  readonly property bool ready: service ? (service.installed && service.daemonActive) : false
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color iconColor: recording
    ? (bar ? bar.urgent : Color.urgent)
    : (speaking ? Color.accent : (ready ? barForeground : Qt.darker(barForeground, 1.55)))
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function plain(value) {
    return String(value || "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/</g, "‹").replace(/>/g, "›").replace(/&/g, "＆")
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.service ? root.plain(root.service.statusText) : "Omalexia"
    iconComponent: Component {
      Item {
        Text {
          id: glyph
          anchors.centerIn: parent
          text: root.recording ? "󰍬" : (root.transcribing ? "󰔟" : "󰂺")
          color: root.iconColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
          opacity: root.ready || root.recording ? 1.0 : 0.6

          Behavior on color { ColorAnimation { duration: 160 } }
        }

        Rectangle {
          id: badge
          width: Style.space(4)
          height: width
          radius: width / 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          color: root.recording ? (root.bar ? root.bar.urgent : Color.urgent) : Color.accent
          visible: root.speaking || root.recording || root.transcribing

          SequentialAnimation on opacity {
            running: badge.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) badge.opacity = 1
            NumberAnimation { to: 0.25; duration: 500 }
            NumberAnimation { to: 1.0; duration: 500 }
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton && root.service) root.service.toggleReading()
      else if (buttonCode === Qt.MiddleButton && root.service) root.service.toggleDictation()
      else root.toggle()
    }
  }
}
