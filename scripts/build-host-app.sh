#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcrun swift build --product SFCallHost
BIN_DIR="$(xcrun swift build --show-bin-path)"
APP="$ROOT/.build/SFCallHost.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/SFCallHost" "$APP/Contents/MacOS/SFCallHost"
cp "$ROOT/Host/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/SFCallHost"

/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

printf '%s\n' "$APP"
