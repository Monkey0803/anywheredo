#!/usr/bin/env python3
"""把 SVG 光栅化成 PNG（透明背景）。

    python3 scripts/svg2png.py <in.svg> <out.png> <px> [--scale N]

<px> 是「最长边」的目标像素数，宽高比按 SVG 的 intrinsic 尺寸保持不变。

Chrome 按 SVG 的 intrinsic 尺寸渲染文档：窗口比它小就裁切、比它大会留空，
百分比尺寸在 headless 下又不生效，所以这里把 SVG 内联进 html 并写死像素尺寸。
--scale N 先放大 N 倍渲染再降采样，小尺寸下边缘更干净（默认 1）。
"""
import pathlib
import re
import subprocess
import sys
import tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
  html, body {{ margin:0; padding:0; background:transparent; overflow:hidden; }}
  svg {{ display:block; width:{w}px; height:{h}px; }}
</style></head><body>
{svg}
</body></html>
"""


def intrinsic_size(svg: str):
    """从 <svg> 根节点读 width/height；没有就退回 viewBox 的宽高。"""
    head = svg[: svg.index(">", svg.index("<svg")) + 1]
    w = re.search(r'\swidth="([\d.]+)', head)
    h = re.search(r'\sheight="([\d.]+)', head)
    if w and h:
        return float(w.group(1)), float(h.group(1))
    vb = re.search(r'viewBox="[\d.\-]+[,\s]+[\d.\-]+[,\s]+([\d.]+)[,\s]+([\d.]+)"', head)
    if vb:
        return float(vb.group(1)), float(vb.group(2))
    return 1.0, 1.0


def render(svg_path, out_path, px, scale=1):
    svg_path, out_path = pathlib.Path(svg_path), pathlib.Path(out_path)
    svg = svg_path.read_text(encoding="utf-8")
    iw, ih = intrinsic_size(svg)
    # 去掉 intrinsic 的 width/height，尺寸交给外层 CSS（viewBox 保留）
    svg = re.sub(r'\swidth="[^"]*"', "", svg, count=1)
    svg = re.sub(r'\sheight="[^"]*"', "", svg, count=1)

    fit = max(iw, ih)
    w = max(1, round(px * iw / fit))
    h = max(1, round(px * ih / fit))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        page = tmp / "page.html"
        page.write_text(
            PAGE.format(svg=svg, w=w * scale, h=h * scale), encoding="utf-8"
        )
        shot = tmp / "shot.png"
        subprocess.run(
            [
                CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                "--no-sandbox", "--force-device-scale-factor=1",
                "--default-background-color=00000000",
                f"--window-size={w * scale},{h * scale}",
                f"--screenshot={shot}", f"file://{page}",
            ],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if not shot.exists() or shot.stat().st_size == 0:
            raise SystemExit(f"渲染失败：{svg_path}")
        if scale == 1:
            out_path.write_bytes(shot.read_bytes())
        else:
            subprocess.run(
                ["sips", "-z", str(h), str(w), str(shot), "--out", str(out_path)],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    return out_path, (w, h)


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    scale = 1
    if "--scale" in argv:
        i = argv.index("--scale")
        scale = int(argv[i + 1])
    path, (w, h) = render(argv[1], argv[2], int(argv[3]), scale)
    print(f"{path}  ({w}x{h}, {scale}x supersample)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
