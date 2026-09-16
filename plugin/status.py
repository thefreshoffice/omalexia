#!/usr/bin/python3
"""Status and actions for the Omalexia bar plugin.

One JSON snapshot in, one JSON reply out. The QML side never parses config
files or shells out on its own; everything funnels through here so the panel
stays a thin view over the same commands the keys and the menu use.

  status.py                    -> full snapshot
  status.py set <key> <value>  -> change one thing, then print the snapshot
  status.py do <action> [arg]  -> run an action (read, stop, dictate, …)
"""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tomllib
from pathlib import Path

HOME = Path.home()
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local" / "state")
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local" / "share")
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
BIN = HOME / ".local" / "bin"

OMALEXIA_CONFIG = CONFIG_HOME / "omalexia" / "config.toml"
OMALEXIA_STATE = STATE_HOME / "omalexia"
VOICES_DIR = DATA_HOME / "omalexia" / "voices"
KOKORO_DIR = DATA_HOME / "omalexia" / "kokoro"
SPEAK_SOCK = RUNTIME / "omalexia" / "speakd.sock"
SPEAK_STATE = RUNTIME / "omalexia" / "state"
VOXTYPE_CONFIG = CONFIG_HOME / "voxtype" / "config.toml"
VOXTYPE_MODELS = DATA_HOME / "voxtype" / "models"
VOXTYPE_STATE = RUNTIME / "voxtype" / "state"
SQUARE_TOGGLE = STATE_HOME / "omarchy" / "toggles" / "hypr" / "single-window-aspect-ratio.lua"

LANG_NAMES = {
    "en": "English", "nl": "Nederlands", "de": "Deutsch", "fr": "Français",
    "es": "Español", "it": "Italiano", "pt": "Português", "da": "Dansk",
    "sv": "Svenska", "no": "Norsk", "fi": "Suomi", "pl": "Polski",
    "cs": "Čeština", "ro": "Română", "hu": "Magyar", "tr": "Türkçe",
    "ru": "Русский", "uk": "Українська", "el": "Ελληνικά", "ar": "العربية",
    "zh": "中文", "ja": "日本語", "ko": "한국어", "hi": "हिन्दी", "vi": "Tiếng Việt",
}

VOICES = {
    "en": [
        ("en_US-lessac-medium", "Lessac (US)"),
        ("en_GB-alan-medium", "Alan (UK)"),
        ("en_GB-jenny_dioco-medium", "Jenny (UK)"),
        ("en_US-hfc_female-medium", "HFC (US)"),
        ("en_US-lessac-high", "Lessac, richer (slower)"),
        ("en_GB-cori-high", "Cori (UK), richer (slower)"),
    ],
    "nl": [
        ("nl_NL-pim-medium", "Pim"),
        ("nl_NL-ronnie-medium", "Ronnie"),
        ("nl_NL-alex-medium", "Alex"),
        ("nl_BE-nathalie-medium", "Nathalie (Vlaams)"),
        ("nl_BE-rdh-medium", "RDH (Vlaams)"),
    ],
}
FONTS = [
    ("atkinson", "Atkinson Hyperlegible"),
    ("opendyslexic", "OpenDyslexic"),
    ("inter", "Inter"),
    ("default", "Omarchy default"),
]
FONT_FAMILIES = {
    "atkinson": "atkinson hyperlegible",
    "opendyslexic": "opendyslexic",
    "inter": "inter",
}


def installed_font_families() -> set:
    r = run(["fc-list", ":", "family"], timeout=5)
    families = set()
    for line in (r.stdout.splitlines() if r else []):
        for name in line.split(","):
            families.add(name.strip().lower())
    return families


def run(cmd, timeout=6, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False, **kw)
    except (OSError, subprocess.TimeoutExpired):
        return None


def detached(cmd):
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def tool(name: str) -> str:
    local = BIN / name
    return str(local) if local.exists() else (shutil.which(name) or name)


