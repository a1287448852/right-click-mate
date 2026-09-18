#!/bin/bash
# 打包 DMG 安装包。
#
# 用法：./make-dmg.sh
# 产物：build-swiftui/右键伴侣-<版本>.dmg
#
# 里面是「App + Applications 软链接」的经典布局，拖一下就能装。
# 关于签名：这个 App 是 ad-hoc 本地签名，没有 Apple 开发者签名和公证，
# 所以用户首次打开需要手动放行一次 —— 安装说明写在 DMG 里的文本文件里。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build-swiftui"
APP="$BUILD/右键伴侣.app"
STAGE="$BUILD/dmg-stage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/App-Info.plist" 2>/dev/null || echo "0.1")"
DMG="$BUILD/RightClickMate-$VERSION.dmg"

if [[ ! -d "$APP" ]]; then
	echo "找不到 $APP"
	echo "先跑 ./build-swiftui.sh"
	exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<'NOTES'
右键伴侣 — 安装说明
====================

1. 把「右键伴侣」拖到右边的 Applications 文件夹。

2. 首次打开时会被系统拦下（提示"无法验证开发者"）。
   这是因为本项目没有 Apple 开发者签名（$99/年），不是有问题。

   放行方法（任选其一）：
   a) 在「应用程序」里右键点「右键伴侣」→ 选「打开」→ 再点一次「打开」
   b) 或者打开「终端」执行：
      xattr -cr "/Applications/右键伴侣.app"

3. 打开 App 后，到「通用设置」面板点「打开访达扩展管理面板」，
   确认「右键伴侣」处于开启状态。

4. 然后到任意文件夹右键，就能看到「右键伴侣」菜单了。

要求：macOS 27.0 或更高。

源码与问题反馈：https://github.com/a1287448852/right-click-mate
NOTES

echo "[1/2] 生成 DMG"
hdiutil create -volname "右键伴侣" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

echo "[2/2] 校验"
hdiutil verify "$DMG" >/dev/null 2>&1 && echo "  镜像校验通过"
rm -rf "$STAGE"

echo
echo "产物：$DMG"
ls -lh "$DMG" | awk '{print "  大小：" $5}'
echo "SHA256：$(shasum -a 256 "$DMG" | awk '{print $1}')"
