# LocalVoice

A free, private text-to-speech Mac app. Type English text, pick a voice, and get
natural speech — generated entirely on your Mac. No API keys, no accounts, no
usage limits, no cloud.

Built for a **Mac mini M4 with 16 GB RAM**, but it runs on any Apple Silicon Mac
with macOS 14 or newer.

Powered by [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (Apache-2.0).

---

## Why this exists

ElevenLabs is excellent, but it is a paid cloud service. This project is a
local-first alternative for the common case: **English text in, natural voice
out**. It is not a clone and does not do voice cloning — it gives you a clean,
native Mac app with six built-in voices and zero cost.

### Open-source TTS options compared

| Engine | License | Model size | RAM | Voice cloning | Notes |
| --- | --- | --- | --- | --- | --- |
| **Kokoro-82M** (this app) | Apache-2.0 | ~330 MB | ~1.5 GB | No | Best quality-per-byte; very fast on CPU; 50+ voices |
| [Piper](https://github.com/rhasspy/piper) | MIT | 20–100 MB | < 512 MB | No | Extremely fast, clearly synthetic |
| [Chatterbox](https://github.com/resemble-ai/chatterbox) | MIT | ~2 GB | ~4 GB | Yes | Great quality and cloning, slower on CPU |
| [XTTS-v2](https://huggingface.co/coqui/XTTS-v2) | CPML (non-commercial) | ~2 GB | ~4 GB | Yes | Good cloning, restricted license |
| [Dia-1.6B](https://github.com/nari-labs/dia) | Apache-2.0 | ~3 GB | ~6 GB | No | Dialogue-style, heavy for 16 GB Macs |

Kokoro wins here because it sounds close to paid services, runs comfortably in
16 GB, and is genuinely free for commercial use.

## Features

- Native SwiftUI app, no Electron
- Six voices: American and British, female and male
- Adjustable speaking speed (0.70x – 1.40x)
- Playback with seek bar, save to WAV, reveal in Finder
- Fully offline after one-time setup
- Persistent engine process: the model stays warm, so repeat generations are fast
- ⌘↵ to generate

## Requirements

- macOS 14+ (tested on macOS 26.2)
- Apple Silicon (tested on M4; Intel may work but is not tested)
- 16 GB RAM recommended
- ~2.5 GB disk for the Python environment and model
- Internet needed once, for setup

## Install

```bash
git clone https://github.com/theikbhal/localvoice.git
cd localvoice

# One-time: installs Python 3.12, Kokoro, and downloads the model + voices (~350 MB)
./scripts/setup_engine.sh

# Build, copy to /Applications, and add a Desktop shortcut
./scripts/install.sh
```

If you prefer to build without installing:

```bash
./scripts/build_app.sh
open build/LocalVoice.app
```

The setup script uses [uv](https://github.com/astral-sh/uv) when available
(`brew install uv`). On macOS 26, Homebrew's Python 3.12 can be broken by the
system libexpat update; uv's standalone Python avoids that.

## Usage

1. Type or paste English text.
2. Choose a voice and speed.
3. Press **Generate** (or ⌘↵).
4. Play it, or **Save** the WAV.

Voices included:

| ID | Name | Accent | Gender |
| --- | --- | --- | --- |
| `af_heart` | Heart | American | Female |
| `af_bella` | Bella | American | Female |
| `am_michael` | Michael | American | Male |
| `am_fenrir` | Fenrir | American | Male |
| `bf_emma` | Emma | British | Female |
| `bm_george` | George | British | Male |

## Performance (Mac mini M4, 16 GB)

- First launch: ~4–6 s to load the model
- After warm-up: roughly **0.5–0.9 s per short sentence**
- About **4–5x faster than real time** on CPU
- Audio: 24 kHz mono WAV

## How it works

The SwiftUI app launches `Resources/kokoro_worker.py` once and talks to it over
newline-delimited JSON on stdin/stdout. The worker loads Kokoro from local files
in `~/Library/Application Support/LocalVoice` and returns the path of a rendered
WAV file, which the app plays with `AVAudioPlayer`.

```
Sources/LocalVoice/     SwiftUI UI, engine bridge, playback
Resources/              Kokoro worker + app icon
scripts/                setup, build, install
```

Engine files are stored outside the app bundle so the app can be replaced
without re-downloading the model:

```
~/Library/Application Support/LocalVoice/
├── engine/          Python 3.12 virtualenv (kokoro, torch, spaCy)
├── model/           kokoro-v1_0.pth + config.json
├── voices/          six voice packs
└── wav/             generated audio (safe to delete)
```

## Uninstall

```bash
rm -rf /Applications/LocalVoice.app ~/Desktop/LocalVoice.app
rm -rf ~/Library/Application\ Support/LocalVoice
```

## Troubleshooting

**The app says the engine is not installed.** Run `./scripts/setup_engine.sh`,
or click **Install Engine** in the app's footer to run the bundled installer in
Terminal.

**Setup fails while creating the Python environment.** Install uv
(`brew install uv`) and re-run setup. macOS 26's libexpat change breaks some
Homebrew Python builds.

**macOS blocks the app on another Mac.** The build is ad-hoc signed, not
notarized. Right-click the app and choose **Open** the first time.

## Credits & license

- App code: MIT © 2026 Shaik Ikbhal Basha
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) by hexgrad — Apache-2.0
- [kokoro](https://pypi.org/project/kokoro/), [misaki](https://github.com/hexgrad/misaki), PyTorch, spaCy

Not affiliated with ElevenLabs. "ElevenLabs" is a trademark of its owner.
