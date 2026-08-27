#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$(bash scripts/build-host-app.sh | tail -1)"
EXPECTED="$ROOT/.build/SFCallHost.app"

test "$APP" = "$EXPECTED"
test -x "$APP/Contents/MacOS/SFCallHost"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
test "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = "com.sfcall.host"

for key in \
    NSMicrophoneUsageDescription \
    NSSpeechRecognitionUsageDescription \
    NSScreenCaptureUsageDescription \
    NSAudioCaptureUsageDescription
do
    value="$(/usr/bin/plutil -extract "$key" raw "$APP/Contents/Info.plist")"
    compact="$(printf '%s' "$value" | tr -d '[:space:]')"
    test -n "$compact"
done

/usr/bin/codesign --verify --deep --strict "$APP"
printf 'HOST_BUNDLE_VERIFY: PASS\n'
