"""Kokoro-82M worker for omalexia-speakd.

Runs inside ~/.local/share/omalexia/kokoro/.venv (Python 3.12 + kokoro-onnx),
keeps the model loaded and streams 24 kHz int16 PCM per sentence.

stdin:  one JSON object per line: {"text", "voice", "speed", "lang"}
stdout: for each sentence, a 4-byte little-endian length followed by PCM
        bytes; a zero length marks the end of the utterance.
"""

import asyncio
import json
import sys

import numpy as np
from kokoro_onnx import Kokoro

MODEL = "kokoro-v1.0.onnx"
VOICES = "voices-v1.0.bin"


def write(data: bytes):
    sys.stdout.buffer.write(len(data).to_bytes(4, "little"))
    if data:
        sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


async def synth(kokoro: Kokoro, req: dict):
    stream = kokoro.create_stream(
        req["text"],
        voice=req.get("voice", "af_heart"),
        speed=float(req.get("speed", 1.0)),
        lang=req.get("lang", "en-us"),
    )
    async for samples, _rate in stream:
        pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2").tobytes()
        write(pcm)
    write(b"")


def main():
    kokoro = Kokoro(MODEL, VOICES)
    sys.stdout.buffer.write(b"ready\n")
    sys.stdout.buffer.flush()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            asyncio.run(synth(kokoro, req))
        except Exception as exc:  # noqa: BLE001
            print(f"kokoro worker: {exc}", file=sys.stderr, flush=True)
            write(b"")


if __name__ == "__main__":
    main()
