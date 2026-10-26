#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE=local
case "${1:-}" in
    '') [[ $# == 0 ]] || { echo 'Unexpected empty argument' >&2; exit 2; } ;;
    --release) [[ $# == 1 ]] || { echo 'Usage: scripts/package-pro-macos.sh [--release]' >&2; exit 2; }; MODE=release ;;
    *) echo 'Usage: scripts/package-pro-macos.sh [--release]' >&2; exit 2 ;;
esac
VERSION="$(cat "$ROOT/scripts/pro-version.txt")"
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$ || "$VERSION" == 0.0.0 ]]; then
    echo 'Invalid Pro version: expected X.Y.Z (major <= 9999; minor/patch <= 99)' >&2
    exit 1
fi
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "pro-v$VERSION" ]]; then
    echo 'RELEASE_TAG must match scripts/pro-version.txt exactly' >&2
    exit 1
fi
export CHIRPOS_PRO_BUILD=1 CHIRPOS_DEVELOPMENT_BUILD=1
# Pro uses ad-hoc codesigning in both modes; Ed25519 authenticates update ZIPs.
export CHIRPOS_SIGNING_IDENTITY=''
export CHIRPOS_PRO_UPDATES=0
export CHIRPOS_APP_PATH="$ROOT/dist/ChirpOS Pro.app"
OUTPUT="$ROOT/dist/pro"
PUBLIC_KEY="$ROOT/config/pro-update-public-key.txt"
if [[ "$MODE" == release ]]; then
    PRIVATE_KEY="${CHIRPOS_UPDATE_PRIVATE_KEY_FILE:-$ROOT/.local/pro-update-private-key}"
    swift "$ROOT/scripts/pro-update-sign.swift" check-key "$PRIVATE_KEY" "$PUBLIC_KEY"
    export CHIRPOS_PRO_UPDATES=1
    OUTPUT="$ROOT/dist/pro-release"
fi
bash "$ROOT/scripts/build.sh"
APP="$CHIRPOS_APP_PATH"
codesign --verify --deep --strict "$APP"
python3 - "$APP/Contents/Info.plist" "$VERSION" "$CHIRPOS_PRO_UPDATES" "$PUBLIC_KEY" <<'PY'
import plistlib
from pathlib import Path
import sys
with open(sys.argv[1], 'rb') as f:
    info = plistlib.load(f)
expected = {
    'CFBundleShortVersionString': sys.argv[2],
    'CFBundleIdentifier': 'dev.birding.desktop.development',
    'ChirpOSDevelopmentBuild': True,
    'ChirpOSProBuild': True,
    'ChirpOSUpdatesEnabled': sys.argv[3] == '1',
}
for name, value in expected.items():
    if info.get(name) != value or type(info.get(name)) is not type(value):
        sys.exit(f'Incorrect built bundle metadata: {name}')
if sys.argv[3] == '1' and info.get('ChirpOSUpdatePublicKey') != Path(sys.argv[4]).read_text().strip():
    sys.exit('Built bundle update public key does not match tracked key')
PY
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported host architecture: $ARCH" >&2; exit 1 ;; esac
# Label assets from the actual executable, and fail if the runner/binary disagree.
BINARY_ARCHS="$(lipo -archs "$APP/Contents/MacOS/Birding")"
if [[ "$BINARY_ARCHS" != "$ARCH" ]]; then
    printf 'Expected native %s binary; lipo reported %s\n' "$ARCH" "$BINARY_ARCHS" >&2
    exit 1
