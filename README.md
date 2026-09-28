# AnywhereDo

[![CI](https://github.com/Monkey0803/anywheredo/actions/workflows/ci.yml/badge.svg)](https://github.com/Monkey0803/anywheredo/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**简体中文** | [English](README_EN.md)

macOS 上的菜单栏小工具：**选中一段文字，卡片直接贴在选区正下方**（像输入法候选框那样），
不用先复制、不碰剪贴板。

三种触发方式，**默认只开第一种**：

| 触发方式 | 默认 | 影响剪贴板吗 |
| --- | --- | --- |
| **划词即弹**（选中文字就弹） | ✅ 开 | 不碰 |
| 复制后弹出建议（`⌘C` 就弹） | ❌ 关 | 会读剪贴板内容 |
| ⌘C 兜底（给 Chrome/Electron 类 App 划词） | ❌ 关 | 会短暂改写剪贴板再还原 |

后两个随时可以在菜单栏 ✨ 或设置里一键打开。

## 安装

### Homebrew（推荐）

```bash
brew tap monkey0803/tap
brew install --cask anywheredo
```

若报 `Refusing to load cask … from untrusted tap`（Homebrew 7 起要求显式信任第三方 tap），先执行：

```bash
brew trust monkey0803/tap
brew install --cask anywheredo
```

### 手动下载

从 [Releases](https://github.com/Monkey0803/anywheredo/releases) 下载
`AnywhereDo-<版本>-universal.zip`（arm64 + x86_64 通用），解压后把 `AnywhereDo.app` 拖进 `/Applications`。

> **签名说明**：v1.0.0 是 ad-hoc 签名，升级到**第一个使用固定证书签名的版本**时，
> 需要在「辅助功能」列表里把 AnywhereDo 移除后重新添加一次；从那个版本起，后续升级不再需要重新授权
> （原因见 [RELEASING.md](RELEASING.md)：ad-hoc 的 designated requirement 是 cdhash，代码一变就失效）。

> AnywhereDo **不上架 App Store**，也**没有做 Apple 公证**，只通过 GitHub Release 与 Homebrew tap 分发。
> 两种方式拿到的包都会被 macOS 打上隔离标记（Homebrew 会把下载物的隔离标记传播到安装后的 App），
> 所以首次打开可能被 Gatekeeper 拦住（提示「无法验证开发者」或「已损坏」）。解决办法二选一：
> **右键 → 打开**，或执行一次 `xattr -dr com.apple.quarantine /Applications/AnywhereDo.app`。

### 从源码构建

```bash
git clone https://github.com/Monkey0803/anywheredo.git
cd anywheredo
./scripts/build_app.sh          # 需要 Xcode / Swift 工具链（macOS 13+）
open build/AnywhereDo.app       # 菜单栏出现火花图标
```

首次使用划词时系统会要求授予**辅助功能**权限（只读选区文本与坐标；复制模式不需要任何权限）。
授权步骤与排查见 [权限说明](#权限说明) 和 [划词没效果？先看权限](#划词没效果先看权限排查顺序)。

## 它是怎么工作的

```
     ⌘C                               选中文字
      │                                   │
      ▼                                   ▼
PasteboardWatcher                   SelectionWatcher
每 0.35s 比对 changeCount           每 0.35s 读「焦点元素的选区」
（系统对剪贴板没有通知，             （走 Accessibility API：
  只有变了才真正读取内容）             AXSelectedText / AXSelectedTextRange /
      │                               AXBoundsForRange → 选区屏幕矩形）
      │                                   │
      └──────────────┬────────────────────┘
                     ▼
              Analyzer（纯 Foundation，可单测）
                classify    链接 / 文件路径 / JSON / 颜色 / 时间 / 邮箱 / 电话 / 算式 / Base64 / 代码 / 文本
                facts       不用点按钮就能看到的结论：算式结果、时间戳换算、颜色 RGB、JSON 结构…
                suggestions 该类型下真正有用的动作，最多 6 条 + 3 条 AI 建议
                     │
                     ▼
              PopupController
                复制触发 → 贴在鼠标旁；划词触发 → 贴在选区正下方（下方放不下自动翻到上方）
                非激活 NSPanel：不抢焦点、不切 Space；Esc / 点别处 / 超时关闭
```

两条触发链路对同一段文字会在 1.2s 内去重，不会弹两次。

划词的完整判定顺序（都能在诊断日志里看到）：

```
鼠标拖选 / 双击选词 / 三击选行 结束
   │
   ├─ 该 App 能通过 AX 读到选区  →  走正常链路（贴选区）
   │
   └─ 读不到（Chrome / Electron / 自绘文本）
         ├─ 焦点在密码框（AXSecureTextField）        → 跳过
         ├─ 系统「安全键盘输入」已开启                → 跳过
         ├─ 来源 App 在黑名单里                       → 跳过
         └─ 否则：合成 ⌘C →（期间暂停剪贴板监听）→ 读内容 → 还原原剪贴板
                  剪贴板没变化 = 其实没有选中内容，什么都不做、也不打扰你
```

## 识别什么、能做什么

（划词模式默认用**紧凑卡片**：不显示预览、最多 3 条建议 + 「展开剩余」按钮。）

（下表对「复制」和「划词」两种来源都适用。）

| 复制 / 选中的内容 | 面板里的结论 | 可点的建议 |
| --- | --- | --- |
| `https://github.com/apple/swift` | 域名、协议 | 在浏览器打开 / 复制 Markdown 链接 / 只复制域名 / Google 搜索 |
| `/Users/me/notes.md`、Finder 里复制的文件 | 大小、修改时间 | 在 Finder 中显示 / 用默认应用打开 / 复制所在文件夹 / 复制 `cd` 命令 |
| `{"a":1,"b":[…]}` | 对象·2 个字段 | 格式化 JSON（预览）/ 压缩成一行 / 复制原文 |
| `#3C8DEE`、`rgb(60,141,238)` | HEX / RGB / HSB | 复制 HEX / rgb() / SwiftUI `Color(...)` / HSB |
| `1700000000`、`2024-03-05 18:30` | 本地时间、UTC | 复制本地时间 / ISO 8601 / Unix 秒 / Unix 毫秒 / 建日历事件 |
| `dev@example.com` | 域名 | 写邮件 / 复制地址 / 提取域名 |
| `+86 138 1234 5678` | — | 发信息 / FaceTime 拨打 / 只复制数字 |
| `(128+64)*2-10` | `= 374` | 复制计算结果 |
| `aGVsbG8gd29ybGQ=` | 解码预览 | 解码查看 / 复制原文 |
| 代码 / 报错堆栈 | 行数、语言、是否疑似堆栈 | 搜索报错 / 去空行 / Google；配置 AI 后：解释代码、找 Bug、分析报错 |
| 一段普通文本 | 字数、行数 | 打开文中链接 / Google 搜索 / Google 翻译 / 复制为纯文本；配置 AI 后：总结、翻译、要点 |

面板支持键盘：`1`-`9` 直接触发对应建议，`Esc` 关闭。

## 构建与运行

需要 Xcode / Swift 工具链（macOS 13+）。

```bash
swift test                 # 30 个单元测试：分类、算式、JSON、Base64、颜色、时间、建议生成
./scripts/build_app.sh     # 产出 build/AnywhereDo.app（ad-hoc 签名）
open build/AnywhereDo.app  # 启动：菜单栏出现火花图标
```

分发用（arm64 + x86_64 通用二进制）：

```bash
UNIVERSAL=1 ./scripts/build_app.sh
```

push 到 `main` 会自动跑 GitHub Actions：构建 + 单元测试 + 打包通用 `.app`（作为 artifact 可下载）。

App 图标（`Resources/AppIcon.icns`）和菜单栏图标已经生成好了，直接构建即可。
改了标识或想换一套方案，跑一次 `./scripts/build_icons.sh [方案名]` 再重新构建；
设计说明见 [`design/logo/README.md`](design/logo/README.md)。

### 划词没效果？先看权限（排查顺序）

按这个顺序查，基本一步到位：

1. **菜单栏 ✨ → 自检：读取当前选区**：会直接告诉你权限状态和能不能读到选区。
2. **菜单栏 ✨ → 打开诊断日志**：`~/Library/Application Support/AnywhereDo/diagnostics.log`
   记录了每次启动的权限状态、每个触发事件（来源 App、内容长度、锚点）、弹窗位置——
   只记状态不记内容。常见结论：

   | 日志里看到 | 说明 |
   | --- | --- |
   | `权限=未授予` | 划词不会启动，走授权流程即可 |
   | `划词未启用：缺少辅助功能权限` | 同上，且已提醒过 |
   | `触发：com.xxx 长度=… 锚点=选区` | 划词读到选区了，弹窗应该贴在选区下方 |
   | 只有 `锚点=鼠标` | 你在用复制模式，或者目标 App 不提供选区坐标 |
   | 什么都没有 | 该 App 读不到选区，且兜底也没触发（检查是否关了 ⌘C 兜底） |
   | `划词：xxx 长度=241 换行符=0 估算行数=- 选区坐标=无` | Chromium 的典型表现：文字拿到了，但换行符与坐标都没有 |
   | `⌘C 兜底：跳过（起点在标题栏/标签栏）` | 是普通拖拽，不是划词，按设计没碰剪贴板 |
   | `⌘C 兜底：xxx 取到 长度=41 已还原=是` | 兜底成功，剪贴板已还原 |
   | `⌘C 兜底：跳过（焦点在安全输入框）` | 密码框，按设计不处理 |
   | `⌘C 兜底：xxx 没有复制到内容` | 该 App 忽略合成按键，或当时确实没有选中内容 |

3. 命令行自检（在终端里跑，会打印同一批信息）：

   ```bash
   .build/release/AnywhereDo --accessibility
   .build/release/AnywhereDo --selection
   .build/release/AnywhereDo --copy-probe   # 验证「合成 ⌘C + 还原剪贴板」
   .build/release/AnywhereDo --check-update # 检查 GitHub 上是否有新版本
   .build/release/AnywhereDo --render-hover   # 把悬停小图标渲染成 PNG（调试用）
   .build/release/AnywhereDo --hover-demo     # 验证「悬停展开」的接线（会尝试移动鼠标）
   ```

4. **Chrome / 飞书 / VS Code 这类 App 读不到选区**是正常的（它们自绘文本）。
   它们不把选区内容告诉系统，唯一办法是合成 ⌘C，而那会动剪贴板——
   所以兜底默认是**关**的；真需要时在菜单里打开 **「划词兜底：用 ⌘C 读 Electron 类 App」**。

5. **最常见的原因**：App 是从 Finder / `open` 启动的，而辅助功能权限只授给了终端。
   权限是按「进程身份」给的，终端有权限 ≠ App 有权限。

6. **改过代码重新编译后**要重新授权一次：ad-hoc 签名每次编译都会变，TCC 里旧的授权会失效
   （列表里勾还在，但实际不生效）。处理办法：把它从列表里 `-` 删除后重新 `+` 添加。
   想避免这个问题，就把 App 放到 `/Applications` 固定下来，不要每次都重新编译。

### 开划词需要授权（必须）

划词要读别的 App 里的选区文本和位置，只能用辅助功能 API，因此需要一次手动授权：

1. 首次启动如果划词开着但没权限，会自动弹一次说明框，
   点 **「打开辅助功能设置」**（系统授权框会同时把 App 加进列表）；
2. 在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 **AnywhereDo**；
3. 不用重启：授权后 3 秒内自动生效（也可以点菜单里的 **自检：读取当前选区** 确认）。

菜单里还有常驻的 **⚠️ 划词需要「辅助功能」权限** 入口，随时可以再触发一次。

不想授权就只用复制模式：菜单栏取消「划词即弹」即可，**复制模式完全不需要任何权限**。

想要开机自启，把 `build/AnywhereDo.app` 拖进 `/Applications`，然后在设置里勾选「登录时自动启动」。

调试（不开 GUI）：

```bash
.build/release/AnywhereDo --analyze "https://github.com/apple/swift"
printf '%s' '{"a":1}' | .build/release/AnywhereDo --analyze -
.build/release/AnywhereDo --accessibility   # 辅助功能授权状态
.build/release/AnywhereDo --selection       # 打印当前焦点 App 里选中的文字
```

## 设置

菜单栏图标 → **设置…**，或直接编辑 `~/Library/Application Support/AnywhereDo/settings.json`（权限 600）：

| 字段 | 说明 |
| --- | --- |
| `enabled` | 总开关，关闭后既不读剪贴板也不读选区 |
| `watchClipboard` | 复制后弹出建议（默认 `false`） |
| `watchSelection` | 划词即弹（需要辅助功能权限，默认 `true`） |
| `selectionCompact` | 划词时用紧凑卡片（不预览、最多 3 条建议） |
| `selectionCopyFallback` | 对读不到选区的 App 用 ⌘C 兜底（默认 `false`） |
| `showPreview` | 是否在弹窗里显示内容预览 |
| `keyboardShortcuts` | 是否让弹窗接收 `1-9` / `Esc` |
| `autoDismissSeconds` | 自动关闭秒数，`0` = 不自动关闭 |
| `maxContentLength` | 面板里保留的最大字符数（默认 3000，防止复制大文件卡界面） |
| `ignoreSensitive` | 忽略带 `org.nspasteboard.ConcealedType` 等标记的内容 |
| `ignoredBundleIDs` | 来源 App 黑名单，默认含 1Password / Bitwarden / 钥匙串等 |
| `selectionModifierInstant` | 按住 ⌘/⌥ 划词直接执行第一条建议（默认 `false`，不会调用 AI） |
| `selectionHoverIcon` | 划词后先出 26pt 小图标，悬停或点击才展开卡片（默认 `false`） |
| `ignoredBundleIDs` | 忽略的 App（bundle id 数组，设置里可从运行中的 App 挑选） |
| `checkForUpdates` | 启动时检查新版本（默认 `true`） |
| `lastUpdateCheck` | 上次检查时间，用于限流（自动写入） |
| `ai.*` | OpenAI 兼容接口：`baseURL` + `model` + `apiKey`（DeepSeek / OpenAI / Ollama 均可） |

配置 AI 后，建议列表里会多出带 ✨ 的条目（总结 / 翻译 / 润色 / 解释代码 / 找 Bug / 分析报错 / 提取待办），
结果在面板内展示，可一键复制。

## 隐私

- 只处理**文本**，内容不落盘、不写日志；面板只展示分析结论。
- 划词只读「当前最前台 App 焦点元素的选区」，**安全输入框（`AXSecureTextField`）直接跳过**；
  我们自己的弹窗/设置窗口拿着焦点时完全不做判断。
- ⌘C 兜底默认关闭。打开后它会短暂改写剪贴板（读完后按类型逐个写回，含 Finder 文件引用、HTML），
  并且**只在真正的鼠标划词动作上触发**：拖窗口、拖滚动条、拉滑块、拖文件、双击按钮都不会触发；
  剪贴板超过 12MB 或无法快照时直接放弃，宁可不兜底也不破坏你的剪贴板。
- 密码管理器打上「敏感 / 临时」标记的内容直接跳过。
- 来源 App 黑名单里的应用（默认含常见密码管理器与钥匙串）复制的内容不处理。
- 自己写剪贴板（「复制为 Markdown 链接」等）会被 `changeCount` 确认，不会自触发。
- 网络请求只有两个，都可以关：
  - **检查更新**（默认开）：启动时向 GitHub 的 releases API 发一个 GET，最多 6 小时一次，不带任何个人信息；
    设置里可以关掉，也可以用菜单里的「检查更新…」手动触发。
  - **AI 建议**：只在你配置了接口并主动点击后才发请求。

## 权限说明

- 复制模式：**不需要**任何权限。全局鼠标监听只用于「点别处关闭」。
- 划词模式：需要**辅助功能**权限（读选区文本与坐标）。
- 读取剪贴板时若系统弹出「允许粘贴」提示，选择**允许**，否则拿不到内容。
- 兼容性：

  | App 类型 | 选区文字 | 选区坐标 | 结果 |
  | --- | --- | --- | --- |
  | 原生 App（TextEdit / Safari / Xcode / 备忘录 / Mail） | ✅ | ✅ | 卡片贴选区正下方 |
  | Chromium 系（Chrome / DSH 界面 / 飞书 / VS Code） | ✅ | ❌ | 卡片贴鼠标（拖选结束的位置） |
  | 部分自绘文本的 App | ❌ | ❌ | 不弹（除非打开 ⌘C 兜底） |

- **Chromium 会把逐行渲染的代码块拍平**：通过辅助功能 API 拿到的选区文本里没有换行符，
  所以这种内容不会显示行数（只显示字符数），也不会谎报「1 行」。

## 实现笔记

- 菜单栏 App 默认没有主菜单，而 AppKit 的 **⌘X / ⌘C / ⌘V / ⌘A / ⌘Z 是靠「编辑」菜单的快捷键
  沿响应链派发的**——不装这个菜单，设置窗口里的文本框就不能粘贴、不能全选。
  所以 `AppDelegate.installMainMenu()` 里装了一个不会显示出来的主菜单（含「编辑」菜单）。
- 弹窗是 `.nonactivatingPanel`：不抢焦点、不切 Space，⌘C 之后原来的选区还在。
- **只有「鼠标划词动作」才会触发**：拖选 / 双击选词 / 三击选行。原因有两个——
  键盘选择（Shift+方向键、⌘A）不该打扰你；更关键的是**输入法的组合串（预编辑拼音）
  在文本框里也是「选中状态」**，不设门槛的话每敲一个字母都会弹一次。
  一旦检测到任何按键，鼠标划词的资格立即作废，并且正在显示的弹窗会立刻收起。
- 弹窗虽然能接收 Esc / 1-9，但**不会吞掉你的按键**：遇到未识别的按键会先收起自己让路。

## 代码结构

```
Sources/AnywhereDoCore/         纯 Foundation 内核，可单独单测
  Analyzer.swift                分类 + 事实 + 建议生成（核心，改这里就能加新玩法）
  ContentKind.swift             类型定义与图标/配色
  Suggestion.swift / AIPreset.swift
  MathEval.swift                递归下降算式求值（+ - * / % ^ 括号，支持 ×÷）
  JSONTools / Base64Tools / ColorTools / TimeTools / TextTransforms.swift
Sources/AnywhereDo/             AppKit 外壳（菜单栏应用，LSUIElement）
  main.swift                    入口 + --analyze CLI
  AppDelegate.swift             状态栏菜单、剪贴板事件分发、动作执行
  PasteboardWatcher.swift       changeCount 轮询、文件 URL、敏感类型过滤
  SelectionWatcher.swift        划词：AX 读取选区文本/坐标、授权状态、坐标换算
  PopupController.swift         贴鼠标 / 贴选区定位、关闭时机、全局鼠标监听
  CopyFallback.swift            合成 ⌘C + 剪贴板快照/还原（给读不到选区的 App 兜底）
  CardViews.swift               建议卡片 / 结果卡片 / 轻提示卡片（纯 Auto Layout）
  ActionRunner.swift            打开链接、Finder、剪贴板、变换、AI
  AIClient.swift                OpenAI 兼容 /chat/completions
  Diagnostics.swift             诊断日志（只写状态，不写内容）
  SettingsWindowController.swift 设置窗口
  AppSettings.swift             设置读写（Application Support JSON, 0600）
```

### 加一条新规则

1. `ContentKind` 里加类型（可选）。
2. `Analyzer.classify` 里插一个识别分支。
3. `Analyzer.buildSuggestions` 的 `switch` 里加对应建议，动作复用已有的 `SuggestionAction`。
4. 在 `Tests/AnywhereDoCoreTests/CoreTests.swift` 补一条断言，`swift test` 通过即可。

## 多语言

界面语言跟随系统偏好设置（简体中文与英文，未匹配到的语言回退到英文）：

- 所有用户可见文案都走 `Sources/AnywhereDoCore/L10n.swift`，字符串表在
  `Sources/AnywhereDoCore/Resources/<语言>.lproj/Localizable.strings`，Core 与 App 共用一张表。
- **AI 的系统提示词也在表里**，所以英文界面下模型会用英文回答。
- **诊断日志固定为中文**：这样任何人贴出的日志都能对着同一张排查表看，不必先判断语言。
- 新增一种语言：复制 `en.lproj` 为 `<新语言>.lproj` 并翻译值（**key 不要改**），
  然后跑 `swift test`——`LocalizationTests` 会校验两张表 key 完全一致、
  每个 `L10n.t("…")` 调用点都有对应条目、枚举出来的 key 一个不缺。
- 调试：`AnywhereDo --strings` 会打印系统偏好语言、资源提供语言与当前生效语言。

## 已知限制

- 轮询间隔 0.35s，极快的连续复制/连续改选只会响应最后一次。
- 划线时若目标 App 不支持 `AXBoundsForRange`，弹窗退化为贴在鼠标旁。
- 只处理文本与文件路径；复制的图片、富文本暂不分析。
- 面板不抢焦点，因此 `1-9` 快捷键依赖非激活面板的键盘行为；若觉得干扰可在设置里关掉。

## License

[MIT](LICENSE)
