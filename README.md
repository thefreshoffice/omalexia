# Omalexia

Omarchy for dyslexic readers, by Michael de By | The Fresh Office. An opt-in profile
on top of an [Omarchy](https://omarchy.org/) install.

    git clone https://github.com/thefreshoffice/omalexia.git
    cd omalexia
    ./install.sh

Safe to re-run. Package steps need `sudo`, so run it from a terminal.

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
| `Super + R` | Reading mode: one clean reading window; everything else tucks away. |
| `Super + Shift + R` | Warm "paper" tint on/off. |
| `Super + Ctrl + Backspace` | Stops a lone window stretching across a wide monitor. (Omarchy default, switched on) |
| `Super + Ctrl + Z` | Screen zoom. (Omarchy default) |
| `Super + Alt + A` | The Omalexia menu: everything above, plus voices, fonts, text size. |

`omalexia keys` prints this; `omalexia status` shows what is on.

### In the bar

An Omalexia widget (an open book) sits in the bar's right section: it
brightens while reading aloud, turns urgent while dictation listens, and
opens a panel with everything above as buttons and switches: read, stop,
speed, voices, dictation engine, reading mode, tint, font, text size. Right
click reads the selection, middle click toggles dictation. See
[`plugin/README.md`](plugin/README.md).

## What it installs

### Listen: `omalexia-speakd` + `omalexia-say`

A small daemon keeps two [Piper](https://github.com/OHF-Voice/piper1-gpl)
neural voices loaded (English and Dutch), so speech starts about 0.1 s
after the key press. The language is detected from the text, so a Dutch
e-mail and an English doc both just work. It streams sentence by sentence
through PipeWire and stops the instant you ask. The speed setting is read
between sentences, so nudging it in the bar panel changes the pace of the
text you are listening to within a few seconds, not just the next one. The
range is 0.5x to 4x: up to 2x the engine itself speaks faster, and beyond
that the audio is time-stretched with ffmpeg's pitch-preserving atempo
filter, so 4x stays intelligible instead of becoming a chipmunk. The
daemon keeps about four seconds of audio buffered ahead of playback, so the
next sentence is synthesized while the current one plays and sentence
boundaries stay seamless. Playback starts once about a second and a half is
in hand, so a short opening sentence no longer runs dry while the second
one synthesizes, and paragraph breaks keep their identity: the reader takes
a deliberate breath there instead of rushing on (or worse, an accidental
gap).

Before speaking it unwraps hard line breaks (e-mails, terminals), drops
markdown symbols, bullets and `#` headings, and reads URLs as their host
name. F10 uses the Wayland primary selection (whatever is highlighted); for
the rare app that does not publish one it sends `Ctrl+C` and restores the
clipboard afterwards, never in a terminal, where `Ctrl+C` means interrupt.

**It works everywhere** because it is also the system voice: the installer
registers the daemon as the default [Speech Dispatcher](https://wiki.archlinux.org/title/Speech_dispatcher)
module. Firefox Reader View "Narrate", the Orca screen reader, `spd-say`,
and any program using the Web Speech API get the same voice, and cancelling
in the program stops playback.

Voices (`omalexia voice list`): the defaults are `en_US-lessac-medium` and
`nl_NL-pim-medium`. "medium" voices are the right choice on a CPU: on the
reference laptop (Arrow Lake, no NVIDIA) they start in 0.08–0.13 s, while
"high" voices take ~1 s per sentence for a modestly richer sound.
`omalexia voice set en en_GB-alan-medium` swaps a voice (downloads it if
needed); the menu lists the good ones.

**Any language, not just these two.** The Piper catalog covers about 45
languages and `omalexia voice add de` (or `fr`, `uk`, `ar`, `zh`, ...) is all
it takes: a good default voice is downloaded on the spot and the language
joins the detector, so a German paragraph is simply read in German.
`omalexia voice languages` lists what is enabled and what is available,
`remove` disables one again, and the bar panel's language selector follows
whatever is enabled. Detection first looks at the script (Cyrillic, Greek,
Arabic, CJK, ...), then scores Latin-script candidates on function words and
characters like ß, ñ or ő. Only the three most recently used voices are kept
loaded, so enabling ten languages costs disk, not memory.

Optional: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) is the
best-sounding local voice that still runs on a CPU (~0.8 s to first word
here). It speaks English, Spanish, French, Hindi, Italian, Japanese,
Portuguese and Chinese; `omalexia voice engine fr kokoro` switches any of
those languages to it (the first use installs its venv, ~350 MB). One shared
worker serves all Kokoro languages, so each extra language costs nothing.
Dutch is the notable gap; it stays on Piper. Once
enabled it is loaded at daemon start and kept loaded: settings changes reload
only the voices they touch, and when the recently-used cap evicts a voice it
picks a Piper one first, so Kokoro answers at synthesis speed (about 0.7 s
for the first sentence), not model-load speed.

**Read-along highlighting.** While text is read aloud, the word being
spoken is marked right in the text on screen: the daemon knows the exact
duration of every sentence before playing it, divides it over the words by
phoneme count (espeak-ng), and streams word events on the playback clock;
`omalexia-locate` finds the words on screen once per reading, so a
translucent marker glides across the actual words. When the reading came
from a visible selection, the highlight itself marks the text: the
highlighted rows are detected by colour (a themed selection colour or
foot-style inverted fg/bg alike) and the selected text is fitted onto them
as a character grid, pixel-exact in about half a second with no OCR at
all. Otherwise the window is OCRed (tesseract word boxes, banded and run
in parallel) and the spoken words aligned to them; a word matched on its
own that disagrees with its neighbours' geometry is dropped rather than
highlighted in the wrong place. That works in any app, browser, PDF viewer
or terminal, because no app cooperation is needed; when the text is not
visible (reading the clipboard from elsewhere), nothing is drawn rather
than something wrong. The locator keeps following for the whole reading,
the way macOS Spoken Content re-queries text geometry while it speaks:
it re-captures just the tracked strip (quick checks while things move,
lazy ones once the screen settles), finds the text again by row-signature
correlation (so scrolling and window moves shift the marker instead of
stranding it), re-fits a moved selection exactly, and hides the marker
when the text leaves the screen. The rendering is built not to flicker:
the sentence being read gets a faint steady wash with the word pill
riding on top, missed words are interpolated between their neighbours
instead of blinking the marker off, every text line gets one uniform
rail height so the pill does not bounce with letter shapes, and the pill
fades and glides rather than popping. Word timing is closed-loop: each
event waits for the audio actually taken by the player (measured off the
playback pipe), so a stalled or slow output holds the marker back
instead of letting it run ahead. The panel's "Marker timing" slider adds
the one thing software cannot see, the lag of the listening device;
wireless headphones typically want a few tenths of a second more, tuned
by ear while reading (it applies live). The panel's "Highlight words" setting
switches between marking the text, a subtitle bar at the bottom of the
screen showing the sentence with the spoken word in a pill, or off; the
"Highlight style" setting picks what gets marked in the text: the word
being spoken (the standard), the whole sentence, or both together (a
sentence wash with the word pill riding on it). Pairs
best with reading mode, which keeps the window still.

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
(`fresh office = The Fresh Office`). It is rule-based and takes milliseconds; an
`omalexia-dictation-llm` executable on PATH is used first if you want to add
a local LLM pass later.

### Look

- **Reading font**: `omalexia font atkinson|opendyslexic|inter|reset` sets
  fontconfig's sans-serif/system-ui, the GTK interface and document fonts,
  Hyprland's own text, the terminal font (a Nerd-Font-patched companion, so
  icons keep working) and Chromium's page fonts plus a 14 px minimum in one
  go. The default is **Atkinson Hyperlegible** (Braille Institute; distinct
  letterforms, official Arch package). OpenDyslexic is one command away, but
  read the research note below before assuming it helps.
- **Text size**: the installer sets `omarchy display text size 14` once
  (shell, GTK apps and terminals together); the menu offers 12–18.
- **Reading mode** (`Super + R`): floats the focused window at
  `min(1100 px, 60 % of the monitor)` width, 94 % height, centred, and tucks
  the workspace's other windows away so you face one clean window. `Super+R`
  again brings everything back: the hidden windows return, and the reading
  window goes back to where it was, exact position and size if it was
  floating, back into the tiling layout on its own workspace if it was tiled.
- **Narrow single window**: Omarchy's `single-window-aspect-ratio` toggle
  is switched on: a lone window on a wide monitor becomes square-ish instead
  of a 2400 px text line.
- **Paper tint** (`Super + Shift + R`): 4900 K / 92 % gamma via hyprsunset.
  Comfort, not treatment (see below).
- **Reduced motion**: `omalexia motion off` disables window animations.
- Cursor 28 px, Qt accessibility on, OCR set to `eng+nld`, Dutch and English
  spell-check dictionaries (hunspell) for GTK apps and browsers.

`omalexia off` reverts every visual change; the keys and voices stay.

## Why these choices (research notes)

- **Fonts.** The British Dyslexia Association style guide asks for a plain
  sans-serif, 12–14 pt+, 1.5 line spacing, 60–70 characters per line,
  left-aligned, no italics/underline/caps, dark text on an off-white
  background. Controlled studies (Rello & Baeza-Yates 2013; Wery &
  Diliberto 2017; Kuster et al. 2018) found **no measurable benefit from
  OpenDyslexic or Dyslexie** over Arial/Helvetica/Verdana (readers tend to
  prefer the plain fonts), so the default is a well-made plain sans with
  distinct letterforms, and OpenDyslexic is opt-in for people who like it.
- **Line length** is the one layout rule with solid evidence, hence
  reading mode and the single-window aspect toggle rather than a font trick.
- **Colour tints / Irlen overlays**: a 2016 systematic review found no
  reliable effect. The tint is offered as a comfort setting only.
- **TTS engine.** Measured on the reference laptop: Piper medium 0.08–0.13 s
  to first audio per sentence; Piper high ~0.9 s; Kokoro-82M ~0.8 s (English
  only, clearly nicer); Supertonic 3 (the only quality Dutch alternative)
  ~5 s per sentence on CPU, not usable interactively yet.
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
├── plugin/                          Omarchy shell bar widget + panel (thefreshoffice.omalexia)
│   ├── manifest.json, BarWidget.qml, Panel.qml, Service.qml
│   └── status.py                    snapshot + actions helper the QML calls
├── site/                            the omalexia announcement page (static, self-contained)
│   ├── index.html
│   └── README.md                    hosting: GitHub Pages, Cloudflare/Netlify, or nginx
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
  rewrites on exit, so `omalexia font` only touches it while Chromium is closed
  and tells you otherwise. Chromium's own **Reading mode** side panel
  (font, spacing, colours) is the better tool for long web articles.
- Hyprland does not share the primary selection with XWayland apps; F10
  falls back to `Ctrl+C` there.
- Read-along highlighting re-checks the screen about once a second while
  reading, so scrolling and window moves are followed; a very fast fling can
  lag the marker by a beat, and text that leaves the window hides the marker
  until it comes back. The subtitle bar mode has none of these limits.
- Kokoro and Piper "high" voices are not instant on CPU; the defaults are.
- At 4x a Piper "high" voice synthesizes at roughly the pace it plays, so a
  long 4x session with one can occasionally pause to catch up; "medium"
  voices and Kokoro keep up comfortably.

## Contributing

Omalexia is open source and the goal is simple: the best accessibility add-on
for Omarchy. Everyone who wants to help is welcome, in whatever way fits:

- Dyslexic readers: tell us what works and what does not. An issue that says
  "this key did the wrong thing" or "this voice is tiring" is worth more than
  a feature request.
- Speech and models: better voices, faster engines, more languages.
- Fonts, colour and layout: the research notes above are the starting point;
  bring measurements, not just opinions.
- Translations of the panel, menu and site.
- Testing on other hardware, especially machines without a fast CPU.

[ROADMAP.md](ROADMAP.md) lists what is queued and what still needs
measuring, including a bench of more speech engines and a proper look at
Voxtype. Open an issue at https://github.com/thefreshoffice/omalexia/issues to
talk first, or send a pull request straight away. Keep changes local-first,
reversible with `omalexia off`, and one key away.

## License

MIT. See [LICENSE](LICENSE).
