# Multilingual TTS above 8/10, local first (research, 2026-08-30)

The goal: reading voices that a listener would rate above 8 out of 10 in
as many languages as possible, running on this machine, local first.
Dutch is the first target (the household language Kokoro does not
speak), then German, French, Spanish, Italian, Polish and the rest of
Europe. Cloud is out of scope except as a quality reference.

## The machine

- Intel Core Ultra 7 255H (Arrow Lake-H), 16 threads, 30 GB RAM.
- Intel Arc Pro 130T/140T iGPU (Xe, `renderD128`).
- Intel NPU, Core Ultra 200H series (`intel_vpu`, `/dev/accel/accel0`).
- Installed today: onnxruntime 1.29 CPU-only. NOT installed: OpenVINO,
  intel-compute-runtime, Level Zero. Any GPU/NPU work starts with
  `omarchy-pkg-add intel-compute-runtime` (sudo) and `pip install
  openvino` (no sudo).

## Where the stack stands (measured on this machine)

- Piper medium voices: ~45 languages, RTF 0.05, start 0.08-0.13 s.
  Reliable, flat prosody; subjective quality around 5-6. The outside
  ranking below scores Piper 4.5, which matches the household verdict
  for Dutch (pim-medium is understandable, not pleasant).
- Kokoro-82M: 8 languages (en es fr hi it ja pt zh), first word ~0.8 s,
  RTF ~0.3 on CPU. The blog scores it 7.0; the household experience for
  English is better than that. No Dutch, and the model is not trainable
  on new languages without the (closed) recipe.
- Chatterbox Multilingual, ONNX export already on disk (1.7 GB):
  MIT license, 23 languages confirmed from the model card: ar da de el
  en es fi fr he hi it ja ko ms nl no pl pt ru sv sw tr zh; that is
  the broadest European coverage of any high-quality open model
  (Dutch, Danish, German, Greek, Finnish, Norwegian, Polish, Swedish
  and Turkish are all absent from Kokoro). Measured here: quantized LM
  (354 MB q4) at RTF 0.45 on CPU; the fp32 flow-matching conditional
  decoder (534 MB) is the blocker at RTF 1.9 (total 2.4). That single
  file is the acceleration target. Two Dutch samples still await a
  listening verdict: `pw-play ~/.local/share/omalexia/spike/nl-1.wav`.

## The OpenVox frame (starting point, unverified)

The user-supplied article (openvoxai.com, "Best TTS models 2026") ranks
24 local models. Its local candidates at quality >= 7.5, as claimed:

| Claimed | Model | Langs | License claim | Note |
| --- | --- | --- | --- | --- |
| 8.5 | Higgs Audio v3 | 100 | non-commercial | heavy, research |
| 8.5 | Qwen3 TTS | 9 | Apache | weights availability to verify |
| 8.4 | "OmniVoice" | 646 | Apache | OpenVox's own; verify what it is |
| 8.3 | Fish Speech / OpenAudio | 13 | non-commercial | |
| 8.0 | Chatterbox | 23 | MIT | already spiked here, has Dutch |
| 8.0 | CosyVoice 3 | 9 | Apache | streaming |
| 8.0 | IndexTTS 2.5 | 4 | non-commercial | |
| 8.0 | Dia | 1 (en) | Apache | dialogue only |
| 8.0 | VibeVoice | 2 | MIT | long-form |
| 7.8 | Orpheus TTS | 8 | Apache/Llama | LLM-based |
| 7.6 | Spark-TTS | 2 | Apache | zh/en |
| 7.5 | StyleTTS 2 | 14 | MIT | Kokoro's ancestor |
| 7.5 | F5-TTS | 2 (+finetunes) | code MIT, weights NC | |
| 7.5 | GPT-SoVITS | 5 | MIT | |

