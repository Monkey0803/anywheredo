#!/usr/bin/env python3
"""AnywhereDo logo generator.

生成三套候选标识（SVG 源文件）：

  A  spark-card        弹窗卡片 + 火花 —— "光标旁边弹出的小卡片"
  B  cursor-spark      光标 + 火花     —— "指到哪儿，哪儿就能做事"
  C  selection-spark   选区括号 + 火花 —— "选中什么，就为你准备动作"

每套都有两种形态：
  * app icon  —— 1024x1024，macOS 圆角矩形（squircle）+ 渐变
  * menu bar  —— 64x64 单色 template，深浅色菜单栏自适应

用法：  python3 design/logo/generate.py
"""
import math
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]

CANVAS = 1024          # app icon 画布
BODY = 824             # 圆角矩形边长（Apple 图标网格：824/1024）
SQUIRCLE_N = 5.0       # 超椭圆指数，越大约接近圆角矩形


# --------------------------------------------------------------------------
# 几何工具
# --------------------------------------------------------------------------


def strip_trailing_whitespace(text: str) -> str:
    """去掉每行行尾空白：仓库的 pre-commit 钩子会拦截行尾空格，生成的 SVG 也要干净。"""
    return "\n".join(line.rstrip() for line in text.split("\n"))

def _superellipse_points(cx, cy, side, n, samples=4000):
    a = side / 2.0
    pts = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        ct, st = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(ct) ** (2.0 / n), ct)
        y = a * math.copysign(abs(st) ** (2.0 / n), st)
        pts.append((cx + x, cy + y))
    return pts


def _resample_closed(pts, count):
    """按弧长等距重采样，避免圆角处控制点过疏导致 Catmull-Rom 鼓包。"""
    n = len(pts)
    acc = [0.0]
    for i in range(1, n + 1):
        x0, y0 = pts[i - 1]
        x1, y1 = pts[i % n]
        acc.append(acc[-1] + math.hypot(x1 - x0, y1 - y0))
    total = acc[-1]
    out = []
    j = 0
    for k in range(count):
        target = total * k / count
        while j + 1 < len(acc) and acc[j + 1] < target:
            j += 1
        seg = acc[j + 1] - acc[j]
        f = 0.0 if seg == 0 else (target - acc[j]) / seg
        x0, y0 = pts[j % n]
        x1, y1 = pts[(j + 1) % n]
        out.append((x0 + (x1 - x0) * f, y0 + (y1 - y0) * f))
    return out


def _catmull_rom_closed(pts):
    n = len(pts)
    d = [f"M{pts[0][0]:.2f},{pts[0][1]:.2f}"]
    for i in range(n):
        p0 = pts[(i - 1) % n]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6.0, p1[1] + (p2[1] - p0[1]) / 6.0)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6.0, p2[1] - (p3[1] - p1[1]) / 6.0)
        d.append(
            f"C{c1[0]:.2f},{c1[1]:.2f} {c2[0]:.2f},{c2[1]:.2f} "
            f"{p2[0]:.2f},{p2[1]:.2f}"
        )
    d.append("Z")
    return " ".join(d)


def squircle(cx=512, cy=512, side=BODY, n=SQUIRCLE_N, segments=32):
    pts = _resample_closed(_superellipse_points(cx, cy, side, n), segments)
    return _catmull_rom_closed(pts)


def sparkle(cx, cy, r, waist=0.30, bow=0.45):
    """四角火花。

    waist  内凹顶点的半径比例（越小越细长）
    bow    边的控制点拉向角尖的比例（越大边越直）
    """
    w = waist * r / math.sqrt(2.0)
    tips = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    inners = [
        (cx + w, cy - w),
        (cx + w, cy + w),
        (cx - w, cy + w),
        (cx - w, cy - w),
    ]

    def ctrl(tip):
        return (cx + (tip[0] - cx) * bow, cy + (tip[1] - cy) * bow)

    def f(p):
        return f"{p[0]:.1f},{p[1]:.1f}"

    d = [f"M{f(tips[0])}"]
    for i in range(4):
        tip = tips[i]
        nxt = tips[(i + 1) % 4]
        d.append(f"Q{f(ctrl(tip))} {f(inners[i])}")
        d.append(f"Q{f(ctrl(nxt))} {f(nxt)}")
    d.append("Z")
    return " ".join(d)


