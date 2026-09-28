#!/bin/bash
# 构建 AnywhereDo.app（ad-hoc 签名，可直接双击运行）。
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="AnywhereDo"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [ ! -x "$BIN" ]; then
  echo "找不到可执行文件：$BIN" >&2
  exit 1
fi

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 图标资源（由 scripts/build_icons.sh 生成）
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "提示：没有 Resources/AppIcon.icns，先跑 ./scripts/build_icons.sh" >&2
fi
for f in MenuBarIconTemplate.png MenuBarIconTemplate@2x.png; do
  [ -f "Resources/$f" ] && cp "Resources/$f" "$APP/Contents/Resources/$f"
done
true

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "（签名失败，通常仍可运行）"

echo
echo "完成：$APP"
echo "运行：open $APP"
