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
    return "Ready. F10 reads, F9 talks"
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
    applyOptimistic(String(key), String(value))
    enqueue(["/usr/bin/python3", helperPath, "set", String(key), String(value)], "Applying…")
  }

  // Reflect a change in the local snapshot immediately so controls settle
  // where the user put them instead of bouncing back to the stale value
  // until status.py answers. The next snapshot confirms (or corrects).
  function applyOptimistic(key, value) {
    function clone(o) { return JSON.parse(JSON.stringify(o || ({}))) }
    var truthy = value === "true"
    if (key === "speed" || key === "language" || key === "daemon" || key === "highlight"
        || key === "highlightDelay"
        || key.indexOf("voice:") === 0 || key.indexOf("engine:") === 0) {
      var r = clone(read)
      if (key === "speed") r.speed = Number(value)
      else if (key === "language") r.language = value
      else if (key === "daemon") r.daemonActive = truthy
      else if (key === "highlight") r.highlightMode = value
      else if (key === "highlightDelay") r.highlightDelay = Number(value)
      else {
        var isEngine = key.indexOf("engine:") === 0
        var code = key.substring(isEngine ? 7 : 6)
        var langs = r.languages || []
        for (var i = 0; i < langs.length; i++) {
          if (langs[i].code !== code) continue
          if (isEngine) langs[i].engine = value
          else { langs[i].voice = value; langs[i].engine = "piper" }
        }
      }
      read = r
    } else if (key === "dictationEngine" || key === "feedback" || key === "showTyped") {
      var d = clone(dictation)
      if (key === "dictationEngine") d.engine = value
      else if (key === "feedback") d.feedback = truthy
      else d.showTyped = truthy
      dictation = d
    } else if (key === "narrowSingleWindow" || key === "tint" || key === "reducedMotion"
               || key === "font" || key === "textSize") {
      var l = clone(look)
      if (key === "narrowSingleWindow") l.narrowSingleWindow = truthy
      else if (key === "tint") l.tint = truthy
      else if (key === "reducedMotion") l.reducedMotion = truthy
      else if (key === "font") l.font = value
      else l.textSize = Number(value)
      look = l
    }
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

  property string pendingStatusText: ""

  function pumpOps() {
    if (opProcess.running || pendingOps.length === 0) return
    var next = pendingOps[0]
    pendingOps = pendingOps.slice(1)
    // Show the status only if the operation turns out to be slow; a fast
    // one finishes silently instead of flashing text at the user.
    pendingStatusText = next.status
    slowOpTimer.restart()
    opProcess.command = next.cmd
    opProcess.running = true
  }

  Timer {
    id: slowOpTimer
    interval: 350
    repeat: false
    onTriggered: if (opProcess.running) root.actionStatus = root.pendingStatusText
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

  // ---- read-along highlight ------------------------------------------
  // While highlighting is on and the daemon runs, a long-lived watch
  // connection streams sentence and word events timed to the audio;
  // Highlight.qml renders them. Dropping the connection is also the
  // daemon's cue to skip the word-timing work entirely.
  //
  // For mode "text" the daemon also runs omalexia-locate (OCR of the
  // focused window) once per utterance and broadcasts a "boxes" event
  // mapping the word events' char offsets to on-screen positions, so the
  // marker lands on the actual text being read.

  readonly property string highlightMode: {
    var mode = read.highlightMode
    return mode === "bar" || mode === "off" ? String(mode) : "text"
  }
  readonly property bool highlightEnabled: highlightMode !== "off"
  property int highlightUtterance: -1
  property string highlightSentence: ""
  property int highlightSentenceStart: -1
  property int highlightSentenceEnd: -1
  property int highlightWordStart: -1
  property int highlightWordEnd: -1
  property var highlightBoxes: ({})
  property var highlightBox: null
  property var highlightSentenceRects: []

  function clearHighlight() {
    highlightSentence = ""
    highlightSentenceStart = -1
    highlightSentenceEnd = -1
    highlightWordStart = -1
    highlightWordEnd = -1
    highlightBox = null
    highlightSentenceRects = []
  }

  // A faint wash over the whole sentence being read (one rectangle per
  // text line), the steady backdrop the word pill moves across. It gives
  // the eye an anchor the moment a sentence starts, before its first word
  // event, and hides the odd word the matcher could not place.
  function computeSentenceRects() {
    var rects = []
    if (highlightSentenceStart >= 0) {
      var boxes = []
      for (var k in highlightBoxes) {
        var b = highlightBoxes[k]
        if (b.start >= highlightSentenceStart && b.start < highlightSentenceEnd) boxes.push(b)
      }
      boxes.sort(function(p, q) { return p.y - q.y || p.x - q.x })
      var line = null
      for (var i = 0; i < boxes.length; i++) {
        var box = boxes[i]
        if (line && Math.abs(box.y - line.y) < line.h * 0.6) {
          line.x1 = Math.max(line.x1, box.x + box.w)
          line.x0 = Math.min(line.x0, box.x)
          line.h = Math.max(line.h, box.h)
        } else {
          if (line) rects.push(line)
          line = { x0: box.x, x1: box.x + box.w, y: box.y, h: box.h }
        }
      }
      if (line) rects.push(line)
    }
    highlightSentenceRects = rects
  }

  function handleSpeakEvent(line) {
    var ev
    try { ev = JSON.parse(line) } catch (e) { return }
    if (!ev || !ev.event) return
    if (ev.event === "start") {
      highlightUtterance = Number(ev.id)
      highlightBoxes = {}
      clearHighlight()
    } else if (ev.event === "boxes") {
      // Ignore boxes for an utterance we are not on (unless we joined the
      // stream mid-utterance and never saw its start).
      if (highlightUtterance >= 0 && Number(ev.id) !== highlightUtterance) return
      var map = {}
      var list = ev.boxes || []
      for (var i = 0; i < list.length; i++) map[String(list[i].start)] = list[i]
      highlightBoxes = map
      // Reading may already be under way when boxes (re)arrive; place the
      // marker on the current word, and clear it only when tracking is
      // genuinely gone (an empty update).
      if (list.length === 0) {
        highlightBox = null
      } else if (highlightWordStart >= 0) {
        var cur = map[String(highlightWordStart)]
        if (cur !== undefined) highlightBox = cur
      }
      computeSentenceRects()
    } else if (ev.event === "sentence") {
      highlightSentence = String(ev.text || "")
      highlightSentenceStart = ev.start === undefined ? -1 : Number(ev.start)
      highlightSentenceEnd = ev.end === undefined ? -1 : Number(ev.end)
      highlightWordStart = -1
      highlightWordEnd = -1
      // The marker stays where it is until the next word has a box; a
      // blink at every sentence boundary reads as instability.
      computeSentenceRects()
    } else if (ev.event === "word") {
      highlightWordStart = Number(ev.start)
      highlightWordEnd = Number(ev.end)
      var b = highlightBoxes[String(ev.start)]
      if (b !== undefined) highlightBox = b
    } else if (ev.event === "end") {
      highlightBoxes = {}
      clearHighlight()
    }
  }

  // State dump for `quickshell ipc` while chasing sync or overlay issues.
  function highlightDebug() {
    var boxCount = 0
    for (var k in highlightBoxes) boxCount++
    return {
      mode: highlightMode,
      enabled: highlightEnabled,
      daemonActive: daemonActive,
      watchConnected: speakWatch.connected,
      utterance: highlightUtterance,
      boxes: boxCount,
      wordStart: highlightWordStart,
      sentence: highlightSentence.substring(0, 48),
      box: highlightBox ? JSON.stringify(highlightBox) : null
    }
  }

  function syncWatch() {
    var want = highlightEnabled && daemonActive
    if (want === speakWatch.connected) return
    if (want) console.log("omalexia: reconnecting speakd watch")
    speakWatch.connected = want
  }

  onHighlightEnabledChanged: syncWatch()
  onDaemonActiveChanged: syncWatch()
  onHighlightModeChanged: {
    // The boxes flag is stated when connecting; a mode switch reconnects.
    if (speakWatch.connected) { speakWatch.connected = false; syncWatch() }
  }

  Socket {
    id: speakWatch
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/omalexia/speakd.sock"
    parser: SplitParser {
      onRead: function(line) { root.handleSpeakEvent(String(line)) }
    }
    onError: function(err) { console.warn("omalexia speakWatch error:", err) }
    onConnectionStateChanged: {
      if (connected) {
        // Bar mode still needs the word timing but no on-screen boxes;
        // saying so lets the daemon skip the locate work entirely.
        write("{\"cmd\": \"watch\", \"boxes\": " + (root.highlightMode === "text") + "}\n")
        flush()
      } else {
        root.clearHighlight()
      }
    }
  }

  Timer {
    // Heartbeat, deliberately not gated on speakWatch.connected: a socket
    // whose peer went away can flip that property without a change signal,
    // which would leave a condition-gated timer disarmed forever. Checking
    // is idempotent and costs nothing.
    interval: 4000
    repeat: true
    running: root.highlightEnabled && root.daemonActive
    onTriggered: root.syncWatch()
  }

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
      slowOpTimer.stop()
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