def pointer(cx, cy, scale, round_join=None):
    """macOS 风格的箭头光标，尖端在 (cx, cy)，指向左上。

    round_join 不为 None 时，返回 (path, stroke_width)，用「同色描边 + 圆角」
    把尖角磨圆（描边会把形状整体撑大 stroke/2）。
    """
    base = [
        (0.0, 0.0),
        (0.0, 23.5),
        (5.6, 18.3),
        (9.3, 26.5),
        (12.9, 24.9),
        (9.2, 16.7),
        (16.4, 16.7),
    ]
    pts = [(cx + x * scale, cy + y * scale) for x, y in base]
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z"
    return d


# --------------------------------------------------------------------------
# SVG 组装
# --------------------------------------------------------------------------

def _defs(app, bg_from, bg_to, extra=""):
    if not app:
        return extra
    return f"""
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{bg_from}"/>
      <stop offset="1" stop-color="{bg_to}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.28" cy="0.12" r="0.95">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.30"/>
      <stop offset="0.45" stop-color="#ffffff" stop-opacity="0.08"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="vignette" cx="0.5" cy="0.5" r="0.78">
      <stop offset="0.55" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.22"/>
    </radialGradient>
    <linearGradient id="accent" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#FFD166"/>
      <stop offset="1" stop-color="#FF6A3D"/>
    </linearGradient>
    {extra}"""


def app_icon_svg(bg_from, bg_to, foreground, defs_extra=""):
    body = squircle()
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <defs>
    <clipPath id="bodyClip"><path d="{body}"/></clipPath>
    <filter id="dropShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#0B0A1F" flood-opacity="0.30"/>
    </filter>
    <filter id="softShadow" x="-40%" y="-40%" width="180%" height="180%">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#1A1140" flood-opacity="0.22"/>
    </filter>
    {_defs(True, bg_from, bg_to, defs_extra)}
  </defs>

  <g filter="url(#dropShadow)">
    <path d="{body}" fill="url(#bg)"/>
  </g>

  <g clip-path="url(#bodyClip)">
    <path d="{body}" fill="url(#bg)"/>
    <path d="{body}" fill="url(#vignette)"/>
    <path d="{body}" fill="url(#glow)"/>
    {foreground}
  </g>
</svg>
"""


def menubar_svg(foreground, size=64):
    """单色 template：纯黑 + alpha，交给 macOS 决定实际颜色。"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64">
  <g fill="#000000" fill-rule="evenodd">
    {foreground}
  </g>