Caveats: the article is vendor content (OpenVox tags its own supported
models, and its in-house "OmniVoice" lands at #2); its quality numbers
are not per-language, and multilingual models are routinely much weaker
outside English and Chinese. Everything below replaces these claims
with verified data.

## What verification did to the blog's claims

- "OmniVoice by OpenVox, 646 languages, Apache, 8.4" is three-quarters
  wrong. The model is real: k2-fsa/OmniVoice, from Daniel Povey's
  Next-gen Kaldi group (arXiv:2604.00688), genuinely 646 languages, and
  Dutch is in the list with 2,264 hours of training data. But OpenVox
  did not make it (they are a Mac app that bundles it), the 8.4 is
  OpenVox's own self-published score, and the weights are CC-BY-NC, not
  Apache (only the code is Apache-2.0). The audio tokenizer (from Higgs
  Audio) needed a separate license correction after a community report.
- Qwen3-TTS is genuinely open (Apache-2.0 weights on HF, 0.6B and 1.7B,
  released 2026-01-22) but supports 10 languages and Dutch is not one.
- Higgs Audio "8.5, 100 languages": v2 lists only en/zh/de/ko; the
  "100+ languages" claim belongs to v3, which has no published language
  list and a research/non-commercial license. Needs 24 GB+ GPU. Out.
- Fish Speech/OpenAudio: Dutch is confirmed on the S1/S1-mini model
  card, but the actual paper's training-data description never mentions
  Dutch, the weights are non-commercial, and CPU inference is broken in
  practice (documented core-underutilization issue).
- CosyVoice 3: the downloadable model is the 0.5B "Fun-CosyVoice3", not
  the 1.5B the paper's quality claims describe. 9 languages, no Dutch.

## Verified model matrix (Dutch-capable models only)

Every row verified from model cards, LICENSE files, papers or the
repos themselves. "CPU here" means a realistic path on this machine.

| Model | Langs | Weights license | Size | CPU here | Verdict |
| --- | --- | --- | --- | --- | --- |
| Chatterbox Multilingual V3 | 23 | MIT | 0.5B LM + decoder, 3.2 GB | RTF 2.4 measured; fixable (below) | lead candidate |
| Supertonic 3 (Supertone) | 31 | OpenRAIL-M, commercial OK | 99M, 398 MB ONNX | yes: RTF 0.36-0.73 measured here | listener: very good; front-runner |
| VoxCPM2 (OpenBMB) | 30 | Apache-2.0 | 2B | no: RTF 36-93 measured (torch CPU) | listener rejected; out |
| OmniVoice (k2-fsa) | 646 | CC-BY-NC (code Apache) | 0.6B | no: RTF 50-70 measured; XPU is the route | listener: very good; needs Arc XPU |
| OpenAudio S1-mini (Fish) | 13 | CC-BY-NC-SA | 0.5B | no (broken CPU path) | skip |
| ZONOS2 (Zyphra, 2026-06) | 34, nl Tier 2 | MIT or Apache (sources conflict) | 8B MoE, 15.3 GB | no, NVIDIA-only; 1/20 realtime on 8 GB GPU | skip on this machine |
| OuteTTS 1.0 1B | 23, nl high tier | CC-BY-NC-SA + Llama | 2.5 GB | yes, llama.cpp first-class | risky: arena report of altered/omitted words |
| XTTS v2 (Coqui/idiap) | 17 | CPML non-commercial, issuer defunct | ~467M, 2.1 GB | possible, slow, unverified | benchmark reference only |
| Parler mini multilingual v1.1 | 8 core | Apache-2.0 | 0.9B | untested, AR likely slow | curiosity: trained on CML-TTS |
| Voxtral TTS 4B (Mistral) | 9 | CC-BY-NC | 4B | no, 16 GB GPU required | quality reference (see below) |
| VibeVoice-Realtime-0.5B | ~11 voices | MIT | 0.5B | latency claim, hardware unstated | low priority, family quality middling |
| MMS-TTS-nld (Meta) | 1107 | CC-BY-NC | 36M VITS | trivially | quality too low |
| Piper nl (current stack) | ~45 | permissive | 20-60 MB | yes | the baseline to beat |

Verified as having NO Dutch, ruled out for the goal regardless of
quality: Kokoro (8), CosyVoice 3 (9), Qwen3-TTS (10), Higgs Audio v2
(4), IndexTTS 2/2.5 (en/zh + ja/es/ar), MeloTTS (6), Orpheus (en + 7
abandoned research langs), Zonos v0.1, MegaTTS3, ZipVoice, MaskGCT,
NeuTTS Air, Dia2, Step Audio EditX, Breeze TTS 2, NVIDIA Magpie, F5-TTS
base (en/zh; no Dutch finetune exists anywhere, verified gap).

Watch list: Kyutai Pocket TTS (100M, MIT, true real-time on 2 CPU
cores, 200 ms first audio; en/fr/de/es/pt/it today, added 5 languages
between January and May 2026, so Dutch may well come; training code is
open since 2026-08-25, which also makes it a finetune target).

## Quality evidence per language

The uncomfortable, well-sourced core finding: no open-weight model has
credible published evidence of 8/10 subjective quality in Dutch today.

- TTS Arena V2 is English-only by design ("English only, for now"), so
  every arena Elo the blog cites says nothing about Dutch. No Dutch
  arena exists (the one non-English precedent is an Arabic arena).
- The strongest controlled datapoint is Mistral's Voxtral TTS paper
  (arXiv:2603.25551): blind native-speaker preference vs ElevenLabs
  Flash v2.5 across 9 languages. Open model win rates: Spanish 87.8,
  German 72.0, Italian 57.1, French 54.4... and Dutch 49.4, the only
  language of the nine where the open model fails to beat ElevenLabs.
  Dutch is specifically the hard case, not just "another language".
- The only real Dutch metric in the primary literature is XTTS v2's
  (arXiv:2406.04904, Table 4): CER 0.946, speaker sim 0.4825, and Dutch
  is one of XTTS's better languages. Automatic proxies, not MOS.
- Chatterbox Multilingual has no technical report at all (3-person
  team, per their own HF discussion) and zero per-language quality
  numbers; community reports flag phoneme issues in Portuguese and
  Turkish, nothing published on Dutch either way.
- CosyVoice 3's own paper shows the usual gradient: Chinese/English
  best, Japanese/Korean roughly 2x their error rate, de/es/fr/it
  "good" tier. Qwen3-TTS's report shows the same pattern plus a
  community-reported Chinese accent bleeding into other languages.
- One genuine Dutch head-to-head exists, buried in Supertonic's README:
  per-language WER on the Minimax-MLS-test benchmark. Dutch: OmniVoice
  0.77, VoxCPM2 0.84, Supertonic 3 1.47 (English for scale: 2.02, 2.11,
  2.06). Intelligibility, not naturalness, and self-published by
  Supertone, but it says all three read Dutch accurately, which Piper's
  nl_NL demonstrably does not.
- Community mileage on Dutch exists only for Piper, and it is
  damning for nl_NL ("garbled rubbish", "unusable", 2023 through
  2026), while the two Flemish voices trained on small curated data
  (nathalie, rdh) are consistently rated the best of the open Dutch
  bunch, still "robotic". That asymmetry is the key finetuning lesson.
- For German, French, Spanish, Italian and Polish the aim of >8/10 is
  realistic with existing models (Voxtral's decisive wins, CosyVoice 3
  WER 2.7-3.9% there). For Dutch, nothing ships that today; getting
  there means either Chatterbox being better than its missing paperwork
  suggests (the listening test decides), or finetuning (below).

## Acceleration on this hardware

Findings from the OpenVINO/NPU/llama.cpp research pass, ranked by
leverage for the Chatterbox decoder (the RTF 1.9 blocker):

1. The single-step decoder is confirmed applicable, zero hardware
   needed. I inspected our exported conditional_decoder.onnx: the
   10-step CFM solver is unrolled inline (the same attention module
   appears as attn1 through attn1_9 in every one of the 12 mid
   blocks; ~21k of the graph's 24k nodes are the ten estimator
   passes, the HiFT vocoder is the small remainder). The Chatterbox
   repo ships Turbo/Nano variants with a 1-step decoder. Cutting 10
   steps to 1 removes roughly 85% of decoder compute: projected
   decoder RTF ~0.3, total ~0.75, real time on CPU alone. To verify:
   whether a single-step decoder exists for (or transfers to) the
   multilingual speech tokens, or whether we re-export from PyTorch
   with a distilled few-step schedule.
2. `pip install onnxruntime-openvino`, point the existing decoder ONNX
   at `OpenVINOExecutionProvider, device_type GPU, precision FP16`.
   Same-day experiment, proven on this model class: Kokoro-Intel got
   ~3x vs CPU on Iris Xe exactly this way. Expect 2-4x if no CPU
   fallback. I scanned our graph for the documented landmines: it
   contains 1 STFT and 58 ScatterND nodes (48 sprinkled through the
   unrolled solver, 10 in the vocoder source module), plus 2
   RandomNormalLike. So expect the partitioner to split around those;
   whether the big matmul/conv islands still land on GPU decides the
   win, and only the experiment answers that. Use OpenVINO >= 2025.2.
   Prerequisite: `omarchy-pkg-add intel-compute-runtime` (sudo).
3. Full IR conversion (`ov.convert_model`) targeting GPU FP16. The
   official OpenVINO notebooks repo has a CosyVoice 3 conversion
   notebook covering the same LLM + flow-matching + vocoder pipeline
   shape as Chatterbox (shared S3/CosyVoice lineage), which is the
   closest working template. Higher ceiling than 2, more work.
4. FP16 only. INT8 quantization of TTS decoders audibly distorts
   (MeloTTS team finding, they needed a DeepFilterNet cleanup pass).
   Our q4 LM is fine (tokens, not audio); keep the decoder at FP16.
5. llama.cpp SYCL on the Arc iGPU: low priority, the LM half already
   runs at RTF 0.45. Avoid the Vulkan backend on this GPU generation
   (documented crashes and gibberish on Arrow/Meteor Lake at 3B+).
6. The NPU is a dead end for the decoder. Static shapes are mandatory,
   the plugin is officially immature, intel-npu-acceleration-library
   was archived April 2025, and the one team that NPU-enabled a TTS
   pipeline (MeloTTS-OV) deliberately kept the decoder off the NPU.
   Independent LLM-on-NPU tests measured it slower than CPU. Revisit
   in a future OpenVINO release, after 1-3 are done.

Arithmetic: LM 0.45 + decoder 1.9 = 2.4 today. A 1-step decoder or a
2-4x GPU decoder brings the total under 1.0, i.e. faster than real
time, before any deeper work.

## Build vs adopt (the Dutch finetune path)

If no adopted model clears the bar, the data situation for building is
decent and the recipe is proven at small scale:

- CML-TTS Dutch: ~645 h, CC-BY-4.0, 24 kHz, 35 speakers, SNR-filtered
  and aligned specifically for TTS. The bulk-adaptation corpus.
- MLS Dutch: ~1,580 h, CC-BY-4.0, but raw audiobook narration. The
  Piper voice trained straight on it became the worst-rated Dutch
  voice in the ecosystem. Scale without curation demonstrably fails.
- Common Voice Dutch: 126 h validated, CC0, crowdsourced; diversity
  data, not voice data.
- Small curated single-speaker sets: CSS10 Dutch ~14 h, r-dh ~12 h
  Flemish, dataroots ~5 h studio Flemish, all open. This exact shape
  produced Piper's best-reviewed Dutch voices.
- CGN (~900-1,000 h) is license-gated and the wrong shape
  (conversational, mixed conditions). Not worth pursuing.

The recipe that matches all the evidence: bulk-adapt a strong
multilingual backbone on CML-TTS Dutch, then a final small finetune on
one clean single-speaker set to lock a target voice. That two-stage
split is precisely what separated the liked Flemish Piper voices from
the disliked large-data nl_NL ones.

Verified gap worth knowing: nobody has published a Dutch finetune of
any modern flow-matching model (F5-TTS has community finetunes for ~10
languages, Dutch absent). Existing Dutch checkpoints beyond Piper are
weak or unusable (MMS-nld non-commercial and low quality, a Tortoise
Dutch finetune "incomprehensible", an empty Parler Dutch card; one
YourTTS trained on CML-TTS exists, CC-BY-4.0, no quality data). No
Dutch or Belgian research institute has published an open TTS model
(Radboud, INT, KU Leuven, Ghent all checked: ASR only). Parkiet, the
one from-scratch native Dutch model, is now verified: a Dutch port of
Dia-1.6B, MIT code and OpenRAIL weights, but it needs 10-19 GB of
NVIDIA VRAM, so it cannot run here; its only quality evidence is the
author's own informal ElevenLabs comparison. Useful as a listening
reference and as proof Dutch training data suffices, not as a
deployable engine. Kyutai Pocket TTS releasing its training code
(August 2026) makes a CPU-native 100M model a realistic future
finetune target too.

## Listening verdict (2026-08-31, household, Dutch)

The spike samples got their first native listening pass:

- Supertonic 3: very good. Combined with measured real-time CPU
  synthesis, this is the front-runner for integration.
- OmniVoice: very good. Sound quality justifies the acceleration
  work; CPU is measured hopeless (RTF 50-70), so its path is the Arc
  iGPU via the officially supported PyTorch XPU backend.
- VoxCPM2: rejected on sound. Also measured RTF 36-93 on CPU. Out.
- Piper: "mid" for nl_NL; the Flemish nl_BE voices are better, which
  matches the community record. Stays the fallback tier, with nl_BE
  as the preferred Dutch voices while a successor lands.
- Chatterbox: no verdict given yet (samples nl-1/nl-2.wav).

## Measured performance on this machine (2026-08-31)

Protocol: idle machine, one engine at a time, the same three Dutch
texts (short sentence ~3 s, medium ~4 s, paragraph ~8 s of audio),
warm model unless noted. Piper and Supertonic report best of two
passes; the heavier engines a single pass. RTF below 1.0 is faster
than real time.

| Engine | Load | Peak RAM | RTF kort / middel / alinea |
| --- | --- | --- | --- |
| Piper nl_BE-nathalie | per call | 253 MB | 0.43 / 0.29 / 0.20 |
| Supertonic 3 (F1) | 1.0 s | 560 MB | 0.94 / 0.66 / 0.42 |
| Chatterbox q4 + fp32 decoder | 34 s | 2.0 GB | 3.19 / 2.81 / 2.46 |
| OmniVoice, 16 steps | 1.1 s | 2.9 GB | 40.4 / 45.0 / 13.8 |
| OmniVoice, 32 steps | 1.1 s | 2.9 GB | 65.7 (kort only) |
| OmniVoice XPU fp16, 32 steps | 2.2 s | 4.2 GB | 1.04 / 1.00 / 0.86 |
| OmniVoice XPU fp16, 16 steps | 2.2 s | 4.2 GB | 0.61 / 0.53 / 0.48 |
| VoxCPM2 (bf16 torch) | 370 s first run | ~5.9 GB | 93 / 41 / 36 |

Notes:
- Piper's wall time includes reloading the model every call (CLI); it
  stays the latency and footprint king.
- Supertonic is real time across the board with a 1 s cold start and
  a footprint the daemon can keep resident. Its SDK is not streaming,
  but at RTF < 1 sentence-level pipelining with the existing 1.5 s
  pre-buffer works as-is.
- Chatterbox splits as LM ~0.7 RTF, decoder ~1.7-2.4 RTF, confirming
  the decoder diagnosis. Applying the 1-step decoder arithmetic to
  the paragraph run projects roughly RTF 1.0, borderline real time on
  CPU before any iGPU work.
- OmniVoice on CPU is disqualified at any step count, but the Arc
  iGPU changes everything: after installing intel-compute-runtime and
  level-zero-loader (2026-08-31), PyTorch 2.13+xpu sees the iGPU (128
  EUs) and OmniVoice runs 25-75x faster than CPU, comfortably real
  time at 16 steps and borderline at 32. The 646-language engine is
  practical on this machine. XPU listening samples saved for a
  quality check against the CPU ones: ov-xpu-*.wav (32 steps, fp16)
  and ov-xpu16-*.wav (16 steps, fp16).
- VoxCPM2's first two spike sentences ran contended; the paragraph
  (RTF 36) was mostly solo. Rejected on sound anyway.

## Shortlist and spike plan

The bar is >8/10 per language. Updated after the listening verdict
and the on-machine measurements:

1. Supertonic 3 integration: DONE (2026-08-31). Runs as a shared
   worker subprocess behind omalexia-speakd (config/supertonic/
   worker.py, `omalexia voice install supertonic`, `omalexia voice
   engine LANG supertonic`), verified speaking Dutch through the
   daemon in real time. Upstream repo is frozen (archived); assets
   pinned locally.
2. OmniVoice integration: DONE (2026-08-31). XPU measured RTF
   0.48-0.61 at 16 steps, 0.86-1.04 at 32 (fp16, 4.2 GB resident);
   integrated as a worker engine with automatic device pick
   (xpu/cuda/cpu) and a voice-clone prompt (voice.pt) pinning one
   consistent voice across sentences; verified speaking Dutch through
   the daemon on the iGPU, warm utterances real time. Fallback ladder
   in the daemon: omnivoice -> supertonic -> piper. CC-BY-NC weights
   flag stands for any commercial future.
2b. Machine advisor: DONE. `omalexia-tts-advisor` (also `omalexia
   voice advise`) probes CPU/RAM/GPU/compute stack/NPU/disk and ranks
   the engines a machine can sustain, calibrated against this
   laptop's measurements, so weaker machines get Piper or Supertonic
   and GPU machines get OmniVoice.
3. Chatterbox: get the missing listening verdict (nl-1/nl-2.wav).
   Only if it wins on sound does the decoder acceleration work
   (single-step Turbo variant, then onnxruntime-openvino GPU FP16)
   stay on the roadmap; Supertonic being both good and fast lowers
   its priority.
4. Ruled out by listening or measurement: VoxCPM2 (sound + speed),
   OpenAudio S1 (broken CPU path), ZONOS2/Voxtral/Parkiet (hardware),
   OuteTTS (word-accuracy reports), MMS/XTTS (quality/license).
5. If no adopted engine clears 8 for Dutch: the CML-TTS +
   curated-voice finetune path, and watch Kyutai Pocket TTS (training
   code open since 2026-08-25, Dutch not yet shipped).
6. Rest of Europe: whatever wins for Dutch likely covers German,
   French, Spanish, Italian and Polish; verify per language with the
   same listening protocol instead of trusting tier labels.

## What omaspeak teaches (2026-09-20)

[omaspeak](https://github.com/jacob-vincent-mink/omaspeak) is a Rust
local-first TTS CLI/daemon built on the same engine we front for Dutch,
Supertonic 3. It confirms a few of our own choices (one warm model
session, a supervised worker that isolates native crashes, PipeWire
output, stop the player the moment the client exits) and it does NOT
stream: it synthesizes a whole utterance to a WAV, so our sentence
streaming plus first-sentence head split is ahead of it on latency.

The valuable part is its benchmark, on hardware almost identical to the
reference laptop (Intel Core Ultra, Arc iGPU, Intel NPU). Supertonic 3
through OpenVINO is far faster than through the CPU GGUF path, and the
iGPU and NPU are faster still (warm p50 synthesis / RTF):

| Backend           | Warm synth | RTF    |
| ---               | ---:       | ---:   |
| audio.cpp GGUF CPU| 1658 ms    | 0.442  |
| OpenVINO CPU      | 405 ms     | 0.103  |
| OpenVINO iGPU     | 135 ms     | 0.0344 |
| OpenVINO NPU      | 64 ms      | 0.0165 |

Two conclusions for Omalexia:

1. Run Supertonic through OpenVINO, not the CPU ONNX path we ship. On the
   iGPU that is roughly RTF 0.03 and ~135 ms warm; on the NPU ~64 ms.
   That would make Supertonic (already rated very good by ear) both the
   fast AND the high-quality default, and would drop time-to-first-audio
   to well under our current ~0.6 s even for the first sentence.
2. It reopens the NPU, which the 2026-08-24 speech investigation had
   written off. That conclusion was about Chatterbox's flow-matching
   decoder; Supertonic's ONNX graph runs on the NPU through OpenVINO very
   well (64 ms here). Worth a real spike.

Spike plan (needs the OpenVINO user-space, a ~400 MB one-time sudo
install already noted above): `pip install onnxruntime-openvino` in the
Supertonic venv (or convert to OpenVINO IR), point the Supertonic worker
at `OpenVINOExecutionProvider` with device GPU then NPU, FP16, and
re-run the on-machine RTF + listening protocol. If it holds, Supertonic
on the iGPU/NPU becomes the recommended default engine and the
`omalexia voice advise` ranking is updated to prefer it where OpenVINO
is present.
