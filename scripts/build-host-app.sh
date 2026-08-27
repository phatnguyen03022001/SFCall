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

IDENTITY="${SFCALL_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(
        /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
            | /usr/bin/sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
            | /usr/bin/head -n 1
    )"
fi

if [[ -z "$IDENTITY" ]]; then
    cat >&2 <<'EOF'
SFCall host packaging requires a stable Apple Development signing identity.
No suitable identity was found and ad-hoc signing is intentionally disabled because it breaks macOS TCC permission persistence across rebuilds.

Inspect available identities with:
  security find-identity -v -p codesigning

If you have multiple identities, select one explicitly:
  SFCALL_CODESIGN_IDENTITY='Apple Development: Name (TEAMID)' bash scripts/build-host-app.sh
EOF
    exit 2
fi

/usr/bin/plutil -lint "$APP/Contents/Info.plist"
printf 'SFCall host signing identity: %s\n' "$IDENTITY" >&2
/usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

SIGN_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)"
if printf '%s\n' "$SIGN_INFO" | /usr/bin/grep -q '^Signature=adhoc$'; then
    printf 'SFCall host signing failed: ad-hoc signature is not allowed for TCC-stable smoke testing.\n' >&2
    exit 3
fi

TEAM_ID="$(printf '%s\n' "$SIGN_INFO" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ -z "$TEAM_ID" || "$TEAM_ID" == "not set" ]]; then
    printf 'SFCall host signing failed: stable TeamIdentifier is missing.\n' >&2
    exit 3
fi

printf 'SFCall host signing team: %s\n' "$TEAM_ID" >&2
printf '%s\n' "$APP"
