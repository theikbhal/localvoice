#!/usr/bin/env python3
"""LocalVoice Kokoro worker.

Speaks a simple JSON-lines protocol over stdin/stdout so the Swift UI can keep
the model warm between generations.

Request:  {"id": 1, "text": "...", "voice": "af_heart", "speed": 1.0, "out": "/tmp/a.wav"}
Response: {"id": 1, "event": "done", "out": "/tmp/a.wav", "duration": 3.42}
"""

import argparse
import json
import os
import sys
import traceback

SAMPLE_RATE = 24000
REPO_ID = "hexgrad/Kokoro-82M"
HOME = os.path.expanduser("~/Library/Application Support/LocalVoice")
MODEL_DIR = os.path.join(HOME, "model")
VOICE_DIR = os.path.join(HOME, "voices")
VOICES = (
    "af_heart",
    "af_bella",
    "am_michael",
    "am_fenrir",
    "bf_emma",
    "bm_george",
)


def log(message):
    print(message, file=sys.stderr, flush=True)


def emit(payload):
    print(json.dumps(payload), flush=True)


def language_for(voice):
    return "b" if voice.startswith(("bf_", "bm_")) else "a"


class Engine:
    def __init__(self):
        self.model = None
        self.pipelines = {}

    def k_model(self):
        if self.model is None:
            from kokoro import KModel

            config = os.path.join(MODEL_DIR, "config.json")
            weights = os.path.join(MODEL_DIR, "kokoro-v1_0.pth")
            if not (os.path.exists(config) and os.path.exists(weights)):
                raise FileNotFoundError(
                    "Kokoro model is missing. Run scripts/setup_engine.sh first."
                )
            log("loading Kokoro model")
            self.model = KModel(
                repo_id=REPO_ID, config=config, model=weights
            ).eval()

        return self.model

    def pipeline(self, lang):
        if lang not in self.pipelines:
            from kokoro import KPipeline

            log(f"loading pipeline ({lang})")
            self.pipelines[lang] = KPipeline(
                lang_code=lang, model=self.k_model(), repo_id=REPO_ID
            )

        return self.pipelines[lang]

    def voice(self, voice):
        path = os.path.join(VOICE_DIR, f"{voice}.pt")
        return path if os.path.exists(path) else voice

    def synthesize(self, request):
        import numpy as np
        import soundfile as sf

        text = (request.get("text") or "").strip()
        if not text:
            raise ValueError("Text is empty.")

        voice = request.get("voice") or "af_heart"
        speed = float(request.get("speed") or 1.0)
        out = request["out"]

        pipeline = self.pipeline(language_for(voice))
        chunks = []
        for _, _, audio in pipeline(
            text, voice=self.voice(voice), speed=speed, split_pattern=r"\n+"
        ):
            chunks.append(audio.detach().cpu().numpy())

        if not chunks:
            raise RuntimeError("Kokoro returned no audio for this text.")

        samples = np.concatenate(chunks).astype("float32")
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        sf.write(out, samples, SAMPLE_RATE)
        return {"duration": len(samples) / SAMPLE_RATE}


def check(engine):
    missing = [
        path
        for path in [
            os.path.join(MODEL_DIR, "config.json"),
            os.path.join(MODEL_DIR, "kokoro-v1_0.pth"),
        ]
        if not os.path.exists(path)
    ]
    missing += [
        os.path.join(VOICE_DIR, f"{voice}.pt")
        for voice in VOICES
        if not os.path.exists(os.path.join(VOICE_DIR, f"{voice}.pt"))
    ]
    if missing:
        for path in missing:
            log(f"missing: {path}")
        raise SystemExit(1)

    engine.pipeline("a")
    engine.pipeline("b")
    print("engine OK", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    engine = Engine()
    if args.check:
        check(engine)
        return

    emit({"event": "ready"})

    # Warm the default English pipeline while the user is typing.
    try:
        engine.pipeline("a")
        emit({"event": "warm"})
    except Exception:
        log(traceback.format_exc())

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if line == "quit":
            break

        try:
            request = json.loads(line)
        except json.JSONDecodeError as error:
            emit({"event": "error", "message": f"Bad request: {error}"})
            continue

        request_id = request.get("id")
        try:
            result = engine.synthesize(request)
            emit({"id": request_id, "event": "done", **result, "out": request["out"]})
        except Exception as error:
            log(traceback.format_exc())
            emit({"id": request_id, "event": "error", "message": str(error)})


if __name__ == "__main__":
    main()
