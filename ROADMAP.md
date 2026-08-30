# Roadmap

What is next for Omalexia, and why. The rule from the README applies here too:
bring measurements, not opinions. Every item below says what to measure and
what would count as an answer.

[docs/speech-investigation.md](docs/speech-investigation.md) has the first set
of measurements, taken on 2026-08-24. It found that Piper `high` voices are
being rejected for the wrong reason and that the NPU is worth using for
dictation but not for speech. Items below marked **measured** come from there.

## 0. Fix the first sentence (measured, do this first)

Piper emits one chunk per sentence, so the wait before the first word is the
cost of synthesising the whole first sentence. After that, synthesis runs far
ahead of playback: a `high` voice has a real-time factor of about 0.54 and
gains half a second of slack per sentence spoken, so it never stutters on a
long document. The only penalty for a much better voice is about 0.7 s once,
at the start.

- [ ] Split the opening sentence at its first comma so the worst case stops
      being a 24-word sentence, or speak sentence one with the `medium` voice
      and switch to `high` from sentence two. Both voices are already in the
      daemon's engine cache.
- [ ] In reading mode the text is known before the key is pressed. Start
      synthesising on selection instead of on keypress.
- [ ] Re-evaluate the defaults afterwards. `high` and Kokoro were both ruled
      out on a latency cost that only applies to sentence one.
- [ ] Update the README, which currently presents the per-sentence cost of
      `high` voices as disqualifying.

## 1. Bench multiple text-to-speech providers

Omalexia ships Piper as the default and Kokoro as an option, chosen on one
laptop (Arrow Lake, no NVIDIA) with an informal timing run. That is one
machine and two engines. The choice should survive other hardware and a wider
field.

The good news is that the plumbing is already there. `omalexia-speakd`
resolves an engine per language in `engine_for()`, and an engine is a very
small object:

- `name`: string, shown in `omalexia status`
- `rate`: output sample rate, handed to the `Player`
- `synthesize(text, speed, cancel)`: generator yielding PCM chunks, checking
  `cancel` between them so a stop is instant

`PiperEngine` and `KokoroEngine` both fit in about 25 lines. A new provider is
a class, not a refactor, so the work here is evaluation rather than
architecture.

**To do**

- [ ] Add `omalexia voice bench`: run a fixed sentence set (English and Dutch,
      short and long, one with a URL and one with markdown) through every
      installed engine and print a table. It must run with a stub `pw-play` on
      PATH so a bench never plays audio.
- [ ] Record for each engine: time to first audio, real-time factor per
      sentence, resident memory while warm, cold start, languages covered,
      licence, install size, and whether it streams or has to synthesise the
      whole utterance before the first sample.
- [ ] Re-run the current defaults so the README numbers have a reproducible
      source: `en_US-lessac-medium`, `nl_NL-pim-medium`, the matching `high`
      voices, and Kokoro-82M.
- [ ] Compare the three installed Dutch voices (`nl_NL-pim-medium`,
      `nl_NL-mls-medium`, `nl_BE-nathalie-medium`) with listeners rather than
      timings. Nobody has actually done this and Dutch quality is the weakest
      link. **measured:** all three are within 0.35 to 0.72 s to first audio,
      so latency does not decide this.
- [ ] Improve text normalisation ahead of the engine: abbreviations, numbers,
      dates, currency, Dutch compounds. This is where synthetic speech most
      often sounds wrong and it is fixable with rules, not with a bigger model.
- [ ] Listen to the two Chatterbox Dutch samples in
      `~/.local/share/omalexia/spike/` (see the investigation addendum). If
      they clearly beat Piper's pim, spike the S3Gen decoder on the Arc iGPU
      via OpenVINO: the measured CPU split (LM RTF 0.45, decoder RTF 1.9)
      says that is the one piece standing between Chatterbox Dutch and
      real-time.
- [ ] Re-test Supertonic 3. It was rejected at roughly 5 s per sentence on
      CPU. Worth one more run if a faster CPU path appears.
- [ ] Evaluate `espeak-ng` as a deliberate last-resort engine. It sounds
      robotic, but it is instant, tiny, and covers languages Piper does not.
      A slow machine or an unsupported language is better served by an ugly
      voice than by silence.
- [ ] Run the whole bench on at least one slow machine and one machine with an
      NVIDIA GPU, and publish the table per class of hardware instead of a
      single winner.

**Where the defaults may need to differ.** Piper "medium" won on latency. If a
faster machine makes "high" start under about 0.2 s, the default should follow
the hardware rather than stay fixed. `omalexia voice bench` is what would let
the installer make that call.

### Cloud providers: opt-in, never the default

