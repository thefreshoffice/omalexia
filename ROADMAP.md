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

- [ ] Per-word highlighting while reading. Needs application support, so start
      by finding out which applications offer any.
- [ ] A second opinion on the font research. Atkinson Hyperlegible is the
      default and OpenDyslexic is opt-in because the evidence for it is weak.
      If better evidence turns up either way, the default should move.

Open an issue at https://github.com/thefreshoffice/omalexia/issues to pick
something up, or say what is missing from this list.
