#!/bin/bash
# One-time installer for the LocalVoice speech engine (Kokoro-82M).
# Everything is stored in ~/Library/Application Support/LocalVoice.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME/Library/Application Support/LocalVoice"
ENGINE="$HOME_DIR/engine"
MODEL="$HOME_DIR/model"
VOICES="$HOME_DIR/voices"
BASE_URL="https://huggingface.co/hexgrad/Kokoro-82M/resolve/main"
VOICE_LIST=(af_heart af_bella am_michael am_fenrir bf_emma bm_george)

WORKER="$SCRIPT_DIR/../Resources/kokoro_worker.py"
if [ ! -f "$WORKER" ]; then
    WORKER="$SCRIPT_DIR/kokoro_worker.py"
fi
if [ ! -f "$WORKER" ]; then
    echo "error: kokoro_worker.py not found next to this installer." >&2
    exit 1
fi

mkdir -p "$MODEL" "$VOICES"

echo "==> LocalVoice setup"
echo "    engine: $ENGINE"
echo

if command -v uv >/dev/null 2>&1; then
    echo "==> Python 3.12 + uv environment"
    uv python install 3.12
    rm -rf "$ENGINE"
    uv venv --python 3.12 "$ENGINE"
    uv pip install --python "$ENGINE/bin/python" kokoro soundfile
    uv pip install --python "$ENGINE/bin/python" \
        "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
else
    PYTHON="$(command -v python3.12 || command -v python3.11 || true)"
    if [ -z "$PYTHON" ]; then
        echo "error: Python 3.12 not found. Install uv (brew install uv) or Python 3.12." >&2
        exit 1
    fi
    echo "==> Python environment ($PYTHON)"
    rm -rf "$ENGINE"
    if ! "$PYTHON" -m venv "$ENGINE"; then
        echo "error: could not create the virtual environment." >&2
        echo "       On macOS 26, Homebrew Python can be broken. Install uv instead:" >&2
        echo "       brew install uv" >&2
        exit 1
    fi
    "$ENGINE/bin/python" -m pip install --upgrade pip
    "$ENGINE/bin/python" -m pip install kokoro soundfile \
        "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
fi

echo
echo "==> Downloading Kokoro model (about 320 MB)"
if [ ! -f "$MODEL/kokoro-v1_0.pth" ]; then
    curl -L --fail --progress-bar -o "$MODEL/kokoro-v1_0.pth" "$BASE_URL/kokoro-v1_0.pth"
fi
if [ ! -f "$MODEL/config.json" ]; then
    curl -L --fail --progress-bar -o "$MODEL/config.json" "$BASE_URL/config.json"
fi

echo
echo "==> Downloading voices"
for voice in "${VOICE_LIST[@]}"; do
    if [ ! -f "$VOICES/$voice.pt" ]; then
        echo "    $voice"
        curl -sL --fail --max-time 180 -o "$VOICES/$voice.pt" "$BASE_URL/voices/$voice.pt"
    fi
done

echo
echo "==> Verifying engine"
"$ENGINE/bin/python" "$WORKER" --check

echo
echo "Done. LocalVoice is ready — no internet connection is needed from here on."