[OmaPilot](https://github.com/spencerbull/omarchy-omapilot) is a useful
comparison. It offers the same three-way choice of Kokoro locally, ElevenLabs
and OpenAI in the cloud, with ElevenLabs as the guided default and API keys in
`~/.config/omapilot/voice-auth.json`. It also delegates dictation entirely to
Voxtype, which is the same bet Omalexia makes.

Two things there are worth copying and one is not.

Worth copying: a provider list that is explicit and switchable, and keeping
credentials in their own file rather than in widget settings. Also worth
copying is refusing to auto-download a model. OmaPilot tells the user to
install Kokoro themselves rather than pulling hundreds of megabytes behind
their back, and Omalexia should keep asking too.

Not worth copying: a cloud voice as the default. Omalexia reads whatever is on
screen, which means e-mail, documents and passwords in a text field. Shipping
that to a third party by default is the wrong trade for an accessibility tool.

- [ ] If a cloud engine is added, it is off unless switched on explicitly, the
      status line says out loud that text leaves the machine, and it is never
      selected by an installer default.

## 1b. The path to Speechify and Apple quality (plan, 2026-08-25)

Studying how the commercial leaders get their quality shows four
ingredients, and none of them is a secret architecture: studio-grade
per-voice training data, a text frontend with years of linguistics in it,
compute placed where the model needs it (Speechify on cloud GPUs, Apple on
its Neural Engine), and consent-based voice cloning that substitutes a
short clean reference for the studio budget. Mapped to Omalexia, in order
of value per effort:

- [ ] **Text frontend** (copyable, cheap, helps every engine). Extend
      `prepare_text` with number, date, currency and unit reading per
      enabled language, an abbreviation lexicon, and a user dictionary for
      names; the personal `replacements.txt` mechanism from dictation is
      the model. Apple treats this as a co-equal pipeline stage next to
      the model, and it is the main reason their voices never stumble.
- [ ] **Listening gate for Chatterbox Dutch** (decides the next two).
      Judge `~/.local/share/omalexia/spike/nl-1.wav` and `nl-2.wav`
      against Piper's pim.
- [ ] **Dutch reference voice** (the cloning shortcut). Record 30 to 60
      seconds of clean Dutch speech, one voice, quiet room, and re-run the
      Chatterbox spike with it as the reference instead of the default
      English voice. This is exactly how Speechify makes celebrity voices,
      minus the celebrity.
- [ ] **Decoder on the Arc iGPU** (the Apple move, our hardware). The
      measured split says the Chatterbox language model already runs
      faster than real time on CPU (RTF 0.45) and only the fp32
      flow-matching decoder (RTF 1.9) blocks interactive use. Convert the
      decoder to OpenVINO, run it on the iGPU, keep the LM on CPU. Apple
      solved precisely this bottleneck by putting the vocoder on the
      Neural Engine.
- [ ] **Watch for a studio-grade open Dutch dataset**, or help one exist.
      The quality gap is at bottom a data gap: Kokoro proves 82M
      parameters with curated data beats big models with scraped data. If
      a clean multi-hour Dutch corpus appears (or the r-dh/dutch-vl-tts
      dataset matures), training a Piper high or Kokoro-class Dutch voice
      becomes the durable answer.
- [ ] Not copyable, so not planned: per-language linguist teams and
      private studio datasets. Cloud synthesis stays out per the
      cloud-providers section above.

## 2. Investigate Voxtype properly

Omalexia currently treats Voxtype as a black box that it reconfigures:
`config/voxtype/config.toml` swaps Whisper `base.en` for Parakeet TDT 0.6B v3
int8, adds start and stop ticks, shows the typed text as a notification,
raises the recording limit to five minutes, and pipes transcripts through
`omalexia-dictation-cleanup`. That was written against the config format, not
against a real understanding of the program.

**To do**

- [ ] Verify the Parakeet swap end to end on the reference laptop. It needs
      `sudo voxtype setup onnx --enable` plus the model download, which has
      not been run yet, so the shipped config is currently untested on real
      hardware.
- [ ] Measure Dutch and English accuracy against Whisper `base.en` on a fixed
      recording, with word error rate, not impressions. This is the claim the
      README makes and it should have a number behind it.
- [ ] Map the extension surface. Is the cleanup pipe a supported hook or a
      convenient config field. Can a model be registered without patching.
      What happens on an interrupted download or a busy microphone.
- [ ] Find out how Voxtype signals recording state. The bar plugin polls
      `status.py` today. OmaPilot instead records to a file under
      `$XDG_RUNTIME_DIR/omapilot` and reads the transcript when recording
      stops, which hints at a file-drop contract worth checking for. If
      Voxtype exposes a socket, a signal or a state file, the widget should
      subscribe instead of poll.
- [ ] Decide what to upstream. Ticks, the longer recording limit and a
      post-processing hook are useful to every Voxtype user, not just to
      dyslexic ones. Send those to
      [peteonrails/voxtype](https://github.com/peteonrails/voxtype) rather
      than carrying them as local config forever.
- [ ] Confirm the fallback actually works: if the ONNX switch fails the
      installer is supposed to leave Whisper in place. Test it by making the
      download fail on purpose.

## 3. Use the NPU where it actually pays (measured)

The reference laptop has a working NPU: PCI `8086:7D1D`, `intel_vpu` loaded,
`/dev/accel/accel0` world readable and writable, so no udev rule or group
membership is needed. The whole userspace stack is in Arch `extra`
(`intel-npu-driver`, `intel-npu-compiler`, `level-zero-loader`, `openvino`,
`openvino-intel-npu-plugin`, `python-openvino`), roughly 400 MB, none of it
installed yet.

Dictation is the case worth pursuing. An OpenVINO build of the same Parakeet
model Omalexia already uses reports 25.7x real time on the NPU against 5 to 8x
on CPU at identical word error rate, on a chip with the same NPU device ID.
Fixed 10 s chunks give the static shapes an NPU wants.

Text to speech is the case worth dropping. Variable-length text into
variable-length audio is the shape an NPU handles worst, no Piper OpenVINO path
exists, and the one Kokoro project that accepts an `"NPU"` device string has no
tests or benchmarks behind it. More to the point, `medium` voices already run
at a real-time factor of 0.05, so speed is not the problem quality has.

- [ ] Timebox a spike: install the six packages behind an explicit opt-in,
      confirm OpenVINO enumerates `NPU`, run the Parakeet OpenVINO build.
- [ ] Confirm from `dmesg | grep ivpu` which firmware blob loads, to settle
      whether this is the ~13 TOPS NPU 3720 generation as the device ID implies.
- [ ] Answer the Voxtype pluggability question first. The OpenVINO build is a
      four-model pipeline with its own chunking and state handling, not a
      drop-in for the ONNX file Voxtype loads.
- [ ] Keep it optional. It is a large download for a battery and headroom win,
      not a responsiveness one.
- [ ] Do not put TTS on the NPU until a heavier Dutch-capable voice exists that
      would justify the freed headroom.

## 4. Smaller things

- [x] Per-word highlighting while reading (shipped 2026-08-26). It needed no
      application support after all: the daemon times every word from the
      audio it is about to play (phoneme-weighted, exact at each sentence
      boundary) and streams events over a `watch` socket; `omalexia-locate`
      finds the words on screen once per reading, and the bar plugin draws
      a click-through marker over the actual text. A subtitle-bar mode and
      off switch sit next to it in the panel. Since 2026-08-27 a selection
      backend comes first: the on-screen selection highlight is detected by
      colour and the selected text fitted onto it as a character grid,
      pixel-exact in ~0.5 s with no OCR; OCR (banded, single-threaded
      workers, cursor-band fast pass, geometric outlier filter) remains the
      fallback for clipboard and screen reads. Follow-ups, in value order:
      - [x] Re-locate when the text moves (shipped 2026-08-27, after
            researching how macOS does it: Spoken Content re-queries the
            app's accessibility geometry, kAXBoundsForRange, while it
            speaks). `omalexia-locate --follow` re-captures the window
            about once a second for the whole utterance, re-finds the
            tracked text by row-signature correlation (scroll and window
            moves shift the boxes), re-fits a moved selection exactly,
            hides the marker when the text leaves the screen, and rations
            re-OCR. Verified live: a foot terminal scrolling twelve rows
            mid-read kept the marker on the spoken word.
      - [ ] The "Screen" (region OCR) reading flow already runs tesseract to
            get its text; keep those word boxes instead of re-locating, and
            the marker there becomes exact for free.
      - [ ] Retire the terminal adapters as upstream accessibility lands.
            The architecture is: one OS-standard backend (AT-SPI, covering
            browsers, Electron, GTK and Qt with no per-app code) plus two
            small adapters for foot and ghostty, which exist only because
            those terminals do not implement AT-SPI (VTE terminals do), and
            an OCR net under everything, which is also how macOS handles
            pixel-only content (Live Text). Ghostty is actively building
            accessibility support; when a terminal starts publishing its
            text on the accessibility bus, the tree backend picks it up
            automatically and its adapter can be deleted. Consider filing
            or supporting AT-SPI feature requests for foot and ghostty
            upstream; that, not more adapters, is the way this ends.
      - [ ] AT-SPI as a precision upgrade where it exists: this is exactly
            the macOS mechanism (bounds-for-range on the accessibility
            tree). Findings from the 2026-08-27 spike on the laptop: the
            AT-SPI stack runs (registry + bus), gi.repository.Atspi works
            on /usr/bin/python3, `Text.get_range_extents` with WINDOW
            coordinates plus the hyprctl window origin is the API to use.
            But foot has no accessibility tree at all, and Chromium only
            builds its tree for a persistent registered AT client (or
            launched with a11y forced): the runtime ScreenReaderEnabled
            flag alone did not materialize it. So this needs a small
            long-lived a11y client (or install-time browser flags) and
            only pays off in browsers and GTK/Qt apps; the selection and
            signature tracking already cover the terminals.
      - [ ] If the phoneme-weighted timing ever feels off inside long
            sentences, forced alignment (Vosk small) on the synthesized
            audio during the write-ahead is the exact fix.
- [ ] A second opinion on the font research. Atkinson Hyperlegible is the
      default and OpenDyslexic is opt-in because the evidence for it is weak.
      If better evidence turns up either way, the default should move.

Open an issue at https://github.com/thefreshoffice/omalexia/issues to pick
something up, or say what is missing from this list.
