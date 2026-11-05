#!/bin/bash
# Builds LocalVoice, installs it to /Applications, and adds a Desktop shortcut.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/LocalVoice.app"
DEST="/Applications/LocalVoice.app"

"$ROOT/scripts/build_app.sh"

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "==> Creating Desktop shortcut"
ln -sfn "$DEST" "$HOME/Desktop/LocalVoice.app"

echo "==> Opening LocalVoice"
open "$DEST"
