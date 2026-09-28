# AnywhereDo 标识（Logo）

## 结论

主标识用 **A · 弹窗卡片 + 火花**：

```
       ┌──────────────┐          紫色圆角块 + 白色小卡片 + 琥珀色四角火花
       │      ✦       │          卡片的尖角朝左下，指向「光标所在的位置」
       └──────╲       ┘
              ╲
```

- **卡片** = 复制/划词后弹出的那张建议卡，是产品最核心、最独特的一帧。
- **火花** = 卡片里的建议「冒出来」的那一下；也是菜单栏图标的简化形态。
- **尖角朝左下**：卡片是贴着光标/选区弹出来的，不是从屏幕中间冒出来的。

菜单栏图标**只保留火花**。18pt 的菜单栏里，一张卡片再挖个洞只剩十几个像素，
怎么画都会糊；单独一个饱满的四角火花在 18px / 36px 下都清晰，深浅色菜单栏都成立。

## 文件

```
design/logo/
  generate.py                     几何生成器（squircle / 火花 / 光标 / 气泡都是算出来的）
  render_sheet.py                 候选对比图
  render_brand.py                 已采用方案的品牌总览图
  current-concept.txt             当前生效的方案名（build_icons.sh 写入）
  candidates/                     三套方案的 App 图标 SVG（1024×1024）
    a-spark-card.svg              弹窗卡片 + 火花   ← 已采用
    b-cursor-spark.svg            光标 + 火花
    c-selection-spark.svg         选区括号 + 火花
  menubar/                        三套方案的菜单栏 template SVG（64×64，纯黑 + alpha）
  lockup/anywheredo-lockup-a.svg  横版组合（标识 + 字标 + 一句话）
  preview/                        渲染出来的预览图
    brand.png                     品牌总览（App 图标 + 菜单栏 + 横版组合）
    contact-sheet.png             三套方案对比
    lockup.png                    横版组合
```

## 三套候选

| | 方向 | 讲的事 | 菜单栏表现 |
| --- | --- | --- | --- |
| **A** | 弹窗卡片 + 火花 | 「光标旁边弹出的小卡片」 | 火花，18px 清楚 |
| B | 光标 + 火花 | 「指到哪儿，哪儿就能做事」 | 光标 + 火花，18px 偏挤 |
| C | 选区括号 + 火花 | 「选中什么，就准备什么动作」 | 括号 + 火花，18px 清楚 |

B 的箭头形状太通用（一大票工具都用），C 的四角括号容易被读成截图/裁剪工具。
A 最贴近这个 App 真正独有的东西。

## 设计规范

| 项 | 值 |
| --- | --- |
| App 图标网格 | 1024 画布，圆角矩形边长 824（100…924），超椭圆指数 n = 5 |
| 底色渐变 | `#7A5CFF` → `#3A1FD6`（左上 → 右下），叠一层左上白色径向高光 + 四角暗角 |
| 卡片 | 白色 → `#EEF0FB` 微渐变，圆角 80，带柔和投影 |
| 火花 | 四角星，琥珀 `#FFD166` → `#FF6A3D`；凹边用二次贝塞尔，`waist 0.30 / bow 0.45` |
| 菜单栏 | 18pt（1x 18px / 2x 36px），纯黑 + alpha 的 template 图，由 macOS 决定实际颜色 |

## 重新生成 / 换方案

```bash
python3 design/logo/generate.py          # 改几何 → 重出所有 SVG
./scripts/render_logo.sh sheet design/logo/preview/contact-sheet.png
./scripts/render_logo.sh brand design/logo/preview/brand.png

./scripts/build_icons.sh                 # 默认 a-spark-card
./scripts/build_icons.sh c-selection-spark   # 换方案（一条命令）
./scripts/build_app.sh                   # 图标会一起打进 build/AnywhereDo.app
```

`build_icons.sh` 产出三件东西：`Resources/AppIcon.icns`（16…1024 全尺寸）、
`Resources/MenuBarIconTemplate.png` 和 `@2x.png`。

## 渲染器注意事项

`scripts/svg2png.py` 里有两处是踩过坑的：

1. Chrome 按 SVG 的 intrinsic 尺寸渲染文档——窗口比它小会被裁掉、比它大会留白，
   所以必须把 SVG 内联进 html 并**写死像素尺寸**（`width:100%` 在 headless 下不生效）。
2. 想在图标里做「镂空」时，被挖掉的形状必须和外形写在**同一条 `d`** 里；
   `fill-rule="evenodd"` 只在单个 path 内部生效，拆成两个 `<path>` 只会把洞填实。
