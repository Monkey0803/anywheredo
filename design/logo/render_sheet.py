#!/usr/bin/env python3
"""生成候选 logo 的对比图（一张 PNG）：三种方案 x {大图标, 真实尺寸菜单栏}。

用法： python3 design/logo/render_sheet.py [out.png]
"""
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CONCEPTS = [
    ("a-spark-card", "A · 弹窗卡片 + 火花", "光标旁弹出的小卡片"),
    ("b-cursor-spark", "B · 光标 + 火花", "指到哪儿，哪儿就能做事"),
    ("c-selection-spark", "C · 选区括号 + 火花", "选中什么，就准备什么动作"),
]

GLYPH_SIZES = (144, 36, 18)


def render_svg(svg, size, out):
    """复用 scripts/svg2png.py：Chrome 按 SVG intrinsic 尺寸渲染，必须套一层 html。"""
    sys.path.insert(0, str(HERE.parents[1] / "scripts"))
    import svg2png
    svg2png.render(svg, out, size, scale=2)


def inline_glyph(svg_path: pathlib.Path, size: int, color: str) -> str:
    src = svg_path.read_text(encoding="utf-8")
    open_end = src.index(">", src.index("<svg"))
    head = src[src.index("<svg"):open_end + 1]
    body = src[open_end + 1:].replace("</svg>", "")
    head = head.replace('width="64" height="64"', f'width="{size}" height="{size}"')
    return (head + body).replace("#000000", color)


def main():
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "preview/contact-sheet.png"
    tmp = pathlib.Path(tempfile.mkdtemp())

    cards = []
    for slug, title, sub in CONCEPTS:
        icon_png = tmp / f"{slug}.png"
        render_svg(HERE / "candidates" / f"{slug}.svg", 512, icon_png)

        def strip(color, klass):
            bars = []
            for s in GLYPH_SIZES:
                body = inline_glyph(HERE / "menubar" / f"{slug}.svg", s, color)
                bars.append(
                    f'<div class="bar"><span class="tag">{s}px</span>'
                    f'<div class="chip" style="height:{GLYPH_SIZES[0] + 12}px">{body}</div>'
                    f"</div>"
                )
            return f'<div class="{klass}">{"".join(bars)}</div>'

        cards.append(f"""
    <section class="card">
      <img class="icon" src="file://{icon_png}" width="212" height="212" alt="{title}">
      <h2>{title}</h2>
      <p class="sub">{sub}</p>
      {strip("#FFFFFF", "dark")}
      {strip("#1C1C1F", "light")}
    </section>""")

    html = f"""<!doctype html>
<html><head><meta charset="utf-8"><style>
  * {{ box-sizing:border-box; }}
  body {{ margin:0; padding:44px 40px 40px; background:#F4F4F7;
         font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue',Arial,sans-serif; }}
  h1 {{ margin:0 0 6px; font-size:25px; letter-spacing:-0.4px; color:#14122B; }}
  .lede {{ margin:0 0 30px; color:#6B6785; font-size:13.5px; }}
  .row {{ display:flex; gap:24px; align-items:flex-start; }}
  .card {{ background:#fff; border-radius:20px; padding:26px 22px 20px; width:330px;
           box-shadow:0 1px 2px rgba(20,18,43,.06), 0 8px 26px rgba(20,18,43,.08); }}
  .icon {{ display:block; margin:0 auto 16px; }}
  h2 {{ margin:0 0 4px; font-size:14.5px; color:#14122B; text-align:center; letter-spacing:-0.2px; }}
  .sub {{ margin:0 0 16px; font-size:12.5px; color:#8A86A3; text-align:center; }}
  .dark, .light {{ border-radius:11px; padding:9px 8px 7px; display:flex; gap:10px;
                   align-items:flex-end; justify-content:center; margin-bottom:7px; }}
  .dark  {{ background:linear-gradient(#2A2A2E,#1B1B1E); }}
  .light {{ background:linear-gradient(#FFFFFF,#EDEDF1); border:1px solid #E3E3E9; }}
  .bar {{ display:flex; flex-direction:column; align-items:center; gap:6px; }}
  .tag {{ font-size:9px; letter-spacing:.4px; }}
  .dark .tag {{ color:#818189; }} .light .tag {{ color:#A9A5BB; }}
  .chip {{ display:flex; align-items:center; justify-content:center; }}
</style></head>
<body>
  <h1>AnywhereDo · 标识候选</h1>
  <p class="lede">三种方向。每一格下方是菜单栏 template 图标在深/浅色菜单栏上的真实效果（144px 仅用于看细节）。</p>
  <div class="row">{''.join(cards)}</div>
</body></html>
"""

    page = tmp / "sheet.html"
    page.write_text(html, encoding="utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
            "--no-sandbox", "--force-device-scale-factor=1.6",
            "--window-size=1160,880", f"--screenshot={out}", f"file://{page}",
        ],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    print(out)


if __name__ == "__main__":
    main()
