#!/bin/zsh
# Builds Glide.app, signs it, and (with --install) replaces /Applications/Glide.app.
# Signing with the same Apple Development identity every time keeps the
# Accessibility permission across rebuilds; ad-hoc signing would reset it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer full Xcode when it is installed; Command Line Tools also build fine.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
IDENTITY="${GLIDE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
APP="build/Glide.app"

[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources/AppIcon.icns

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Glide"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glide"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "No Apple Development identity found; signing ad-hoc (permission resets each build)." >&2
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'tell application id "dev.waveflow.Glide" to quit' 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Glide.app
  cp -R "$APP" /Applications/Glide.app
  open /Applications/Glide.app
  echo "Installed /Applications/Glide.app"
fi
