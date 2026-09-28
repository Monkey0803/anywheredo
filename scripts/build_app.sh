#!/bin/bash
# 构建 AnywhereDo.app（ad-hoc 签名，可直接双击运行）。
#
#   ./scripts/build_app.sh                     本机架构
#   UNIVERSAL=1 ./scripts/build_app.sh         arm64 + x86_64 通用二进制（分发用）
#   CONFIG=debug ./scripts/build_app.sh        调试构建
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
APP_NAME="AnywhereDo"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

if [ "$UNIVERSAL" = "1" ]; then
  echo "==> swift build -c $CONFIG --arch arm64 --arch x86_64"
  swift build -c "$CONFIG" --arch arm64 --arch x86_64
  BIN="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
  echo "==> swift build -c $CONFIG"
  swift build -c "$CONFIG"
  BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
fi
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