def read_text(path: Path, default: str = "") -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return default


def unit_active(unit: str) -> bool:
    r = run(["systemctl", "--user", "is-active", unit], timeout=3)
    return bool(r and r.stdout.strip() == "active")


# --------------------------------------------------------------------------
# Read aloud
# --------------------------------------------------------------------------


def speakd_request(obj: dict) -> dict:
    if not SPEAK_SOCK.exists():
        return {}
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(str(SPEAK_SOCK))
        s.sendall((json.dumps(obj) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        s.close()
        return json.loads(data.decode() or "{}")
    except (OSError, ValueError):
        return {}


def omalexia_config() -> dict:
    cfg = {"speed": 1.0, "default_language": "auto", "voices": {"en": "en_US-lessac-medium", "nl": "nl_NL-pim-medium"},
           "engines": {}, "kokoro": {"voice": "af_heart"}}
    try:
        tts = tomllib.loads(OMALEXIA_CONFIG.read_text()).get("tts", {})
    except (OSError, ValueError):
        tts = {}
    for k in ("speed", "default_language"):
        if k in tts:
            cfg[k] = tts[k]
    for k in ("voices", "engines", "kokoro"):
        if isinstance(tts.get(k), dict):
            cfg[k].update(tts[k])
    return cfg


def installed_voices() -> list[str]:
    try:
        return sorted(p.stem for p in VOICES_DIR.glob("*.onnx"))
    except OSError:
        return []


def pretty_voice(name: str) -> str:
    """en_GB-alba-medium -> "Alba (GB, medium)"; falls back to the raw name."""
    try:
        code, speaker, quality = name.split("-", 2)
        region = code.split("_", 1)[1]
        label = speaker.replace("_", " ").title()
        return f"{label} ({region}, {quality.replace('_', ' ')})"
    except ValueError:
        return name


def voice_options(lang: str, current: str, have: list[str]) -> list[dict]:
    options = []
    seen = set()
    for name, label in VOICES.get(lang, []):
        suffix = "" if name in have else " · download"
        options.append({"value": name, "label": label + suffix, "installed": name in have})
        seen.add(name)
    for name in have:
        if name.startswith(lang + "_") and name not in seen:
            options.append({"value": name, "label": pretty_voice(name), "installed": True})
            seen.add(name)
    if current and current not in seen:
        options.append({"value": current, "label": pretty_voice(current), "installed": current in have})
    return options


def highlight_mode() -> str:
    """"text" marks the spoken word where it stands on screen, "bar" shows
    the sentence in a card at the bottom, "off" disables both."""
    mode = read_text(OMALEXIA_STATE / "highlight")
    return mode if mode in ("text", "bar", "off") else "text"


def highlight_style() -> str:
    """Within "text" mode: mark the spoken "word" (the standard), the whole
    "sentence", or "both" (sentence wash with the word pill on top)."""
    style = read_text(OMALEXIA_STATE / "highlight-style")
    return style if style in ("word", "sentence", "both") else "word"


def read_aloud_status() -> dict:
    cfg = omalexia_config()
    live = speakd_request({"cmd": "status"})
    have = installed_voices()
    speed_state = read_text(OMALEXIA_STATE / "speed")
    speed = float(live.get("speed") or speed_state or cfg["speed"] or 1.0)
    state = str(live.get("state") or read_text(SPEAK_STATE, "idle") or "idle")
    kokoro = (KOKORO_DIR / ".venv" / "bin" / "python").exists()
    return {
        "daemonActive": unit_active("omalexia-speakd.service") or bool(live),
        "daemonReachable": bool(live),
        "state": state,
        "text": str(live.get("text") or ""),
        "speed": round(speed, 2),
        "language": str(cfg["default_language"]),
        "languageOptions": [{"value": "auto", "label": "Detect from the text"}]
        + [{"value": code, "label": LANG_NAMES.get(code, code)} for code in cfg["voices"]],
        "languages": [
            {
                "code": code,
                "name": LANG_NAMES.get(code, code),
                "voice": str(voice),
                "engine": str(cfg["engines"].get(code, "piper")),
                "kokoroCapable": code in ("en", "es", "fr", "hi", "it", "ja", "pt", "zh"),
                "options": voice_options(code, str(voice), have),
            }
            for code, voice in cfg["voices"].items()
        ],
        "kokoroInstalled": kokoro,
        "highlightMode": highlight_mode(),
        "highlightStyle": highlight_style(),
        "highlightDelay": round(float(live.get("highlightDelay")
                                      or read_text(OMALEXIA_STATE / "highlight-delay")
                                      or 0.15), 2),
        "piperAvailable": (piper_probe := run(["/usr/bin/python3", "-c", "import piper"], timeout=8)) is not None
        and piper_probe.returncode == 0,
    }


# --------------------------------------------------------------------------
# Dictation (voxtype)
# --------------------------------------------------------------------------


def voxtype_config_text() -> str:
    return read_text(VOXTYPE_CONFIG)


def voxtype_config() -> dict:
    try:
        return tomllib.loads(voxtype_config_text())
    except (OSError, ValueError):
        return {}


def toml_set(text: str, section: str, key: str, value: str) -> str:
    """Set key = value inside [section] (section may be dotted), preserving
    everything else. Appends the section if it is missing."""
    lines = text.split("\n")
    header = f"[{section}]"
    in_section = False
    section_start = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and not stripped.startswith("[["):
            in_section = stripped == header
            if in_section:
                section_start = i
            continue
        if in_section and re.match(rf"^\s*{re.escape(key)}\s*=", line):
            lines[i] = f"{key} = {value}"
            return "\n".join(lines)
    if section_start is not None:
        insert = section_start + 1
        lines.insert(insert, f"{key} = {value}")
        return "\n".join(lines)
    return text.rstrip("\n") + f"\n\n{header}\n{key} = {value}\n"


def onnx_active() -> bool:
    r = run(["voxtype", "setup", "onnx", "--status"], timeout=8)
    return bool(r and "Active engine: ONNX" in r.stdout)


def dictation_status() -> dict:
    installed = shutil.which("voxtype") is not None
    if not installed:
        return {"installed": False}
    cfg = voxtype_config()
    engine = str(cfg.get("engine", "whisper"))
    parakeet_model = str(cfg.get("parakeet", {}).get("model", "parakeet-tdt-0.6b-v3-int8"))
    whisper_model = str(cfg.get("whisper", {}).get("model", "base.en"))
    parakeet_present = (VOXTYPE_MODELS / parakeet_model).is_dir()
    whisper_present = any(VOXTYPE_MODELS.glob("ggml-*.bin")) if VOXTYPE_MODELS.exists() else False
    onnx = onnx_active()
    if engine == "parakeet":
        model_label = "Parakeet TDT v3 · Dutch + English"
    else:
        model_label = f"Whisper {whisper_model}"
    return {
        "installed": True,
        "serviceActive": unit_active("voxtype.service"),
        "state": read_text(VOXTYPE_STATE, "idle") or "idle",
        "engine": engine,
        "modelLabel": model_label,
        "parakeetAvailable": parakeet_present and onnx,
        "parakeetNeedsSudo": not onnx,
        "whisperAvailable": whisper_present,
        "feedback": bool(cfg.get("audio", {}).get("feedback", {}).get("enabled", False)),
        "showTyped": bool(cfg.get("output", {}).get("notification", {}).get("on_transcription", False)),
        "cleanup": bool(cfg.get("output", {}).get("post_process", {}).get("command")),
    }


# --------------------------------------------------------------------------
# Look
# --------------------------------------------------------------------------


def text_size() -> int:
    r = run(["omarchy-display-text-size"], timeout=5)
    m = re.search(r"(\d+)", r.stdout if r else "")
    return int(m.group(1)) if m else 12


def look_status() -> dict:
    font_choice = read_text(OMALEXIA_STATE / "font-choice") or "default"
    families = installed_font_families()
    absent = [v for v, fam in FONT_FAMILIES.items() if fam not in families]
    return {
        "font": font_choice,
        "fontLabel": dict(FONTS).get(font_choice, font_choice),
        "fonts": [{"value": v,
                   "label": l + (" (not installed)" if v in absent else "")}
                  for v, l in FONTS],
        "fontsMissing": bool(absent),
        "textSize": text_size(),
        "tint": (OMALEXIA_STATE / "tint").exists(),
        "reducedMotion": (OMALEXIA_STATE / "reduced-motion").exists(),
        "narrowSingleWindow": SQUARE_TOGGLE.exists(),
        "readingMode": active_window_reading(),
    }


def active_window_reading() -> bool:
    r = run(["hyprctl", "activewindow", "-j"], timeout=3)
    try:
        address = json.loads(r.stdout).get("address", "") if r else ""
    except ValueError:
        address = ""
    return bool(address) and (OMALEXIA_STATE / "focus" / address.replace("/", "_")).exists()


# --------------------------------------------------------------------------
# Snapshot
# --------------------------------------------------------------------------


def snapshot() -> dict:
    return {
        "ok": True,
        "installed": (BIN / "omalexia-say").exists(),
        "read": read_aloud_status(),
        "dictation": dictation_status(),
        "look": look_status(),
    }


# --------------------------------------------------------------------------
# Changes
# --------------------------------------------------------------------------


def set_value(key: str, value: str) -> None:
    if key == "speed":
        speakd_request({"cmd": "set", "speed": float(value)})
        OMALEXIA_STATE.mkdir(parents=True, exist_ok=True)
        (OMALEXIA_STATE / "speed").write_text(f"{float(value):.2f}\n")
    elif key.startswith("voice:"):
        lang = key.split(":", 1)[1]
        # Downloads if needed; can take a while, so hand it to a terminal
        # when the voice is missing and do it inline when it is installed.
        if value in installed_voices():
            run([tool("omalexia-voice"), "set", lang, value], timeout=30)
        else:
            detached(["omarchy-launch-floating-terminal-with-presentation", f"omalexia-voice set {lang} {value}"])
    elif key == "engineEn" or key.startswith("engine:"):
        lang = "en" if key == "engineEn" else key.split(":", 1)[1]
        if value == "kokoro" and not (KOKORO_DIR / ".venv").exists():
            detached(["omarchy-launch-floating-terminal-with-presentation", f"omalexia-voice engine {lang} kokoro"])
        else:
            run([tool("omalexia-voice"), "engine", lang, value], timeout=30)
    elif key == "language":
        run([tool("omalexia-voice"), "language", value], timeout=15)
    elif key == "daemon":
        action = "start" if value == "true" else "stop"
        run(["systemctl", "--user", action, "omalexia-speakd.service"], timeout=15)
    elif key == "highlightDelay":
        # How long the marker waits for the audio the listener actually
        # hears; wireless headphones need more. Applied live by the daemon.
        delay = max(-0.3, min(1.5, float(value)))
        speakd_request({"cmd": "set", "highlight_delay": delay})
        OMALEXIA_STATE.mkdir(parents=True, exist_ok=True)
        (OMALEXIA_STATE / "highlight-delay").write_text(f"{delay:.2f}\n")
    elif key == "highlight":
        # The plugin holds the daemon's watch connection only while a
        # highlight mode is on, so "off" also stops the timing work.
        if value not in ("text", "bar", "off"):
            raise SystemExit(f"unknown highlight mode: {value}")
        OMALEXIA_STATE.mkdir(parents=True, exist_ok=True)
        (OMALEXIA_STATE / "highlight").write_text(value + "\n")
    elif key == "highlightStyle":
        if value not in ("word", "sentence", "both"):
            raise SystemExit(f"unknown highlight style: {value}")
        OMALEXIA_STATE.mkdir(parents=True, exist_ok=True)
        (OMALEXIA_STATE / "highlight-style").write_text(value + "\n")
    elif key == "dictationEngine":
        run(["voxtype", "config", "set", "engine", value], timeout=10)
        run(["systemctl", "--user", "restart", "voxtype.service"], timeout=15)
    elif key in ("feedback", "showTyped"):
        text = voxtype_config_text()
        flag = "true" if value == "true" else "false"
        if key == "feedback":
            text = toml_set(text, "audio.feedback", "enabled", flag)
        else:
            text = toml_set(text, "output.notification", "on_transcription", flag)
        VOXTYPE_CONFIG.write_text(text.rstrip("\n") + "\n")
        run(["systemctl", "--user", "restart", "voxtype.service"], timeout=15)
    elif key == "font":
        # Detached: the switch restarts the shell, and this process is the
        # shell's own child. Running it synchronously let the restart kill
        # the switch halfway through.
        detached([tool("omalexia-font"), "reset" if value == "default" else value])
    elif key == "textSize":
        run(["omarchy-display-text-size", str(int(value))], timeout=20)
    elif key == "tint":
        run([tool("omalexia-tint"), "on" if value == "true" else "off"], timeout=20)
    elif key == "reducedMotion":
        run([tool("omalexia"), "motion", "off" if value == "true" else "on"], timeout=15)
    elif key == "narrowSingleWindow":
        run(["omarchy-hyprland-toggle", "single-window-aspect-ratio", "on" if value == "true" else "off"], timeout=15)
    else:
        raise SystemExit(f"unknown setting: {key}")


def do_action(action: str, arg: str = "") -> None:
    say = tool("omalexia-say")
    if action in ("selection", "pointer", "clipboard", "ocr", "stop", "toggle"):
        detached([say, action])
    elif action == "test":
        detached([tool("omalexia-voice"), "test", arg or "en"])
    elif action == "add-language":
        detached(["omarchy-launch-floating-terminal-with-presentation", "omalexia-voice add"])
    elif action == "dictate":
        detached(["voxtype", "record", "toggle"])
    elif action == "dictate-cancel":
        detached(["voxtype", "record", "cancel"])
    elif action == "dictation-restart":
        run(["systemctl", "--user", "restart", "voxtype.service"], timeout=15)
    elif action == "dictation-model":
        detached(["omarchy-voxtype-model"])
    elif action == "dictation-install":
        detached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-voxtype-install"])
    elif action == "word-list":
        detached(["omarchy-launch-config-editor", str(CONFIG_HOME / "omalexia" / "replacements.txt")])
    elif action == "font-install":
        detached(["omarchy-launch-floating-terminal-with-presentation",
                  f"{tool('omalexia-font')} install; echo; read -r -p 'Press Enter to close.'"])
    elif action == "reading-mode":
        detached([tool("omalexia-focus"), "toggle"])
    elif action == "keys":
        detached(["omarchy-launch-floating-terminal-with-presentation", "omalexia keys; read -r"])
    elif action == "menu":
        detached(["omarchy-menu", "toggle", "omalexia"])
    elif action == "install":
        detached(["omarchy-launch-floating-terminal-with-presentation",
                  "echo 'Run ./install.sh from the omalexia checkout.'; read -r"])
    else:
        raise SystemExit(f"unknown action: {action}")


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[0] == "set":
        set_value(argv[1], argv[2])
    elif len(argv) >= 2 and argv[0] == "do":
        do_action(argv[1], argv[2] if len(argv) > 2 else "")
        if argv[1] in ("selection", "pointer", "clipboard", "ocr", "stop", "toggle", "dictate", "dictate-cancel",
                       "test", "reading-mode"):
            # Fire-and-forget actions: no need to re-read everything.
            print(json.dumps({"ok": True}))
            return 0
    print(json.dumps(snapshot()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
