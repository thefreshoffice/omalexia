"""Supertonic 3 worker for omalexia-speakd.

Runs inside ~/.local/share/omalexia/supertonic/.venv, keeps the 99M ONNX
model loaded and streams int16 PCM per sentence. Real time on modest CPUs.

stdin:  one JSON object per line: {"text", "voice", "speed", "lang"}
stdout: "ready RATE" on start; then, per request, 4-byte little-endian
        lengths followed by PCM bytes; a zero length marks the end.
"""

import json
import sys

import numpy as np
from supertonic import TTS

CHUNK = 32768  # samples per stdout chunk


def write(data: bytes):
    sys.stdout.buffer.write(len(data).to_bytes(4, "little"))
    if data:
        sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def main():
    tts = TTS(auto_download=True)
    styles: dict[str, object] = {}
    sys.stdout.buffer.write(f"ready {tts.sample_rate}\n".encode())
    sys.stdout.buffer.flush()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            voice = req.get("voice") or "F1"
            style = styles.get(voice)
            if style is None:
                style = styles[voice] = tts.get_voice_style(voice_name=voice)
            # The SDK's natural pace is 1.05; map the daemon's 1.0 onto it.
            speed = min(2.0, max(0.5, float(req.get("speed", 1.0)))) * 1.05
            wav, _duration = tts.synthesize(
                req["text"], voice_style=style, speed=speed,
                lang=req.get("lang") or None)
            pcm = (np.clip(wav[0], -1.0, 1.0) * 32767).astype("<i2")
            for i in range(0, len(pcm), CHUNK):
                write(pcm[i:i + CHUNK].tobytes())
            write(b"")
        except Exception as exc:  # noqa: BLE001
            print(f"supertonic worker: {exc}", file=sys.stderr, flush=True)
            write(b"")


if __name__ == "__main__":
    main()
