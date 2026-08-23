# Omalexia bar widget

`husense.omalexia` — an Omarchy shell plugin (bar widget + panel) for
[Omalexia](../README.md). Installed by `omalexia/install.sh`, which copies
this directory to `~/.config/omarchy/plugins/husense.omalexia/` and enables
it in the bar's right section.

## In the bar

An open book. It brightens in the accent colour while text is being read
aloud and turns urgent (with a microphone glyph) while dictation is
listening; a small pulsing dot marks either. Dimmed when the read-aloud
daemon is off.

- Left click: open the panel.
- Right click: read the selection, or stop if already reading (same as F10).
- Middle click: start/stop dictation (same as Super+Ctrl+X).

## The panel

- **Header** — state (Ready / Reading aloud / Listening) and a switch that
  starts or stops the read-aloud daemon.
- **Read aloud** — Selection, Clipboard, Screen (OCR), Stop; a speed slider;
  English and Dutch voice pickers (voices not yet downloaded are marked ↓ and
  fetched when chosen; Kokoro appears as a premium English option); the
  language rule; Test the voice.
- **Dictation** — state and engine in one line; Dictate / Cancel / Word list /
  Restart; the engine picker (Parakeet when its ONNX variant is enabled,
  otherwise a note about the sudo step); sound-on-record and show-typed-text
  switches, written straight into `~/.config/voxtype/config.toml`.
- **Look** — Reading mode and Cream theme buttons; Narrow single window,
  Paper tint and Reduced motion switches; the reading font and text size.
- **Footer** — Keys (cheat sheet), Menu, Refresh.

Keyboard: `j`/`k` or arrows move between rows, `h`/`l` walk the buttons in a
row, nudge the slider or cycle a picker, Enter activates, Esc closes, Tab
moves to the neighbouring bar panel. Shortcuts: `r` read selection, `s` stop,
`d` dictate, `+`/`-` speed.

## How it works

`Service.qml` runs two long-lived streams — `omalexia-say follow` for the
read-aloud state and Omarchy's `omarchy-voxtype-status` for dictation — so
the icon changes the moment something happens, and refreshes a full snapshot
from `status.py` every 20 s (configurable) or after every change. `status.py`
is the only place that reads config files or runs commands; every button
and switch maps onto the same `omalexia` commands the keys and the menu use.

IPC: `omarchy-shell husense.omalexia open|close|toggle|read|stop|dictate|status`.

## Settings (bar widget settings UI)

- `refreshIntervalSec` — snapshot interval, default 20.
- `showDictation`, `showLook` — hide sections you never touch.