</svg>
"""


# --------------------------------------------------------------------------
# A. spark-card：弹窗卡片 + 火花
# --------------------------------------------------------------------------

def concept_a_app():
    tail = "M404,552 L330,696 Q322,724 350,714 L556,552 Z"
    fg = f"""
    <g filter="url(#softShadow)">
      <rect x="336" y="276" width="376" height="308" rx="80" fill="url(#cardFill)"/>
      <path d="{tail}" fill="url(#cardFill)"/>
    </g>
    <path d="{sparkle(524, 430, 124)}" fill="url(#accent)"/>
    """
    extra = """<linearGradient id="cardFill" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#EEF0FB"/>
    </linearGradient>"""
    return app_icon_svg("#7A5CFF", "#3A1FD6", fg, extra)


def concept_a_menu():
    """菜单栏形态：只用火花本身。

    泡泡 + 内部火花在 18px 只有十几个像素可用，一定糊；菜单栏沿用
    App 图标里的那个火花（同一形状、同一角色），既最清楚也最省事。
    """
    return menubar_svg(f'<path d="{sparkle(32, 32, 28.5, waist=0.38, bow=0.56)}"/>')


# --------------------------------------------------------------------------
# B. cursor-spark：光标 + 火花
# --------------------------------------------------------------------------

def concept_b_app():
    d = pointer(344, 402, 12.6)
    fg = f"""
    <g filter="url(#softShadow)">
      <path d="{d}" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="12"
            stroke-linejoin="round"/>
    </g>
    <path d="{sparkle(636, 396, 186, waist=0.27, bow=0.43)}" fill="url(#accent)"/>
    """
    return app_icon_svg("#37C6FF", "#3B39E8", fg)


def concept_b_menu():
    return menubar_svg(
        f'<path d="{pointer(10, 8, 1.65)}"/>'
        f'<path d="{sparkle(44, 21, 12.5, waist=0.40, bow=0.55)}"/>'
    )


# --------------------------------------------------------------------------
# C. selection-spark：选区括号 + 火花
# --------------------------------------------------------------------------

def concept_c_app():
    x0, y0, x1, y1 = 250.0, 250.0, 774.0, 774.0
    arm = 168.0
    stroke = 62.0
    brackets = f"""<g fill="none" stroke="#FFFFFF" stroke-width="{stroke}"
        stroke-linecap="round" stroke-linejoin="round" opacity="0.97">
      <path d="M{x0},{y0 + arm} V{y0} H{x0 + arm}"/>
      <path d="M{x1 - arm},{y0} H{x1} V{y0 + arm}"/>
      <path d="M{x1},{y1 - arm} V{y1} H{x1 - arm}"/>
      <path d="M{x0 + arm},{y1} H{x0} V{y1 - arm}"/>
    </g>"""
    fg = f"""
    {brackets}
    <path d="{sparkle(512, 512, 152, waist=0.28, bow=0.44)}" fill="url(#accent)"/>
    """
    return app_icon_svg("#8B5CF6", "#3B2BC4", fg)


def concept_c_menu():
    arm, stroke = 12.5, 5.0
    brackets = f"""<g fill="none" stroke="#000000" stroke-width="{stroke}"
        stroke-linecap="round" stroke-linejoin="round">
      <path d="M11,{11 + arm} V11 H{11 + arm}"/>
      <path d="M{53 - arm},11 H53 V{11 + arm}"/>
      <path d="M53,{53 - arm} V53 H{53 - arm}"/>
      <path d="M{11 + arm},53 H11 V{53 - arm}"/>
    </g>"""
    return menubar_svg(
        brackets + f'<path d="{sparkle(32, 32, 13.0, waist=0.38, bow=0.52)}"/>'
    )


# --------------------------------------------------------------------------
# 横向 lockup
# --------------------------------------------------------------------------

def lockup(a_mark_inner, bg_from="#7A5CFF", bg_to="#3A1FD6"):
    body = squircle(84, 84, 136, segments=32)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="880" height="240" viewBox="0 0 880 240">
  <defs>
    <clipPath id="mClip"><path d="{body}"/></clipPath>
    <linearGradient id="mg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{bg_from}"/>
      <stop offset="1" stop-color="{bg_to}"/>
    </linearGradient>
    <linearGradient id="accent" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#FFD166"/>
      <stop offset="1" stop-color="#FF6A3D"/>
    </linearGradient>
    <linearGradient id="cardFill" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#EEF0FB"/>
    </linearGradient>
  </defs>
  <g clip-path="url(#mClip)">
    <path d="{body}" fill="url(#mg)"/>
    {a_mark_inner}
  </g>
  <text x="196" y="112" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif"
        font-size="76" font-weight="700" letter-spacing="-2" fill="#14122B">AnywhereDo</text>
  <text x="198" y="158" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif"
        font-size="30" font-weight="500" letter-spacing="0.5" fill="#6B6785">复制即建议 · 划词即弹</text>
</svg>
"""


def lockup_a_inner():
    """把 A 的图形缩小塞进 168x168 的 logo 方块里。"""
    s = 136.0 / CANVAS          # 相对 1024 画布缩放
    tx = 84 - 512 * s
    tail = "M404,552 L330,696 Q322,724 350,714 L556,552 Z"
    return f"""<g transform="translate({tx:.2f},{tx:.2f}) scale({s:.6f})">
    <rect x="336" y="276" width="376" height="308" rx="80" fill="url(#cardFill)"/>
    <path d="{tail}" fill="url(#cardFill)"/>
    <path d="{sparkle(524, 430, 124)}" fill="url(#accent)"/>
  </g>"""


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def w(rel, text):
    path = HERE / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(strip_trailing_whitespace(text), encoding="utf-8")
    print("  wrote", path.relative_to(REPO))


def main():
    print("生成 SVG 源文件：")
    w("candidates/a-spark-card.svg", concept_a_app())
    w("candidates/b-cursor-spark.svg", concept_b_app())
    w("candidates/c-selection-spark.svg", concept_c_app())

    w("menubar/a-spark-card.svg", concept_a_menu())
    w("menubar/b-cursor-spark.svg", concept_b_menu())
    w("menubar/c-selection-spark.svg", concept_c_menu())

    w("lockup/anywheredo-lockup-a.svg", lockup(lockup_a_inner()))
    print("完成。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
