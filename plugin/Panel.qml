import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The Omalexia panel: read aloud, dictate, and the reading layout, with the
// current settings visible and changeable in place. Every control funnels
// through Service -> status.py -> the same omalexia commands the keys use.
//
// Keyboard: j/k or arrows move between rows, h/l or Left/Right walk the
// buttons in a row (or nudge a slider / cycle a dropdown), Enter activates,
// Esc closes, Tab switches to the neighbouring bar panel.
Panel {
  id: root
  moduleName: "thefreshoffice.omalexia"
  ipcTarget: "thefreshoffice.omalexia"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property alias service: omalexia

  // ---- cursor model ---------------------------------------------------------

  property bool cursorActive: false
  property int cursorIndex: 0
  property int actionIndex: 0
  property bool dropdownOpen: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var read: omalexia.read
  readonly property var dictation: omalexia.dictation
  readonly property var look: omalexia.look
  readonly property bool dictationInstalled: dictation.installed === true
  readonly property bool showDictation: omalexia.showDictation
  readonly property bool showLook: omalexia.showLook

  // Rows in drawing order. Each key maps to one focusable row; sections
  // that are hidden drop out of the list so the cursor never lands on them.
  readonly property var rows: {
    var keys = ["hero"]
    if (!omalexia.installed) return keys.concat(["install"])
    keys.push("read.actions", "read.speed", "read.voiceEn", "read.voiceNl", "read.language", "read.test")
    if (showDictation) {
      if (dictationInstalled) keys.push("dict.actions", "dict.engine", "dict.feedback", "dict.showTyped")
      else keys.push("dict.install")
    }
    if (showLook) keys.push("look.actions", "look.narrow", "look.tint", "look.motion", "look.font", "look.size")
    keys.push("footer")
    return keys
  }
  readonly property string cursorKey: rows.length === 0 ? "" : rows[Math.max(0, Math.min(rows.length - 1, cursorIndex))]

  function hasCursor(key) { return cursorActive && cursorKey === key }
  function actionHasCursor(key, index) { return hasCursor(key) && actionIndex === index }

  function actionCount(key) {
    if (key === "read.actions") return 4
    if (key === "dict.actions") return 4
    if (key === "look.actions") return 2
    if (key === "footer") return 3
    return 1
  }

  function setCursor(key, index) {
    cursorActive = true
    var i = rows.indexOf(key)
    if (i >= 0) cursorIndex = i
    if (index !== undefined) actionIndex = index
  }

  function ensureCursor() {
    if (cursorIndex >= rows.length) cursorIndex = Math.max(0, rows.length - 1)
    actionIndex = Math.max(0, Math.min(actionIndex, actionCount(cursorKey) - 1))
  }

  function cycleOption(options, current, delta) {
    if (!options || options.length === 0) return current
    var idx = -1
    for (var i = 0; i < options.length; i++) {
      var v = (options[i] && typeof options[i] === "object") ? String(options[i].value) : String(options[i])
      if (v === String(current)) { idx = i; break }
    }
    var next = (idx + delta + options.length) % options.length
    var o = options[next]
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy !== 0) {
      cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + dy))
      actionIndex = 0
      scrollCursorIntoView()
      return
    }
    if (dx === 0) return
    var key = cursorKey
    if (key === "read.speed") {
      var next = Math.max(0.5, Math.min(4.0, Number(read.speed || 1) + dx * 0.1))
      omalexia.set("speed", next.toFixed(1))
    } else if (key === "read.voiceEn") {
      omalexia.set("voiceEn", cycleOption(read.voicesEn, read.voiceEn, dx))
    } else if (key === "read.voiceNl") {
      omalexia.set("voiceNl", cycleOption(read.voicesNl, read.voiceNl, dx))
    } else if (key === "read.language") {
      omalexia.set("language", cycleOption(languageOptions, read.language, dx))
    } else if (key === "dict.engine") {
      omalexia.set("dictationEngine", cycleOption(engineOptions, dictation.engine, dx))
    } else if (key === "look.font") {
      omalexia.set("font", cycleOption(look.fonts, look.font, dx))
    } else if (key === "look.size") {
      omalexia.set("textSize", cycleOption(sizeOptions, String(look.textSize), dx))
    } else {
      actionIndex = Math.max(0, Math.min(actionCount(key) - 1, actionIndex + dx))
    }
  }

  function activateCursor() {
    ensureCursor()
    var key = cursorKey
    switch (key) {
    case "hero": omalexia.toggleDaemon(); break
    case "install": omalexia.act("install"); break
    case "read.actions":
      if (actionIndex === 0) omalexia.readSelection()
      else if (actionIndex === 1) omalexia.readClipboard()
      else if (actionIndex === 2) { root.close(); omalexia.readScreen() }
      else omalexia.stopReading()
      break
    case "read.test": omalexia.testVoice(read.language === "nl" ? "nl" : "en"); break
    case "read.voiceEn": voiceEnDropdown.toggle(); break
    case "read.voiceNl": voiceNlDropdown.toggle(); break
    case "read.language": languageDropdown.toggle(); break
    case "dict.actions":
      if (actionIndex === 0) omalexia.toggleDictation()
      else if (actionIndex === 1) omalexia.cancelDictation()
      else if (actionIndex === 2) omalexia.act("word-list")
      else omalexia.act("dictation-restart")
      break
    case "dict.install": omalexia.act("dictation-install"); break
    case "dict.engine": engineDropdown.toggle(); break
    case "dict.feedback": omalexia.set("feedback", dictation.feedback ? "false" : "true"); break
    case "dict.showTyped": omalexia.set("showTyped", dictation.showTyped ? "false" : "true"); break
    case "look.actions":
      if (actionIndex === 0) { root.close(); omalexia.toggleReadingMode() }
      else omalexia.act("theme", "flexoki-light")
      break
    case "look.narrow": omalexia.set("narrowSingleWindow", look.narrowSingleWindow ? "false" : "true"); break
    case "look.tint": omalexia.set("tint", look.tint ? "false" : "true"); break
    case "look.motion": omalexia.set("reducedMotion", look.reducedMotion ? "false" : "true"); break
    case "look.font": fontDropdown.toggle(); break
    case "look.size": sizeDropdown.toggle(); break
    case "footer":
      if (actionIndex === 0) omalexia.openKeys()
      else if (actionIndex === 1) { root.close(); omalexia.openMenu() }
      else omalexia.refresh()
      break
    }
  }

  function scrollCursorIntoView() {
    var item = rowItems[cursorKey]
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  // Rows register themselves here so the keyboard cursor can scroll to them.
  property var rowItems: ({})
  function registerRow(key, item) {
    var next = {}
    for (var k in rowItems) next[k] = rowItems[k]
    next[key] = item
    rowItems = next
  }

  readonly property var languageOptions: {
    // The daemon reads any language with an enabled voice; the options come
    // from the config via status.py so `omalexia voice add de` shows up here.
    var fromStatus = read.languageOptions || []
    if (fromStatus.length > 1) return fromStatus
    return [
      { value: "auto", label: "Detect from the text" },
      { value: "en", label: "English" },
      { value: "nl", label: "Nederlands" }
    ]
  }
  readonly property var sizeOptions: [
    { value: "12", label: "Normal (12)" },
    { value: "14", label: "Comfortable (14)" },
    { value: "16", label: "Large (16)" },
    { value: "18", label: "Extra large (18)" }
  ]
  readonly property var engineOptions: {
    var options = []
    if (dictation.parakeetAvailable) options.push({ value: "parakeet", label: "Parakeet TDT v3 (Dutch + English)" })
    if (dictation.whisperAvailable) options.push({ value: "whisper", label: "Whisper base.en (English)" })
    if (options.length === 0) options.push({ value: String(dictation.engine || "whisper"), label: String(dictation.engine || "whisper") })
    return options
  }
  readonly property var voiceEnOptions: {
    var options = (read.voicesEn || []).slice()
    if (read.kokoroInstalled) options.push({ value: "kokoro", label: "Kokoro, premium (slower start)" })
    else options.push({ value: "kokoro", label: "Kokoro, premium (installs ~350 MB)" })
    return options
  }
  readonly property string voiceEnValue: read.engineEn === "kokoro" ? "kokoro" : String(read.voiceEn || "")

  function chooseEnglishVoice(value) {
    if (value === "kokoro") omalexia.set("engineEn", "kokoro")
    else {
      if (read.engineEn === "kokoro") omalexia.set("engineEn", "piper")
      omalexia.set("voiceEn", value)
    }
  }

  readonly property string heroMeta: {
    if (!omalexia.installed) return "Not installed"
    if (omalexia.recording) return "Listening"
    if (omalexia.transcribing) return "Typing what you said"
    if (omalexia.speaking) return "Reading aloud"
    if (!omalexia.daemonActive) return "Read-aloud off"
    return "Ready"
  }

  implicitWidth: 0
  implicitHeight: 0

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    actionIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    omalexia.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onRowsChanged: ensureCursor()

  Service {
    id: omalexia
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { omalexia.refresh(); return "ok" }
    function read(): string { omalexia.toggleReading(); return "ok" }
    function stop(): string { omalexia.stopReading(); return "ok" }
    function dictate(): string { omalexia.toggleDictation(); return "ok" }
    function status(): string { return omalexia.statusText }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.dropdownOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") omalexia.readSelection()
        else if (t === "s" || t === "S") omalexia.stopReading()
        else if (t === "d" || t === "D") omalexia.toggleDictation()
        else if (t === "+" || t === "=") omalexia.set("speed", Math.min(4.0, Number(root.read.speed || 1) + 0.1).toFixed(1))
        else if (t === "-") omalexia.set("speed", Math.max(0.5, Number(root.read.speed || 1) - 0.1).toFixed(1))
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---- hero ---------------------------------------------------------

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.hasCursor("hero")
            function focusHero() { root.setCursor("hero") }
            Component.onCompleted: root.registerRow("hero", header)

            PanelHero {
              id: hero
              width: parent.width
              title: "Omalexia"
              meta: root.heroMeta
              detail: omalexia.speaking ? "F10 stops" : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: omalexia.installed && omalexia.daemonActive ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: omalexia.recording ? "󰍬" : "󰂺"
                  color: omalexia.recording ? root.urgent : (omalexia.speaking ? Color.accent : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: omalexia.installed
                  checked: omalexia.daemonActive
                  busy: omalexia.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: omalexia.toggleDaemon()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: omalexia.daemonActive ? "Turn read-aloud off (frees ~150 MB)" : "Turn read-aloud on"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: omalexia.actionStatus !== "" || omalexia.lastError !== ""
            width: parent.width
            text: omalexia.actionStatus !== "" ? omalexia.actionStatus : omalexia.lastError
            color: omalexia.lastError !== "" && omalexia.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---- not installed ------------------------------------------------

          ActionRow {
            visible: omalexia.statusKnown && !omalexia.installed
            rowKey: "install"
            buttons: [{ icon: "󰉉", text: "How to install", tip: "Omalexia's commands are missing from ~/.local/bin" }]
            onTriggered: function(index) { omalexia.act("install") }
          }

          // ---- read aloud ---------------------------------------------------

          PanelSeparator { visible: omalexia.installed; foreground: root.foreground }

          Column {
            visible: omalexia.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "READ ALOUD"; foreground: root.foreground; fontFamily: root.fontFamily }

            ActionRow {
              rowKey: "read.actions"
              buttons: [
                { icon: "󰗊", text: "Selection", tip: "Read the highlighted text (F10)" },
                { icon: "", text: "Clipboard", tip: "Read the clipboard (Shift+F10)" },
                { icon: "󰴑", text: "Screen", tip: "Draw a box and read what is in it (Ctrl+F10)" },
                { icon: "󰝛", text: "Stop", tip: "Stop reading", enabled: omalexia.speaking }
              ]
              onTriggered: function(index) {
                if (index === 0) omalexia.readSelection()
                else if (index === 1) omalexia.readClipboard()
                else if (index === 2) { root.close(); omalexia.readScreen() }
                else omalexia.stopReading()
              }
            }

            SliderRow {
              rowKey: "read.speed"
              label: "Speed"
              valueText: Number(root.read.speed || 1).toFixed(1) + "×"
              value: Number(root.read.speed || 1)
              minimum: 0.5
              maximum: 4.0
              step: 0.1
              onCommitted: function(v) { omalexia.set("speed", v.toFixed(1)) }
            }

            DropdownRow {
              id: voiceEnDropdown
              rowKey: "read.voiceEn"
              label: "English voice"
              options: root.voiceEnOptions
              current: root.voiceEnValue
              onChosen: function(v) { root.chooseEnglishVoice(v) }
            }

            DropdownRow {
              id: voiceNlDropdown
              rowKey: "read.voiceNl"
              label: "Dutch voice"
              options: root.read.voicesNl || []
              current: String(root.read.voiceNl || "")
              onChosen: function(v) { omalexia.set("voiceNl", v) }
            }

            DropdownRow {
              id: languageDropdown
              rowKey: "read.language"
              label: "Language"
              options: root.languageOptions
              current: String(root.read.language || "auto")
              onChosen: function(v) { omalexia.set("language", v) }
            }

            ActionRow {
              rowKey: "read.test"
              compact: true
              buttons: [{ icon: "󰙃", text: root.read.language === "nl" ? "Test de stem" : "Test the voice", tip: "Say a sentence with the current voice" }]
              onTriggered: function(index) { omalexia.testVoice(root.read.language === "nl" ? "nl" : "en") }
            }
          }

          // ---- dictation ----------------------------------------------------

          PanelSeparator { visible: omalexia.installed && root.showDictation; foreground: root.foreground }

          Column {
            visible: omalexia.installed && root.showDictation
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "DICTATION"; foreground: root.foreground; fontFamily: root.fontFamily }

            Text {
              visible: root.dictationInstalled
              width: parent.width
              text: {
                var state = omalexia.recording ? "Listening" : (omalexia.transcribing ? "Typing" : "Idle")
                var model = String(root.dictation.modelLabel || "")
                return state + (model ? " · " + model : "") + (root.dictation.serviceActive === false ? " · voxtype not running" : "")
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            ActionRow {
              visible: !root.dictationInstalled
              rowKey: "dict.install"
              buttons: [{ icon: "󰉉", text: "Install voxtype", tip: "Omarchy's dictation engine" }]
              onTriggered: function(index) { omalexia.act("dictation-install") }
            }

            ActionRow {
              visible: root.dictationInstalled
              rowKey: "dict.actions"
              buttons: [
                { icon: omalexia.recording ? "󰓛" : "󰑊", text: omalexia.recording ? "Stop" : "Dictate", tip: "Start or stop dictation (Super+Ctrl+X, or hold F9)" },
                { icon: "󰜺", text: "Cancel", tip: "Discard the current recording (Shift+F9)", enabled: omalexia.recording || omalexia.transcribing },
                { icon: "󰬴", text: "Word list", tip: "Personal replacements: spoken = written" },
                { icon: "󰜉", text: "Restart", tip: "Restart voxtype" }
              ]
              onTriggered: function(index) {
                if (index === 0) omalexia.toggleDictation()
                else if (index === 1) omalexia.cancelDictation()
                else if (index === 2) omalexia.act("word-list")
                else omalexia.act("dictation-restart")
              }
            }

            DropdownRow {
              id: engineDropdown
              visible: root.dictationInstalled
              rowKey: "dict.engine"
              label: "Engine"
              options: root.engineOptions
              current: String(root.dictation.engine || "")
              onChosen: function(v) { omalexia.set("dictationEngine", v) }
            }

            Text {
              visible: root.dictationInstalled && root.dictation.parakeetNeedsSudo === true
              width: parent.width
              text: "Parakeet (Dutch + English) needs one sudo step: rerun install.sh in a terminal."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            ToggleRow {
              visible: root.dictationInstalled
              rowKey: "dict.feedback"
              label: "Sound when recording starts and stops"
              description: "A short tick you can hear without looking."
              checked: root.dictation.feedback === true
              onFlipped: function(next) { omalexia.set("feedback", next ? "true" : "false") }
            }

            ToggleRow {
              visible: root.dictationInstalled
              rowKey: "dict.showTyped"
              label: "Show what was typed"
              description: "A notification with the transcribed text."
              checked: root.dictation.showTyped === true
              onFlipped: function(next) { omalexia.set("showTyped", next ? "true" : "false") }
            }
          }

          // ---- look ---------------------------------------------------------

          PanelSeparator { visible: omalexia.installed && root.showLook; foreground: root.foreground }

          Column {
            visible: omalexia.installed && root.showLook
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "LOOK"; foreground: root.foreground; fontFamily: root.fontFamily }

            ActionRow {
              rowKey: "look.actions"
              buttons: [
                { icon: "󰖲", text: root.look.readingMode === true ? "Tile window" : "Reading mode", tip: "Float the focused window at a readable width (Super+R)" },
                { icon: "󰸌", text: "Cream theme", tip: "Flexoki Light: dark text on cream, as the BDA advises", enabled: String(root.look.theme || "") !== "flexoki-light" }
              ]
              onTriggered: function(index) {
                if (index === 0) { root.close(); omalexia.toggleReadingMode() }
                else omalexia.act("theme", "flexoki-light")
              }
            }

            ToggleRow {
              rowKey: "look.narrow"
              label: "Narrow single window"
              description: "A lone window stays square-ish on a wide monitor (Super+Ctrl+Backspace)."
              checked: root.look.narrowSingleWindow === true
              onFlipped: function(next) { omalexia.set("narrowSingleWindow", next ? "true" : "false") }
            }

            ToggleRow {
              rowKey: "look.tint"
              label: "Paper tint"
              description: "Warm the whole screen like cream paper (Super+Shift+R)."
              checked: root.look.tint === true
              onFlipped: function(next) { omalexia.set("tint", next ? "true" : "false") }
            }

            ToggleRow {
              rowKey: "look.motion"
              label: "Reduced motion"
              description: "No window animations."
              checked: root.look.reducedMotion === true
              onFlipped: function(next) { omalexia.set("reducedMotion", next ? "true" : "false") }
            }

            DropdownRow {
              id: fontDropdown
              rowKey: "look.font"
              label: "Reading font"
              options: root.look.fonts || []
              current: String(root.look.font || "default")
              onChosen: function(v) { omalexia.set("font", v) }
            }

            DropdownRow {
              id: sizeDropdown
              rowKey: "look.size"
              label: "Text size"
              options: root.sizeOptions
              current: String(root.look.textSize || 12)
              onChosen: function(v) { omalexia.set("textSize", v) }
            }
          }

          // ---- footer -------------------------------------------------------

          PanelSeparator { visible: omalexia.installed; foreground: root.foreground }

          ActionRow {
            visible: omalexia.installed
            rowKey: "footer"
            compact: true
            buttons: [
              { icon: "", text: "Keys", tip: "The cheat sheet" },
              { icon: "󰗊", text: "Menu", tip: "Omalexia in the Omarchy menu (Super+Alt+A)" },
              { icon: "󰑐", text: "Refresh", tip: "Re-read the settings" }
            ]
            onTriggered: function(index) {
              if (index === 0) omalexia.openKeys()
              else if (index === 1) { root.close(); omalexia.openMenu() }
              else omalexia.refresh()
            }
          }
        }
      }
    }
  }

  // ---- row components ---------------------------------------------------------

  // A row of buttons. The keyboard cursor walks the buttons with h/l.
  component ActionRow: Item {
    id: actionRow
    property string rowKey: ""
    property var buttons: []
    property bool compact: false
    signal triggered(int index)

    width: parent ? parent.width : implicitWidth
    implicitHeight: flow.implicitHeight
    Component.onCompleted: root.registerRow(rowKey, actionRow)

    Flow {
      id: flow
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: actionRow.buttons
        Button {
          required property var modelData
          required property int index
          text: String(modelData.text || "")
          iconText: String(modelData.icon || "")
          tooltipText: String(modelData.tip || "")
          enabled: modelData.enabled === undefined ? true : modelData.enabled === true
          opacity: enabled ? 1.0 : 0.45
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: actionRow.compact ? Style.font.bodySmall : Style.font.body
          hasCursor: root.actionHasCursor(actionRow.rowKey, index)
          onHovered: function(on) { if (on) root.setCursor(actionRow.rowKey, index) }
          onClicked: if (enabled) actionRow.triggered(index)
        }
      }
    }
  }

  // Label + live value + slider.
  component SliderRow: CursorSurface {
    id: sliderRow
    property string rowKey: ""
    property string label: ""
    property string valueText: ""
    property real value: 1
    property real minimum: 0
    property real maximum: 1
    property real step: 0.1
    signal committed(real value)

    width: parent ? parent.width : implicitWidth
    implicitHeight: sliderInner.implicitHeight + Style.spacing.rowPaddingX
    hasCursor: root.hasCursor(rowKey)
    foreground: root.foreground
    Component.onCompleted: root.registerRow(rowKey, sliderRow)

    HoverHandler { onHoveredChanged: if (hovered) root.setCursor(sliderRow.rowKey) }

    Column {
      id: sliderInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(4)

      Row {
        width: parent.width
        Text {
          text: sliderRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          width: parent.width - valueLabel.implicitWidth
          elide: Text.ElideRight
        }
        Text {
          id: valueLabel
          text: sliderRow.valueText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      PanelSlider {
        width: parent.width
        bar: root.bar
        value: sliderRow.value
        minimum: sliderRow.minimum
        maximum: sliderRow.maximum
        step: sliderRow.step
        tickCount: 4
        onReleased: function(v) { sliderRow.committed(v) }
      }
    }
  }

  // Label + themed dropdown. `current` is re-applied by a Binding so a
  // background refresh wins over whatever the popup last selected.
  component DropdownRow: Item {
    id: dropdownRow
    property string rowKey: ""
    property string label: ""
    property var options: []
    property string current: ""
    signal chosen(string value)

    function toggle() { dropdown.toggle() }

    width: parent ? parent.width : implicitWidth
    implicitHeight: dropdown.implicitHeight
    Component.onCompleted: root.registerRow(rowKey, dropdownRow)

    HoverHandler { onHoveredChanged: if (hovered) root.setCursor(dropdownRow.rowKey) }

    Dropdown {
      id: dropdown
      width: parent.width
      label: dropdownRow.label
      options: dropdownRow.options
      foreground: root.foreground
      fontFamily: root.fontFamily
      hasCursor: root.hasCursor(dropdownRow.rowKey)
      onHovered: function(on) { if (on) root.setCursor(dropdownRow.rowKey) }
      onPopupOpenChanged: root.dropdownOpen = popupOpen
      onChanged: function(v) { if (v !== dropdownRow.current) dropdownRow.chosen(v) }
    }

    Binding {
      target: dropdown
      property: "value"
      value: dropdownRow.current
    }
  }

  // Labeled on/off row.
  component ToggleRow: Toggle {
    id: toggleRow
    property string rowKey: ""
    signal flipped(bool next)

    width: parent ? parent.width : implicitWidth
    foreground: root.foreground
    fontFamily: root.fontFamily
    hasCursor: root.hasCursor(rowKey)
    Component.onCompleted: root.registerRow(rowKey, toggleRow)
    onHovered: function(on) { if (on) root.setCursor(toggleRow.rowKey) }
    onClicked: toggleRow.flipped(!toggleRow.checked)
  }
}
