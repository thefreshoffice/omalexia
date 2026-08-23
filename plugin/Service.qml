import QtQuick
import Quickshell
import Quickshell.Io

// State for the Omalexia bar widget and panel. Two long-lived streams keep
// the icon honest the instant something changes (read-aloud state from
// `omalexia-say follow`, dictation state from Omarchy's own voxtype status
// follower); everything else is a periodic snapshot from status.py.
Item {
  id: root
  property var settings: ({})

  // Snapshot (status.py)
  property bool statusKnown: false
  property bool installed: false
  property var read: ({})
  property var dictation: ({})
  property var look: ({})
  property string lastError: ""
  property string actionStatus: ""

  // Live streams
  property string speakState: "idle"      // idle | speaking | down
  property string dictState: "idle"       // idle | recording | transcribing

  readonly property string home: Quickshell.env("HOME")
  readonly property string helperPath: filePath(Qt.resolvedUrl("status.py"))
  readonly property string sayPath: home + "/.local/bin/omalexia-say"
  readonly property bool busy: statusProcess.running || opProcess.running
  readonly property bool speaking: speakState === "speaking"
  readonly property bool recording: dictState === "recording"
  readonly property bool transcribing: dictState === "transcribing"
  readonly property bool daemonActive: read.daemonActive === true && speakState !== "down"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 5, 600)
  readonly property bool showDictation: setting("showDictation", true) === true
  readonly property bool showLook: setting("showLook", true) === true

  readonly property string statusText: {
    if (!installed) return "Omalexia is not installed"
    if (recording) return "Listening…"
    if (transcribing) return "Typing what you said…"
    if (speaking) return read.text ? "Reading: " + String(read.text) : "Reading aloud"
    if (!daemonActive) return "Read-aloud is off"
    return "Ready — F10 reads, F9 talks"
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function filePath(url) {
    return decodeURIComponent(String(url || "").replace(/^file:\/\//, ""))
  }

  function applySnapshot(raw) {
    var text = String(raw || "").trim()
    if (text === "") return
    var parsed
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      lastError = "Could not read Omalexia status"
      return
    }
    if (!parsed || parsed.ok !== true) return
    if (parsed.read === undefined) return   // fire-and-forget reply
    statusKnown = true
    installed = parsed.installed === true
    read = parsed.read || ({})
    dictation = parsed.dictation || ({})
    look = parsed.look || ({})
    lastError = ""
    if (read.state === "speaking" || read.state === "idle") speakState = String(read.state)
    if (dictation.state) dictState = String(dictation.state)
  }

  function refresh() {
    if (statusProcess.running || helperPath === "") return
    statusProcess.command = ["/usr/bin/python3", helperPath]
    statusProcess.running = true
  }

  // Change one setting. Serialised through a single process so two quick
  // clicks cannot race on the same config file.
  property var pendingOps: []

  function set(key, value) {
    enqueue(["/usr/bin/python3", helperPath, "set", String(key), String(value)], "Applying…")
  }

  function act(action, arg) {
    var cmd = ["/usr/bin/python3", helperPath, "do", String(action)]
    if (arg !== undefined && arg !== null && String(arg) !== "") cmd.push(String(arg))
    enqueue(cmd, "")
  }

  function enqueue(cmd, status) {
    if (helperPath === "") return
    pendingOps = pendingOps.concat([{ cmd: cmd, status: status }])
    pumpOps()
  }

  function pumpOps() {
    if (opProcess.running || pendingOps.length === 0) return
    var next = pendingOps[0]
    pendingOps = pendingOps.slice(1)
    actionStatus = next.status
    opProcess.command = next.cmd
    opProcess.running = true
  }

  function readSelection() { act("selection") }
  function readClipboard() { act("clipboard") }
  function readScreen() { act("ocr") }
  function stopReading() { act("stop") }
  function toggleReading() { act("toggle") }
  function testVoice(lang) { act("test", lang) }
  function toggleDictation() { act("dictate") }
  function cancelDictation() { act("dictate-cancel") }
  function toggleReadingMode() { act("reading-mode") }
  function openKeys() { act("keys") }
  function openMenu() { act("menu") }
  function toggleDaemon() { set("daemon", daemonActive ? "false" : "true") }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer { id: delayedRefresh; interval: 900; repeat: false; onTriggered: root.refresh() }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applySnapshot(statusOut.text)
      else root.lastError = String(statusErr.text || statusOut.text || "Could not read Omalexia status").trim()
    }
  }

  Process {
    id: opProcess
    running: false
    command: []
    stdout: StdioCollector { id: opOut; waitForEnd: true }
    stderr: StdioCollector { id: opErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.actionStatus = ""
      if (exitCode === 0) root.applySnapshot(opOut.text)
      else root.lastError = String(opErr.text || opOut.text || "Omalexia command failed").trim()
      root.pumpOps()
      if (root.pendingOps.length === 0) delayedRefresh.restart()
    }
  }

  // Read-aloud state, streamed. `omalexia-say follow` prints one JSON line
  // per change; if it is missing the process exits and we retry later.
  Process {
    id: speakFollow
    command: ["bash", "-c", "exec \"$0\" follow", root.sayPath]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var data = JSON.parse(String(line))
          if (data && data.state) root.speakState = String(data.state)
        } catch (e) {}
      }
    }
    onExited: followRetry.restart()
  }

  Timer { id: followRetry; interval: 15000; repeat: false; onTriggered: speakFollow.running = true }

  // Dictation state, streamed from Omarchy's own voxtype follower (JSON
  // rows with alt/class = idle | recording | transcribing).
  Process {
    id: dictFollow
    command: ["bash", "-c", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var data = JSON.parse(String(line))
          var state = String((data && (data.alt || data["class"])) || "idle")
          if (state === "") state = "idle"
          root.dictState = state
        } catch (e) {}
      }
    }
    onExited: dictRetry.restart()
  }

  Timer { id: dictRetry; interval: 30000; repeat: false; onTriggered: dictFollow.running = true }
}
