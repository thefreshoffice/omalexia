# Speech investigation: quality and the NPU

Measured on the reference laptop (Intel Core Ultra 7 255H, Arrow Lake-H, no
NVIDIA) on 2026-08-24, against the voices Omalexia installs today.

Two questions were asked: can the speech quality be better, and can the NPU be
used for dictation and speech. The short answers are yes and partly, and the
two are less related than they look.

## Summary

1. **The quality ceiling is set by the first sentence, not by the CPU.**
   Piper `high` voices synthesise at a real-time factor of about 0.54, so once
   playback starts they stay comfortably ahead of it forever. The only cost is
   that the first sentence takes about 0.9 s instead of 0.2 s. Fix the first
   sentence and `high` becomes usable everywhere. This needs no new model and
   no NPU.
2. **The NPU is a clear win for dictation and a doubtful one for speech.**
   Speech recognition on this NPU generation is measured at roughly 3 to 5
   times the CPU throughput at identical accuracy. Text to speech on NPU is
   unproven and architecturally awkward, and would not fix quality anyway.
3. **Dutch is what blocks the better-sounding models.** Every model that
   clearly beats Piper on naturalness is either English-only or too heavy for
   a CPU. That, not compute, is the real constraint.

## Part 1: text to speech quality

### What the current voices actually do

One sentence, synthesised cold after a warm-up pass, `OMP_NUM_THREADS=4`:

| voice | load | time to first audio | real-time factor |
|---|---|---|---|
| `en_US-lessac-medium` | 0.84 s | 0.32 s | 0.051 |
| `en_US-lessac-high` | 1.35 s | 3.46 s | 0.543 |
| `en_GB-alba-medium` | 1.44 s | 0.38 s | 0.058 |
| `nl_NL-pim-medium` | 1.34 s | 0.42 s | 0.055 |
| `nl_NL-mls-medium` | 1.41 s | 0.72 s | 0.069 |
| `nl_BE-nathalie-medium` | 1.24 s | 0.35 s | 0.063 |

The important detail is that time to first audio and total synthesis time were
identical in every row. Piper emits **one chunk per sentence**. There is no
partial output within a sentence, so the delay before the first word is the
cost of synthesising the whole first sentence. The 3.46 s figure for
`lessac-high` is a deliberately long 24-word test sentence, which is close to
a worst case.

### Why `high` voices are being rejected for the wrong reason

The README says `high` voices take "~1 s per sentence for a modestly richer
sound", and treats that as disqualifying. It is not, because synthesis and
playback are already pipelined: `_run` in `omalexia-speakd` writes each chunk
into `pw-play` as soon as the engine yields it. What matters is whether each
sentence is ready before the previous one finishes playing.

Four-sentence paragraph, `en_US-lessac-high`. "margin" is how long the chunk
was ready before playback needed it:

| sentence | ready at | audio length | needed at | margin |
|---|---|---|---|---|
| 1 | 0.93 s | 2.50 s | 0.00 s | **-0.93 s** |
| 2 | 2.15 s | 2.54 s | 2.50 s | +0.35 s |
| 3 | 3.35 s | 2.96 s | 5.04 s | +1.69 s |
| 4 | 4.67 s | 3.04 s | 8.00 s | +3.33 s |

The margin is negative exactly once, on the first sentence, and then grows
without bound. Because the real-time factor is 0.54, the buffer gains about
half a second of slack per sentence spoken. A `high` voice will never stutter
on a long document. It just starts 0.7 s later than a `medium` one.

`medium` for comparison: first sentence ready at 0.21 s, margin +2.03 s by
sentence two.

### The fix

Only the first sentence needs to be fast. Three options, cheapest first:

- **Split the opening sentence.** Synthesise the first clause up to the first
  comma with the same voice, then continue normally. Cuts the worst case
  without a second model in memory.
- **Fast first sentence, good rest.** Speak sentence one with the `medium`
  voice and switch to `high` from sentence two. Both voices are already loaded
  in the daemon's engine cache. The seam is audible if you listen for it, so
  test whether it actually bothers anyone.
- **Warm start.** For reading mode, where the text is known before the key is
  pressed, begin synthesising on selection rather than on keypress.

The same argument rehabilitates Kokoro. At roughly 0.8 to 1.2 s per sentence
its real-time factor is about 0.35, so it too only ever pays on sentence one.
It is currently described as an optional extra for people who will accept a
delay. That framing is wrong and should change.

**This is the highest value change available and it is small.** It affects
`_run` and the engine selection in `engine_for`, nothing else.

### Better models, and why Dutch blocks them

Ranked roughly by naturalness, with the constraint that matters:

