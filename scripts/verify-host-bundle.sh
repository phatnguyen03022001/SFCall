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

SIGN_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)"
if printf '%s\n' "$SIGN_INFO" | /usr/bin/grep -q '^Signature=adhoc$'; then
    printf 'HOST_BUNDLE_VERIFY: FAIL — ad-hoc signing cannot preserve TCC identity across rebuilds\n' >&2
    exit 1
fi

TEAM_ID="$(printf '%s\n' "$SIGN_INFO" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ -z "$TEAM_ID" || "$TEAM_ID" == "not set" ]]; then
    printf 'HOST_BUNDLE_VERIFY: FAIL — stable signing TeamIdentifier is missing\n' >&2
    exit 1
fi

DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -dr - "$APP" 2>&1)"
test -n "$DESIGNATED_REQUIREMENT"

printf 'HOST_SIGNING_TEAM: %s\n' "$TEAM_ID"
printf 'HOST_DESIGNATED_REQUIREMENT: %s\n' "$DESIGNATED_REQUIREMENT"
printf 'HOST_BUNDLE_VERIFY: PASS\n'