fi
NAME="ChirpOS-Pro-$VERSION-macOS-$ARCH"
mkdir -p "$OUTPUT"
STAGING=$(mktemp -d "$ROOT/.build/pro-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/ChirpOS Pro.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/安装说明.txt" <<'INFO'
啾啾 Pro / ChirpOS Pro — macOS

1. 先从菜单退出正在运行的啾啾 / ChirpOS / ChirpOS Dev。
2. 将 ChirpOS Pro.app 拖到 Applications（应用程序）。
3. 从应用程序打开“啾啾 Pro”，在菜单栏鸟图标中进入鸟种设置或观鸟手册。
4. 首次安装可能被 Gatekeeper 阻止：在系统设置 → 隐私与安全性中核对来源后选择“仍要打开”，按系统提示确认。

包含 M8 与 E0–E5：100 种鸟的增强基础姿态与特色动作。
沿用原本地测试版的设置与观鸟数据；请勿与旧版同时运行。
概率 V2 为全部 100 种鸟预设正的相对权重，默认均可出现。
仅勾选“手动调整概率”后显示权重编辑，可重置为系统默认值；保存后生效。
旧版概率配置迁移为系统默认权重，首次保存前备份旧文件，其他偏好保留。
采用 ad-hoc 签名，没有 Apple Developer ID 证书，未进行 Apple 公证。
Ed25519 更新签名用于验证 Pro 更新包，与 Apple 签名、公证及首次安装许可相互独立。
保留 macOS 下载隔离属性；安装脚本不会移除 quarantine。
INFO
if [[ "$MODE" == release ]]; then
    printf '\n此发布版已启用 Pro 更新；更新必须同时通过 GitHub SHA-256 与独立 Ed25519 签名验证。\n' >> "$STAGING/安装说明.txt"
else
    printf '\n此本地测试包默认关闭 Pro 更新，不应作为 GitHub 更新资产发布。\n' >> "$STAGING/安装说明.txt"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$NAME.zip"
if [[ "$MODE" == release ]]; then
    swift "$ROOT/scripts/pro-update-sign.swift" sign "$OUTPUT/$NAME.zip" "$VERSION" "$PRIVATE_KEY" "$PUBLIC_KEY"
    swift "$ROOT/scripts/pro-update-sign.swift" verify "$OUTPUT/$NAME.zip" "$VERSION" "$PUBLIC_KEY"
fi
hdiutil create -quiet -ov -format UDZO -volname 'ChirpOS Pro' -srcfolder "$STAGING" "$OUTPUT/$NAME.dmg"
hdiutil verify "$OUTPUT/$NAME.dmg"
cp "$STAGING/安装说明.txt" "$OUTPUT/安装说明.txt"
(
    cd "$OUTPUT"
    if [[ "$MODE" == release ]]; then
        shasum -a 256 "$NAME.zip" "$NAME.zip.sig" "$NAME.dmg" > SHA256SUMS.txt
    else
        shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt
    fi
)
{
    printf 'Product: ChirpOS Pro / 啾啾 Pro\nVersion: %s\nArchitecture: %s\n' "$VERSION" "$ARCH"
    printf 'Source commit: %s\n' "$(git rev-parse HEAD)"
    printf 'Source branch: %s\n' "$(git branch --show-current)"
    printf 'Source tag: %s\n' "${RELEASE_TAG:-not specified (local package)}"
    if [[ -n "${RELEASE_TAG:-}" ]]; then
        printf 'Source tag commit: %s\n' "$(git rev-parse --verify "refs/tags/$RELEASE_TAG^{commit}")"
    fi
    if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
        printf 'Source tree: modified\n'
    else
        printf 'Source tree: clean\n'
    fi
    printf 'Bundle ID: dev.birding.desktop.development; development flag: true\n'
    printf 'Bundle build: %s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
    printf 'Signing: ad-hoc; Apple Developer ID: none; notarization: none\n'
    printf 'Pro updates enabled: %s\n' "$CHIRPOS_PRO_UPDATES"
    if [[ "$MODE" == release ]]; then
        printf 'Update authentication: Ed25519; signature: %s.zip.sig\n' "$NAME"
        printf 'Update public key: %s\n' "$(cat "$PUBLIC_KEY")"
        printf 'Canonical payload: ChirpOS Pro Update v1\\nVERSION\\nZIP_BASENAME\\nBYTES\\nLOWERCASE_SHA256\\n (UTF-8)\n'
        printf 'Release notes: docs/releases/pro-v%s.md\n' "$VERSION"
    else
        printf 'Update authentication: disabled (local testing package)\n'
    fi
    printf 'Quarantine: preserved; first installation may require approval in macOS Privacy & Security\n'
} > "$OUTPUT/BUILD-INFO.txt"
printf 'Pro installation packages: %s\n' "$OUTPUT"