| model | licence | Dutch | viable on this CPU |
|---|---|---|---|
| Piper `medium` | MIT | yes | yes, current default |
| Piper `high` | MIT | yes, if a voice exists | yes, see above |
| [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) | Apache 2.0 | **no** | yes, English only |
| [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) 0.6B | Apache 2.0 | **no** | GGUF path only, unmeasured |
| [Chatterbox Multilingual](https://www.resemble.ai/chatterbox/) | MIT | **yes** | **no**, wants a GPU |
| XTTS v2 | non-commercial | yes | no |

Kokoro scores highest in its size class on naturalness and is Apache 2.0, but
has no Dutch. Qwen3-TTS covers ten languages and Dutch is not among them.
Chatterbox is MIT, covers Dutch, and is the only one that clearly beats Piper
on naturalness while being licensable, but it runs at a real-time factor of
about 0.5 on an RTX 4090. On a CPU with no NVIDIA it is not a candidate for
interactive reading.

So the honest position is: **English can get better today via Kokoro, Dutch
cannot.** Anything that improves Dutch has to come from either a better Piper
`nl` voice or from training one. Three Dutch voices are already installed and
have never been compared side by side, which is the obvious first step.

There is also a non-model lever worth more than it sounds: the text
normalisation in front of the engine. Abbreviations, numbers, dates, currency
and Dutch compound words are where synthetic speech most often sounds wrong,
and that is fixable with rules rather than parameters.

## Part 2: the NPU

### What the hardware is

| | |
|---|---|
| CPU | Intel Core Ultra 7 255H (Arrow Lake-H) |
| NPU PCI ID | `8086:7D1D` at `00:0b.0` |
| kernel driver | `intel_vpu` 1.0.0, loaded, kernel 7.1.8-arch1-3 |
| device node | `/dev/accel/accel0`, mode `crw-rw-rw-` |
| firmware present | `vpu_37xx`, `vpu_40xx`, `vpu_50xx` in `/lib/firmware/intel/vpu/` |

The NPU is present, bound, and the device node is world readable and writable,
so **no group membership or udev rule is needed**. Nothing has to be done to
the system to make it reachable by a normal user.

Device ID `7D1D` is the same one Meteor Lake uses, which suggests this is the
NPU 3720 generation at roughly 13 TOPS INT8 rather than the much faster part in
the Core Ultra 200V series. That matters for expectations and it is worth
confirming from `dmesg | grep ivpu` which firmware blob actually loads.

### The userspace stack is all in the official Arch repositories

Nothing here comes from the AUR:

```
extra/intel-npu-driver         1.35.0
extra/intel-npu-compiler       2026.28
extra/level-zero-loader        1.32.0
extra/openvino                 2026.3.0
extra/openvino-intel-npu-plugin 2026.3.0
extra/python-openvino          2026.3.0
```

None of them are installed yet. That is roughly a 400 MB one-time install, so
it belongs behind an explicit opt-in, not in the default installer.

### Dictation on the NPU: worth doing

[FluidInference/parakeet-tdt-0.6b-v3-ov](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-ov)
is an OpenVINO build of the exact model Omalexia already configures Voxtype to
use. Reported on a Core Ultra 7 155H, which carries the same NPU device ID as
this machine:

| device | throughput | word error rate |
|---|---|---|
| NPU | 25.7x real time | 3.7% |
| CPU | 5 to 8x real time | 3.7% |

Three to five times the throughput at identical accuracy, at lower power. The
reason it works so well is that the pipeline runs in fixed 10 s chunks with 3 s
overlap, which gives the static shapes an NPU wants.

The catch is that this is a four-model OpenVINO pipeline with its own chunking,
LSTM state handling and token deduplication, not a drop-in replacement for the
ONNX file Voxtype loads. Whether it can be used depends entirely on how
pluggable Voxtype's backend is, which is already an open question on the
roadmap.

The honest benefit also needs stating: dictation is not currently slow. The win
is battery and leaving the CPU free, not responsiveness. Which leads to the one
place where the two halves of this investigation meet.

### Speech on the NPU: probably not, and it would not help

Kokoro can be pointed at an NPU in the sense that
[OpenArc](https://deepwiki.com/SearchSavior/OpenArc/3.3-openvino-engine-(kokoro-tts))
passes a device string of `"CPU"`, `"GPU"` or `"NPU"` to `compile_model`. But
there are no NPU benchmarks, no tests and no documented caveats anywhere in
that project. It is an untested code path, not a supported feature.

Piper has no OpenVINO path at all. The one published NPU port of Piper targets
Rockchip's RK3588 and reports a 4.3x speedup, but the write-up is mostly about
fighting dynamic input shapes and stitching artefacts, which is exactly the
problem an Intel NPU has too.

That is the structural point. Speech recognition chops audio into fixed
windows, so it suits an accelerator that wants static shapes. Text to speech
takes variable-length text and produces variable-length audio, which is the
opposite. An autoregressive vocoder is the least NPU-friendly shape there is.

And even if it worked, look at the numbers above: `medium` voices already
synthesise at a real-time factor of 0.05. They are twenty times faster than
they need to be. Making them faster changes nothing a user can hear. The NPU
cannot make a voice sound better, only produce the same audio using less power.

**The one genuinely interesting version of this idea** is the combination:
move dictation to the NPU, which frees CPU and thermal headroom, and spend that
headroom on a heavier, better-sounding TTS model. That is a real argument, but
it only pays off if a better Dutch-capable model exists to spend it on, which
per Part 1 it currently does not. So the ordering is: solve quality first, and
treat the NPU as the thing that makes the answer affordable afterwards.

## What to do next

In order:

1. Fix the first sentence. Measured, small, benefits every user immediately,
   and makes both Piper `high` and Kokoro viable defaults.
2. Compare the three installed Dutch voices properly, with listeners rather
   than timings.
3. Improve text normalisation before the engine. Cheap, and it fixes the
   mistakes people actually notice.
4. Build `omalexia voice bench` so all of the above stops being anecdote.
5. Timebox an NPU spike: install the six packages, confirm `openvino` enumerates
   `NPU`, and run the Parakeet OpenVINO build. Answer the Voxtype pluggability
   question before promising anything.
6. Leave TTS on NPU alone until something above changes.
