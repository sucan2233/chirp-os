#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CHIRPOS_PRO_BUILD=1 CHIRPOS_DEVELOPMENT_BUILD=1
# This local test package deliberately uses ad-hoc signing and no upstream updater.
export CHIRPOS_SIGNING_IDENTITY=''
export CHIRPOS_APP_PATH="$ROOT/dist/ChirpOS Pro.app"
bash "$ROOT/scripts/build.sh"
APP="$CHIRPOS_APP_PATH"
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(uname -m)
OUTPUT="$ROOT/dist/pro"
NAME="ChirpOS-Pro-$VERSION-macOS-$ARCH"
mkdir -p "$OUTPUT"
STAGING=$(mktemp -d "$ROOT/.build/pro-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/ChirpOS Pro.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/安装说明.txt" <<'INFO'
啾啾 Pro / ChirpOS Pro — macOS 本地测试版

1. 先从菜单退出正在运行的啾啾 / ChirpOS / ChirpOS Dev。
2. 将 ChirpOS Pro.app 拖到 Applications（应用程序）。
3. 从应用程序打开“啾啾 Pro”，在菜单栏鸟图标中进入鸟种设置或观鸟手册。

包含 M8 与 E0–E5：100 种鸟的增强基础姿态与特色动作。
沿用原本地测试版的设置与观鸟数据；请勿与旧版同时运行。
上游新增鸟可能保留 0% 出现概率，可在鸟种设置中调整。
采用本机临时签名，未进行 Apple 公证；上游自动更新已停用。
M9 未开发，真实窗口跟随、菜单暂停/恢复、睡眠唤醒及外接屏仍有未验项目。
INFO
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$NAME.zip"
hdiutil create -quiet -ov -format UDZO -volname 'ChirpOS Pro' -srcfolder "$STAGING" "$OUTPUT/$NAME.dmg"
hdiutil verify "$OUTPUT/$NAME.dmg"
cp "$STAGING/安装说明.txt" "$OUTPUT/安装说明.txt"
(
    cd "$OUTPUT"
    shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt
)
{
    printf 'Product: ChirpOS Pro / 啾啾 Pro\nVersion: %s\nArchitecture: %s\n' "$VERSION" "$ARCH"
    printf 'Source commit: %s\n' "$(git rev-parse HEAD)"
    printf 'Source branch: %s\n' "$(git branch --show-current)"
    if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
        printf 'Source tree: modified\n'
    else
        printf 'Source tree: clean\n'
    fi
    printf 'Signing: ad-hoc; notarization: none; update channel: local only\n'
} > "$OUTPUT/BUILD-INFO.txt"
printf 'Pro installation packages: %s\n' "$OUTPUT"
