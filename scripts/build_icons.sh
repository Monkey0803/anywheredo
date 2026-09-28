#!/bin/bash
# 从 design/logo 的 SVG 生成 App 图标与菜单栏图标。
#
#   ./scripts/build_icons.sh [concept]
#
#   concept  候选方案目录名，默认 a-spark-card
#            a-spark-card | b-cursor-spark | c-selection-spark
#
# 产出（直接进 Resources/，build_app.sh 会把它们拷进 .app）：
#   Resources/AppIcon.icns                macOS App 图标（含 16~1024 全尺寸）
#   Resources/MenuBarIconTemplate.png     菜单栏模板图 18pt @1x
#   Resources/MenuBarIconTemplate@2x.png  菜单栏模板图 18pt @2x
set -euo pipefail

cd "$(dirname "$0")/.."

CONCEPT="${1:-a-spark-card}"
APP_SVG="design/logo/candidates/$CONCEPT.svg"
MB_SVG="design/logo/menubar/$CONCEPT.svg"

[ -f "$APP_SVG" ] || { echo "找不到 $APP_SVG" >&2; exit 1; }
[ -f "$MB_SVG" ]  || { echo "找不到 $MB_SVG" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> 渲染 App 图标（${CONCEPT}）"
"$PWD/scripts/render_logo.sh" icon "$APP_SVG" "$TMP/icon1024.png" 1024 >/dev/null

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  size="${spec%%:*}"; name="${spec##*:}"
  sips -z "$size" "$size" "$TMP/icon1024.png" --out "$ICONSET/$name.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "    Resources/AppIcon.icns"

echo "==> 渲染菜单栏图标"
# 先放大 8 倍渲染再降采样，边缘更干净（菜单栏图标必须带 alpha 且是纯黑 template）
"$PWD/scripts/render_logo.sh" glyph "$MB_SVG" "$TMP/mb36.png" 36 >/dev/null
"$PWD/scripts/render_logo.sh" glyph "$MB_SVG" "$TMP/mb18.png" 18 >/dev/null
cp "$TMP/mb18.png" Resources/MenuBarIconTemplate.png
cp "$TMP/mb36.png" Resources/MenuBarIconTemplate@2x.png
echo "    Resources/MenuBarIconTemplate.png (+@2x)"

printf '%s\n' "$CONCEPT" > design/logo/current-concept.txt
echo
echo "完成。当前方案：${CONCEPT}"
echo "换方案： ./scripts/build_icons.sh b-cursor-spark"
