"""OmniVoice worker for omalexia-speakd.

Runs inside ~/.local/share/omalexia/omnivoice/.venv (PyTorch with XPU, CUDA
or CPU backend), keeps the 0.6B model loaded and streams 24 kHz int16 PCM
per sentence. Real time needs a GPU: on this project's reference laptop the
Arc iGPU does RTF ~0.5 at 16 diffusion steps; CPU is 20-70x too slow.

A voice-clone prompt saved as voice.pt next to this script pins one
consistent voice; without it every utterance may pick a different voice.

stdin:  one JSON object per line: {"text", "voice", "speed", "lang", "steps"}
stdout: "ready RATE" on start; then, per request, 4-byte little-endian
        lengths followed by PCM bytes; a zero length marks the end.
"""

import json
import os
import sys
from pathlib import Path

import numpy as np
import torch
from omnivoice import OmniVoice, VoiceClonePrompt

RATE = 24000
CHUNK = 32768
HERE = Path(__file__).resolve().parent


def pick_device() -> str:
    forced = os.environ.get("OMALEXIA_OMNIVOICE_DEVICE")
    if forced:
        return forced
    if getattr(torch, "xpu", None) is not None and torch.xpu.is_available():
        return "xpu"
    if torch.cuda.is_available():
        return "cuda:0"
    return "cpu"


def write(data: bytes):
    sys.stdout.buffer.write(len(data).to_bytes(4, "little"))
    if data:
        sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def main():
    device = pick_device()
    dtype = torch.float32 if device == "cpu" else torch.float16
    if device == "cpu":
        print("omnivoice worker: no GPU backend available; CPU synthesis "
              "is far slower than real time", file=sys.stderr, flush=True)
    model = OmniVoice.from_pretrained("k2-fsa/OmniVoice", device_map=device, dtype=dtype)
    prompt = None
    voice_file = HERE / "voice.pt"
    if voice_file.exists():
        try:
            prompt = VoiceClonePrompt.load(str(voice_file))
        except Exception as exc:  # noqa: BLE001
            print(f"omnivoice worker: ignoring voice.pt: {exc}", file=sys.stderr, flush=True)
    print(f"omnivoice worker: {device} ({dtype})"
          + (" with pinned voice" if prompt else ""), file=sys.stderr, flush=True)
    sys.stdout.buffer.write(f"ready {RATE}\n".encode())
    sys.stdout.buffer.flush()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            kwargs = {
                "num_step": int(req.get("steps") or 16),
                "voice_clone_prompt": prompt,
            }
            speed = float(req.get("speed", 1.0))
            if abs(speed - 1.0) > 0.01:
                kwargs["speed"] = min(2.0, max(0.5, speed))
            try:
                audio = model.generate(text=req["text"], language=req.get("lang") or None, **kwargs)
            except ValueError:
                # Unknown language id: let the model infer it from the text.
                audio = model.generate(text=req["text"], language=None, **kwargs)
            pcm = (np.clip(np.asarray(audio[0]), -1.0, 1.0) * 32767).astype("<i2")
            for i in range(0, len(pcm), CHUNK):
                write(pcm[i:i + CHUNK].tobytes())
            write(b"")
        except Exception as exc:  # noqa: BLE001
            print(f"omnivoice worker: {exc}", file=sys.stderr, flush=True)
            write(b"")


if __name__ == "__main__":
    main()
