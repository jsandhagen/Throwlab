#!/bin/bash
# Puts a Flutter SDK and this project's packages in place, so `flutter test`,
# `flutter analyze` and the preview harness under tool/preview all work in a
# Claude Code on the web session. The container is cached once this finishes,
# so later sessions find the SDK already here and skip the download.
set -euo pipefail

# A local machine has its own Flutter; this is only for the web sandbox.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# CI (.github/workflows/build-apk.yml) builds on the stable channel, whatever
# is latest that day. Pinning here is what keeps a session reproducible —
# bump it when stable has moved far enough to matter.
FLUTTER_VERSION="3.35.7"
FLUTTER_HOME="$HOME/flutter"
ARCHIVE="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "session-start: installing Flutter $FLUTTER_VERSION into $FLUTTER_HOME"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/flutter.tar.xz" "$ARCHIVE"
  tar xf "$tmp/flutter.tar.xz" -C "$tmp"
  rm -rf "$FLUTTER_HOME"
  mv "$tmp/flutter" "$FLUTTER_HOME"
  rm -rf "$tmp"
fi

# The SDK reads its own git checkout to work out its version. Unpacked by
# root into root's home it looks like someone else's repository, and every
# flutter command then dies on "detected dubious ownership".
git config --global --add safe.directory "$FLUTTER_HOME"

export PATH="$FLUTTER_HOME/bin:$PATH"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Nothing here can answer a prompt, and the spinners only make the logs
# harder to read.
flutter config --no-cli-animations >/dev/null 2>&1 || true
flutter --disable-telemetry >/dev/null 2>&1 || true

# The engine and the Material icon font: the font is what stops every glyph
# in a tool/preview PNG painting as a filled box.
flutter precache --universal

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
flutter pub get

echo "session-start: ready — $(flutter --version | head -1)"
