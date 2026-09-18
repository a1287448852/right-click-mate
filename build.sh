#!/bin/bash
# 只用命令行工具构建，不需要 Xcode。
# 用法：./build.sh [install]   （install 会复制到 /Applications 并注册扩展）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/右键伴侣.app"
APPEX="$APP/Contents/PlugIns/SuperRightClickFinderSync.appex"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"
EXT_ID="com.local.SuperRightClick.FinderSync"
INSTALLED="/Applications/右键伴侣.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"

echo "[1/4] 编译 Finder 扩展"
# appex 的入口点是 Foundation 的 NSExtensionMain，不是 _main。
# Xcode 自动加这个 flag，命令行构建要自己写。
swiftc -parse-as-library -O -module-name SuperRightClickFinderSync \
	-sdk "$SDK" -target "$TARGET" \
	-framework Cocoa -framework FinderSync \
	-Xlinker -e -Xlinker _NSExtensionMain \
	-o "$APPEX/Contents/MacOS/SuperRightClickFinderSync" \
	"$ROOT/Sources/Config.swift" "$ROOT/Sources/ImageTools.swift" "$ROOT/Sources/FinderSync.swift"

echo "[2/5] 编译主 App"
swiftc -O -sdk "$SDK" -target "$TARGET" -framework Cocoa \
	-o "$APP/Contents/MacOS/SuperRightClick" \
	"$ROOT/Sources/Config.swift" "$ROOT/Sources/Theme.swift" \
	"$ROOT/Sources/main.swift" "$ROOT/Sources/SettingsWindow.swift"

echo "[3/5] 生成图标"
mkdir -p "$APP/Contents/Resources"
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
	rm -rf "/Applications/SuperRightClick.app" "$INSTALLED"
	cp -R "$APP" /Applications/
	# 先让 LaunchServices 认识这个 App，再注册扩展，顺序反了会静默失败
	LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
	"$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
	sleep 1
	pluginkit -a "$INSTALLED/Contents/PlugIns/SuperRightClickFinderSync.appex" || true
	pluginkit -e use -i "$EXT_ID" || true
	sleep 1
	echo "[install] 扩展状态："
	pluginkit -m -p com.apple.FinderSync 2>/dev/null | grep -i superright || echo "  !! 没注册上，重跑一次本脚本"
	echo "[install] 完成。去 Finder 里右键试试；菜单没出现就跑一下 killall Finder"
fi

echo "构建产物：$APP"
