#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# U integration retains the local release version; use CHIRPOS_DEVELOPMENT_BUILD=1 for candidates.
PRO_BUILD="${CHIRPOS_PRO_BUILD:-0}"
[[ "$PRO_BUILD" == 0 || "$PRO_BUILD" == 1 ]] || { printf 'CHIRPOS_PRO_BUILD must be 0 or 1\n' >&2; exit 1; }
DEVELOPMENT_BUILD="${CHIRPOS_DEVELOPMENT_BUILD:-0}"
[[ "$DEVELOPMENT_BUILD" == 0 || "$DEVELOPMENT_BUILD" == 1 ]] || { printf 'CHIRPOS_DEVELOPMENT_BUILD must be 0 or 1\n' >&2; exit 1; }
if [[ "$PRO_BUILD" == 1 ]]; then DEVELOPMENT_BUILD=1; fi
PRO_UPDATES="${CHIRPOS_PRO_UPDATES:-0}"
[[ "$PRO_UPDATES" == 0 || "$PRO_UPDATES" == 1 ]] || { printf 'CHIRPOS_PRO_UPDATES must be 0 or 1\n' >&2; exit 1; }
if [[ "$PRO_BUILD" == 1 ]]; then
    PRO_VERSION="$(cat "$ROOT/scripts/pro-version.txt")"
    # Base-100 components give 0.8.0 build 800; reject ambiguous/overflowing components.
    PRO_BUILD_NUMBER="$(python3 - "$PRO_VERSION" <<'PY'
import re
import sys
version = sys.argv[1]
if not re.fullmatch(r'(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)', version):
    sys.exit('Invalid Pro version: expected X.Y.Z (major <= 9999; minor/patch <= 99)')
major, minor, patch = map(int, version.split('.'))
number = major * 10000 + minor * 100 + patch
if number == 0:
    sys.exit('Pro build number must be positive')
print(number)
PY
)"
    # Public keys are always embedded when available; enabling updates requires one.
    PRO_PUBLIC_KEY="$(python3 - "$ROOT/config/pro-update-public-key.txt" "$PRO_UPDATES" <<'PY'
import base64
from pathlib import Path
import sys
path = Path(sys.argv[1])
if not path.is_file():
    if sys.argv[2] == '1':
        sys.exit('Pro updates require config/pro-update-public-key.txt')
    print('')
else:
    try:
        value = path.read_text(encoding='utf-8').strip()
        raw = base64.b64decode(value, validate=True)
        if len(raw) != 32 or base64.b64encode(raw).decode() != value:
            raise ValueError()
    except (ValueError, UnicodeError):
        sys.exit('Invalid Pro update public key: expected canonical base64 raw 32-byte key')
    print(value)
PY
)"
fi
swift build -c release
DEFAULT_APP="$ROOT/dist/ChirpOS.app"
if [[ "$PRO_BUILD" == 1 ]]; then DEFAULT_APP="$ROOT/dist/ChirpOS Pro.app"; fi
APP="${CHIRPOS_APP_PATH:-$DEFAULT_APP}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/Assets"
cp .build/release/Birding "$APP/Contents/MacOS/Birding.new"
mv -f "$APP/Contents/MacOS/Birding.new" "$APP/Contents/MacOS/Birding"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Birding</string>
<key>CFBundleIdentifier</key><string>dev.birding.desktop</string>
<key>CFBundleName</key><string>ChirpOS</string>
<key>CFBundleDisplayName</key><string>ChirpOS</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>60</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "$DEVELOPMENT_BUILD" == 1 ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.birding.desktop.development' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName ChirpOS Dev' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName ChirpOS Dev' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :ChirpOSDevelopmentBuild bool true' "$APP/Contents/Info.plist"
fi
if [[ "$PRO_BUILD" == 1 ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName ChirpOS Pro' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName ChirpOS Pro' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :ChirpOSProBuild bool true' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PRO_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PRO_BUILD_NUMBER" "$APP/Contents/Info.plist"
    UPDATES_ENABLED=false
    if [[ "$PRO_UPDATES" == 1 ]]; then UPDATES_ENABLED=true; fi
    /usr/libexec/PlistBuddy -c "Add :ChirpOSUpdatesEnabled bool $UPDATES_ENABLED" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :ChirpOSUpdatePublicKey string $PRO_PUBLIC_KEY" "$APP/Contents/Info.plist"
fi
"$ROOT/.build/release/Birding" --export-icon "$ROOT/Assets"
"$ROOT/.build/release/Birding" --export-icon "$ROOT/.build/AppIcon-macOS" --macos-mask
rm -rf "$APP/Contents/Resources/Birding_BirdingCore.bundle"
cp -R "$ROOT/.build/release/Birding_BirdingCore.bundle" "$APP/Contents/Resources/"
rm -f "$APP/Contents/Resources/stand.png" # Remove the unused legacy export from incremental builds.
ICONSET="$ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/.build/AppIcon-macOS/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/.build/AppIcon-macOS/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/.build/AppIcon.icns"
# A content-specific resource name avoids reusing Finder's stale icon cache.
ICON_HASH="$(shasum -a 256 "$ROOT/.build/AppIcon.icns" | cut -c 1-12)"
ICON_NAME="AppIcon-$ICON_HASH"
rm -f "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/"AppIcon-*.icns
cp "$ROOT/.build/AppIcon.icns" "$APP/Contents/Resources/$ICON_NAME.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $ICON_NAME" "$APP/Contents/Info.plist"
for language in en zh-Hans zh-Hant; do
    mkdir -p "$APP/Contents/Resources/$language.lproj"
    name="ChirpOS"
    if [[ "$language" != en ]]; then name="啾啾"; fi
    if [[ "$DEVELOPMENT_BUILD" == 1 ]]; then
        name="ChirpOS Dev"
        if [[ "$language" != en ]]; then name="啾啾测试版"; fi
    fi
    if [[ "$PRO_BUILD" == 1 ]]; then
        name="ChirpOS Pro"
        if [[ "$language" != en ]]; then name="啾啾 Pro"; fi
    fi
    printf '"CFBundleName" = "%s";\n"CFBundleDisplayName" = "%s";\n' "$name" "$name" > "$APP/Contents/Resources/$language.lproj/InfoPlist.strings"
done
if [[ -n "${CHIRPOS_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$CHIRPOS_SIGNING_IDENTITY" --options runtime --timestamp "$APP"
else
    codesign --force --sign - "$APP"
fi
touch "$APP"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then "$LSREGISTER" -f "$APP" || true; fi
printf 'Built: %s\n' "$APP"
