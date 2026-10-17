#!/usr/bin/env bash
# Build the Invita Studio Flutter web app inside Vercel's build container.
# Vercel does not ship Flutter, so it is cloned on demand and reused if the
# build cache keeps it around.
set -euo pipefail

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_DIR="${FLUTTER_DIR:-$PWD/.flutter}"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Cloning Flutter ($FLUTTER_CHANNEL) into $FLUTTER_DIR ..."
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_CHANNEL" "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
export CI=true

flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version
flutter pub get
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run -O1

echo "Web build ready in build/web"
