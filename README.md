# Omalexia

Omarchy for dyslexic readers. Opt-in; not part of the baseline `install.sh`.

    ./omalexia/install.sh

Three things matter most for a dyslexic user of a computer: hearing text
instead of decoding it, speaking text instead of spelling it, and not having
to fight the layout to read. Omalexia does all three locally, on the machine,
with one key each. **F9 = talk, F10 = listen.**

| Key | Does |
|-----|------|
| `F10` | Reads the highlighted text aloud. Press again to stop. |
| `Shift + F10` | Reads the clipboard. |
| `Ctrl + F10` | Draw a box on the screen; reads what is in it (OCR, Dutch + English). Works on images, PDFs, video calls. |
| `Super + F10` / `Super + Shift + F10` | Faster / slower. |
| `F9` (hold) | Dictate; release to type it where the cursor is. (Omarchy default) |
| `Super + Ctrl + X` | Dictation on/off for long text. (Omarchy default) |
| `Shift + F9` | Cancel a dictation. |
| `Super + R` | Reading mode: the focused window floats at a readable width, centred. |
| `Super + Shift + R` | Warm "paper" tint on/off. |
| `Super + Ctrl + Backspace` | Stops a lone window stretching across a wide monitor. (Omarchy default, switched on) |
| `Super + Ctrl + Z` | Screen zoom. (Omarchy default) |
| `Super + Alt + A` | The Omalexia menu — everything above, plus voices, fonts, text size. |

`omalexia keys` prints this; `omalexia status` shows what is on.

## What it installs

### Listen: `omalexia-speakd` + `omalexia-say`

