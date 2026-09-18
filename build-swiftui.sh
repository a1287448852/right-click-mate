#!/bin/bash
# SwiftUI 版构建脚本。
#
# 和 build.sh 的区别：这个用 Xcode 里的工具链编译，因为 SwiftUI 的 @State / @Namespace
# 是编译器宏，实现（SwiftUIMacros 插件）只在 Xcode 里，命令行工具不带。
#
# 不改全局 xcode-select，直接用 Xcode 工具链的绝对路径，所以不需要 sudo。
#
# 用法：./build-swiftui.sh [install]

set -euo pipefail

DEVELOPER="/Applications/Xcode.app/Contents/Developer"
TOOLCHAIN="$DEVELOPER/Toolchains/XcodeDefault.xctoolchain"
SWIFTC="$TOOLCHAIN/usr/bin/swiftc"
SDK="$DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
PLUGINS="$TOOLCHAIN/usr/lib/swift/host/plugins"

if [[ ! -x "$SWIFTC" ]]; then
	echo "找不到 Xcode 工具链：$SWIFTC"
	echo "先装 Xcode（App Store 搜 Xcode，约 7GB），装完再跑这个脚本。"
	exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build-swiftui"
APP="$BUILD/右键伴侣.app"
APPEX="$APP/Contents/PlugIns/SuperRightClickFinderSync.appex"
TARGET="arm64-apple-macosx27.0"
EXT_ID="com.local.SuperRightClick.FinderSync"
INSTALLED="/Applications/右键伴侣.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

echo "[1/5] 编译 Finder 扩展（AppKit，扩展不能用 SwiftUI）"
"$SWIFTC" -parse-as-library -O -module-name SuperRightClickFinderSync \
	-sdk "$SDK" -target "$TARGET" \
	-framework Cocoa -framework FinderSync \
	-Xlinker -e -Xlinker _NSExtensionMain \
	-o "$APPEX/Contents/MacOS/SuperRightClickFinderSync" \
	"$ROOT/Sources/Config.swift" "$ROOT/Sources/ImageTools.swift" "$ROOT/Sources/FinderSync.swift"

echo "[2/5] 编译 SwiftUI 主 App"
"$SWIFTC" -parse-as-library -O -sdk "$SDK" -target "$TARGET" \
	-framework FinderSync \
	-o "$APP/Contents/MacOS/SuperRightClick" \
	"$ROOT/Sources/Config.swift" \
	"$ROOT/Sources/SwiftUI/SettingsView.swift"

echo "[3/5] 生成图标"
swift "$ROOT/tools/make-icon.swift" "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "[4/5] 写入 Info.plist"
cp "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Extension-Info.plist" "$APPEX/Contents/Info.plist"

echo "[5/5] ad-hoc 签名（先内后外）"
codesign --force --sign - --timestamp=none \
	--entitlements "$ROOT/Resources/Extension.entitlements" "$APPEX"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP" && echo "签名校验通过"

if [[ "${1:-}" == "install" ]]; then
	echo "[install] 安装到 /Applications"
	rm -rf "$INSTALLED"
	cp -R "$APP" /Applications/
	LSREGISTER="$DEVELOPER/../SharedFrameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
	[[ -x "$LSREGISTER" ]] || LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
	"$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
	sleep 1
	pluginkit -a "$INSTALLED/Contents/PlugIns/SuperRightClickFinderSync.appex" || true
	pluginkit -e use -i "$EXT_ID" || true
	sleep 1
	pluginkit -m -p com.apple.FinderSync 2>/dev/null | grep -i superright || echo "  !! 扩展没注册上，重跑一次"
fi

echo "构建产物：$APP"
