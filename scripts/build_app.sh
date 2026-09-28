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

# 版本号唯一来源：Sources/AnywhereDoCore/Version.swift 的 marketing 常量
VERSION="$(grep -oE 'marketing *= *"[^"]+"' Sources/AnywhereDoCore/Version.swift | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
if [ -z "$VERSION" ]; then
  echo "读不到版本号：请检查 Sources/AnywhereDoCore/Version.swift 里的 marketing 常量" >&2
  exit 1
fi

echo "==> 组装 ${APP}（版本 ${VERSION}）"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
if grep -q "__VERSION__" "$APP/Contents/Info.plist"; then
  echo "Info.plist 里还有没替换的 __VERSION__ 占位符" >&2
  exit 1
fi
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

# SwiftPM 生成的本地化资源 bundle（en.lproj / zh-Hans.lproj）
# 必须在签名之前拷进去，否则会破坏签名封条。
CORE_BUNDLE="$(dirname "$BIN")/AnywhereDo_AnywhereDoCore.bundle"
if [ -d "$CORE_BUNDLE" ]; then
  echo "==> 拷入本地化资源：$(basename "$CORE_BUNDLE")"
  cp -R "$CORE_BUNDLE" "$APP/Contents/Resources/"
else
  echo "警告：找不到 $CORE_BUNDLE，App 内的文案将只有回退语言" >&2
fi
true

# ---- 签名 ----
# 给 SIGNING_IDENTITY（+ 可选 SIGNING_KEYCHAIN）就用固定证书签名。
# 不设置则退回 ad-hoc —— 注意 ad-hoc 的 requirement 是 cdhash，
# 重新编译或升级后，用户的「辅助功能」授权会失效。
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"

if [ -n "$SIGNING_IDENTITY" ]; then
  echo "==> 用证书签名：$SIGNING_IDENTITY"
  if [ -n "$SIGNING_KEYCHAIN" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" "$APP"
  else
    codesign --force --sign "$SIGNING_IDENTITY" "$APP"
  fi
  echo "==> 校验签名"
  codesign --verify --strict --verbose=1 "$APP" 2>&1 | tail -2
else
  echo "==> ad-hoc 签名（发布请用 SIGNING_IDENTITY 指定证书）"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "（签名失败，通常仍可运行）"
fi

REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | tail -1 | sed 's/^designated => //')"
echo
echo "==> designated requirement（TCC 按它认授权）："
echo "    $REQUIREMENT"
case "$REQUIREMENT" in
  *cdhash*)
    echo "    ⚠️  含 cdhash：用户每次升级都要重新授权辅助功能" ;;
  *)
    echo "    ✅ 不含 cdhash：升级后授权保持有效" ;;
esac

echo
echo "完成：$APP"
echo "运行：open $APP"