A small daemon keeps two [Piper](https://github.com/OHF-Voice/piper1-gpl)
neural voices loaded — English and Dutch — so speech starts about 0.1 s
after the key press. The language is detected from the text, so a Dutch
e-mail and an English doc both just work. It streams sentence by sentence
through PipeWire and stops the instant you ask.

Before speaking it unwraps hard line breaks (e-mails, terminals), drops
markdown symbols, bullets and `#` headings, and reads URLs as their host
name. F10 uses the Wayland primary selection (whatever is highlighted); for
the rare app that does not publish one it sends `Ctrl+C` and restores the
clipboard afterwards — never in a terminal, where `Ctrl+C` means interrupt.

**It works everywhere** because it is also the system voice: the installer
registers the daemon as the default [Speech Dispatcher](https://wiki.archlinux.org/title/Speech_dispatcher)
module. Firefox Reader View "Narrate", the Orca screen reader, `spd-say`,
and any program using the Web Speech API get the same voice, and cancelling
in the program stops playback.

Voices (`omalexia voice list`): the defaults are `en_US-lessac-medium` and
`nl_NL-pim-medium`. "medium" voices are the right choice on a CPU — on the
reference laptop (Arrow Lake, no NVIDIA) they start in 0.08–0.13 s, while
"high" voices take ~1 s per sentence for a modestly richer sound.
`omalexia voice set en en_GB-alan-medium` swaps a voice (downloads it if
needed); the menu lists the good ones.

Optional: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) is the
best-sounding local English voice that still runs on a CPU (~0.8 s to first
word here, no Dutch). `omalexia voice engine en kokoro` installs it into its
own venv (~350 MB) and switches English to it; Dutch stays on Piper.

Everything is local. Nothing is sent anywhere.

### Talk: Voxtype, tuned

Omarchy already ships [Voxtype](https://github.com/peteonrails/voxtype). The
stock config uses Whisper `base.en`: English only, mediocre accuracy. Omalexia
switches it to **Parakeet TDT 0.6B v3** (NVIDIA, ONNX): 25 European languages
including Dutch with automatic detection, punctuation and capitalisation built
in, and better accuracy than Whisper `base` at CPU speed. The installer
downloads the int8 model (~700 MB) and flips Voxtype to its ONNX binary; if
that fails it leaves Whisper in place.

`config/voxtype/config.toml` also turns on audio ticks when recording starts
and stops (hearing the confirmation beats seeing it), shows the typed text as
a notification so slips are caught immediately, raises the recording limit
from 60 s to 5 minutes, and pipes every transcription through
`omalexia-dictation-cleanup`: filler words in English and Dutch
(`uh`, `um`, `ehm`, `euh`…), doubled words, a capital letter, a full stop,
and your own **personal word list** in `~/.config/omalexia/replacements.txt`
(`hue sense = Husense`). It is rule-based and takes milliseconds; an
`omalexia-dictation-llm` executable on PATH is used first if you want to add
a local LLM pass later.

### Look

- **Reading font** — `omalexia font atkinson|opendyslexic|inter|reset` sets
  fontconfig's sans-serif/system-ui, the GTK interface and document fonts,
  Hyprland's own text, the terminal font (a Nerd-Font-patched companion, so
  icons keep working) and Chromium's page fonts plus a 14 px minimum in one
  go. The default is **Atkinson Hyperlegible** (Braille Institute; distinct
  letterforms, official Arch package). OpenDyslexic is one command away, but
  read the research note below before assuming it helps.
- **Text size** — the installer sets `omarchy display text size 14` once
  (shell, GTK apps and terminals together); the menu offers 12–18.
- **Reading mode** (`Super + R`) — floats the focused window at
  `min(1100 px, 60 % of the monitor)` width, 94 % height, centred; again to
  re-tile. Inactive windows are dimmed 12 % so the eye lands on the right one.
- **Narrow single window** — Omarchy's `single-window-aspect-ratio` toggle
  is switched on: a lone window on a wide monitor becomes square-ish instead
  of a 2400 px text line.
- **Paper tint** (`Super + Shift + R`) — 4900 K / 92 % gamma via hyprsunset.
  Comfort, not treatment (see below).
- **Cream theme** — `flexoki-light` is Omarchy's stock off-white theme and
  matches the BDA advice (dark text on cream, never pure white); the menu
  has a shortcut. Dark themes are fine too; pick the one that feels calm.
- **Reduced motion** — `omalexia motion off` disables window animations.
- Cursor 28 px, Qt accessibility on, OCR set to `eng+nld`, Dutch and English
  spell-check dictionaries (hunspell) for GTK apps and browsers.

`omalexia off` reverts every visual change; the keys and voices stay.

## Why these choices (research notes)

- **Fonts.** The British Dyslexia Association style guide asks for a plain
  sans-serif, 12–14 pt+, 1.5 line spacing, 60–70 characters per line,
  left-aligned, no italics/underline/caps, dark text on an off-white
  background. Controlled studies (Rello & Baeza-Yates 2013; Wery &
  Diliberto 2017; Kuster et al. 2018) found **no measurable benefit from
  OpenDyslexic or Dyslexie** over Arial/Helvetica/Verdana — readers tend to
  prefer the plain fonts — so the default is a well-made plain sans with
  distinct letterforms, and OpenDyslexic is opt-in for people who like it.
- **Line length** is the one layout rule with solid evidence, hence
  reading mode and the single-window aspect toggle rather than a font trick.
- **Colour tints / Irlen overlays**: a 2016 systematic review found no
  reliable effect. The tint is offered as a comfort setting only.
- **TTS engine.** Measured on the reference laptop: Piper medium 0.08–0.13 s
  to first audio per sentence; Piper high ~0.9 s; Kokoro-82M ~0.8 s (English
  only, clearly nicer); Supertonic 3 (the only quality Dutch alternative)
  ~5 s per sentence on CPU — not usable interactively yet.
- **STT engine.** Parakeet TDT v3 is multilingual, punctuates, and runs
  well on CPU through ONNX; Whisper `large-v3-turbo` would match it on
  accuracy but is several seconds per utterance without a GPU.

## Files

```
omalexia/
├── install.sh                       idempotent; --no-pkgs to skip sudo steps
├── bin/
│   ├── omalexia                     umbrella command (say, voice, font, focus, tint, …)
│   ├── omalexia-speakd              TTS daemon (systemd user service)
│   ├── omalexia-say                 client: selection | clipboard | ocr | toggle | stop | speed
│   ├── omalexia-voice               list/install/set voices, Kokoro installer
│   ├── omalexia-font                desktop-wide reading font switch
│   ├── omalexia-focus               reading mode for the focused window
│   ├── omalexia-tint                paper tint via hyprsunset
│   └── omalexia-dictation-cleanup   voxtype post-processor
└── config/
    ├── hypr/omalexia.lua            keys, dimming, fonts, env  → ~/.config/hypr/omalexia.lua
    ├── voxtype/config.toml          tuned dictation             → ~/.config/voxtype/config.toml
    ├── speech-dispatcher/omalexia.conf  sd_generic module       → ~/.config/speech-dispatcher/modules/
    ├── systemd/omalexia-speakd.service                          → ~/.config/systemd/user/
    ├── omarchy-menu.jsonc           menu block (merged between markers)
    ├── omalexia.toml                default TTS settings        → ~/.config/omalexia/config.toml
    ├── replacements.txt             personal word list template
    └── kokoro/worker.py             optional Kokoro engine worker
```

State lives in `~/.local/state/omalexia/` (font choice, speed, tint, reading
mode markers), voices in `~/.local/share/omalexia/voices/`, the socket in
`$XDG_RUNTIME_DIR/omalexia/`.

## Packages

Official repos: `ttf-atkinson-hyperlegible`, `otf-atkinsonhyperlegiblemono-nerd`,
`otf-opendyslexic-nerd`, `inter-font`, `hunspell-en_us`, `hunspell-nl`,
`tesseract-data-nld`, `speech-dispatcher`, `wl-clipboard`, `wtype`, `grim`,
`slurp`, `tesseract`, `jq`. AUR: `piper-tts` (builds a wheel on
`python-onnxruntime`) and `voxtype-bin`.

## Known limits

- Chromium's page fonts are written to its `Preferences` file, which Chromium
  rewrites on exit — `omalexia font` only touches it while Chromium is closed
  and tells you otherwise. Chromium's own **Reading mode** side panel
  (font, spacing, colours) is the better tool for long web articles.
- Hyprland does not share the primary selection with XWayland apps; F10
  falls back to `Ctrl+C` there.
- There is no per-word highlighting while reading; that needs app support.
- Kokoro and Piper "high" voices are not instant on CPU; the defaults are.
