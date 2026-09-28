#!/bin/bash
# 把 design/logo 下的 SVG 光栅化成 PNG。
#
#   render_logo.sh icon  <svg> <out.png> [size]    App 图标（正方形、透明背景）
#   render_logo.sh glyph <svg> <out.png> [size]    菜单栏单色图（默认 36，8x 超采样）
#   render_logo.sh sheet <out.png>                 三套候选的对比图
#   render_logo.sh brand <out.png>                 已采用方案的品牌总览图
set -euo pipefail

cd "$(dirname "$0")/.."

case "${1:-}" in
  icon)
    python3 scripts/svg2png.py "$2" "$3" "${4:-1024}"
    ;;
  glyph)
    python3 scripts/svg2png.py "$2" "$3" "${4:-36}" --scale 8
    ;;
  sheet)
    python3 design/logo/render_sheet.py "$2"
    ;;
  brand)
    python3 design/logo/render_brand.py "$2"
    ;;
  *)
    sed -n '2,8p' "$0"
    exit 1
    ;;
esac
