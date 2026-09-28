#!/usr/bin/env python3
"""把已采用的标识渲染成一张「品牌总览」图（design/logo/preview/brand.png）。

用法： python3 design/logo/render_brand.py [out.png]
"""
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

sys.path.insert(0, str(REPO / "scripts"))
import svg2png  # noqa: E402


def main():
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "preview/brand.png"
    concept = (HERE / "current-concept.txt").read_text(encoding="utf-8").strip() \
        if (HERE / "current-concept.txt").exists() else "a-spark-card"

    tmp = pathlib.Path(tempfile.mkdtemp())
    icon = tmp / "icon.png"
    svg2png.render(HERE / "candidates" / f"{concept}.svg", icon, 512, scale=2)

    label = tmp / "mark.png"
    mb_svg = (HERE / "menubar" / f"{concept}.svg").read_text(encoding="utf-8")
    head_end = mb_svg.index(">", mb_svg.index("<svg")) + 1
    mark = (mb_svg[:head_end].replace('width="64" height="64"', 'width="100" height="100"')
            + mb_svg[head_end:])

    def strip(color, klass, sizes=(36, 18)):
        cells = []
        for s in sizes:
            sized = mark.replace("#000000", color).replace(
                'width="100" height="100"', f'width="{s}" height="{s}"'
            )
            cells.append(
                f'<div class="bar"><span>{s}px</span>'
                f'<div class="chip" style="height:64px">{sized}</div></div>'
            )
        return f'<div class="{klass}">{"".join(cells)}</div>'

    lockup_png = tmp / "lockup.png"
    svg2png.render(HERE / "lockup" / "anywheredo-lockup-a.svg", lockup_png, 880, scale=2)

    html = f"""<!doctype html><html><head><meta charset="utf-8"><style>
  * {{ box-sizing:border-box; }}
  body {{ margin:0; padding:40px; background:#F4F4F7;
         font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',Arial,sans-serif; color:#14122B; }}
  h1 {{ margin:0 0 4px; font-size:23px; letter-spacing:-.4px; }}
  p.lede {{ margin:0 0 30px; color:#6B6785; font-size:13px; }}
  .grid {{ display:flex; gap:22px; align-items:stretch; }}
  .card {{ background:#fff; border-radius:18px; padding:24px; width:320px;
           box-shadow:0 1px 2px rgba(20,18,43,.06), 0 8px 26px rgba(20,18,43,.07); }}
  .card h2 {{ margin:0 0 16px; font-size:12px; letter-spacing:.8px; text-transform:uppercase; color:#8A86A3; }}
  .card img {{ display:block; margin:0 auto; }}
  .row {{ display:flex; gap:14px; align-items:flex-end; justify-content:center; margin-bottom:12px; }}
  .row img {{ display:block; }}
  .cap {{ text-align:center; font-size:11px; color:#A9A5BB; margin-top:6px; }}
  .dark, .light {{ border-radius:11px; padding:10px; display:flex; gap:18px;
                   align-items:center; justify-content:center; margin-top:12px; }}
  .dark  {{ background:linear-gradient(#2A2A2E,#1B1B1E); }}
  .light {{ background:linear-gradient(#FFFFFF,#EDEDF1); border:1px solid #E3E3E9; }}
  .bar {{ display:flex; flex-direction:column; align-items:center; gap:6px; }}
  .bar span {{ font-size:9px; letter-spacing:.4px; }}
  .dark .bar span {{ color:#818189; }} .light .bar span {{ color:#A9A5BB; }}
  .wide {{ width:660px; }}
  .wide img {{ width:100%; }}
</style></head><body>
  <h1>AnywhereDo · 标识</h1>
  <p class="lede">方案 {concept}：弹窗卡片 + 火花。卡片负责「是什么」，火花负责「立刻能做事」。</p>
  <div class="grid">
    <section class="card">
      <h2>App 图标</h2>
      <div class="row">
        <img src="file://{icon}" width="180" height="180">
      </div>
      <div class="row">
        <img src="file://{icon}" width="64" height="64">
        <img src="file://{icon}" width="32" height="32">
      </div>
      <div class="cap">Finder / 聚焦 / 系统设置里看到的就是它</div>
    </section>
    <section class="card">
      <h2>菜单栏图标（template）</h2>
      <div class="cap" style="margin:0 0 12px">跟着系统走：浅色菜单栏变深、深色菜单栏变浅，选中时反色</div>
      {strip("#000000", "light")}
      {strip("#FFFFFF", "dark")}
    </section>
    <section class="card wide">
      <h2>横版组合</h2>
      <img src="file://{lockup_png}">
    </section>
  </div>
</body></html>
"""
    page = tmp / "brand.html"
    page.write_text(html, encoding="utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--no-sandbox",
         "--force-device-scale-factor=1.5", "--window-size=1080,585",
         f"--screenshot={out}", f"file://{page}"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    print(out)


if __name__ == "__main__":
    main()
