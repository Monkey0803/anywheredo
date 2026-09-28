# AnywhereDo

[![CI](https://github.com/Monkey0803/anywheredo/actions/workflows/ci.yml/badge.svg)](https://github.com/Monkey0803/anywheredo/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[简体中文](README.md) | **English**

A tiny macOS menu-bar utility: **select some text and a card pops up right below the selection**
(like an input-method candidate window). No copy needed, no clipboard involved.

Three triggers, **only the first one is enabled by default**:

| Trigger | Default | Touches the clipboard? |
| --- | --- | --- |
| **Select-to-suggest** (pop up on text selection) | ✅ on | no |
| Suggest after copy (pop up on `⌘C`) | ❌ off | reads clipboard content |
| ⌘C fallback (select-to-suggest in Chrome/Electron apps) | ❌ off | briefly rewrites the clipboard, then restores it |

The last two can be toggled from the menu-bar icon or the settings window at any time.

## Install

### Homebrew (recommended)

```bash
brew tap monkey0803/tap
brew install --cask anywheredo
```

If you get `Refusing to load cask … from untrusted tap` (Homebrew 7 and later require third-party
taps to be trusted explicitly), run:

```bash
brew trust monkey0803/tap
brew install --cask anywheredo
```

### Manual download

Grab `AnywhereDo-<version>-universal.zip` from
[Releases](https://github.com/Monkey0803/anywheredo/releases), unzip it and drag `AnywhereDo.app`
into `/Applications`.

> **Signing note**: v1.0.0 is ad-hoc signed, so upgrading to the **first certificate-signed
> release** requires removing and re-adding AnywhereDo in the Accessibility list once. From that
> release onward, upgrades keep the same signing identity and no re-grant is needed
> (see [RELEASING.md](RELEASING.md): an ad-hoc designated requirement is a cdhash, which changes
> with every build).

> AnywhereDo is **not distributed through the App Store** and is **not notarized** — releases come
> from GitHub Releases and the Homebrew tap only. Both routes deliver a quarantined download
> (Homebrew propagates the quarantine flag from the download to the installed app), so the first
> launch may be blocked by Gatekeeper ("unidentified developer" / "is damaged"). Either
> **right-click → Open** it once, or run
> `xattr -dr com.apple.quarantine /Applications/AnywhereDo.app`.

### Build from source

```bash
git clone https://github.com/Monkey0803/anywheredo.git
cd anywheredo
./scripts/build_app.sh          # requires Xcode / Swift toolchain (macOS 13+)
open build/AnywhereDo.app       # a spark icon shows up in the menu bar
```

The first time you select text, macOS asks for **Accessibility** permission (it is only used to read
the selected text and its position; the copy mode needs no permission at all).
Selection mode offers two quieter variants (both in Settings → Popup, off by default):

- **Hover icon**: only a 26pt icon appears first; hover it or click it to expand the full card.
  If the pointer already rests on the icon when the drag ends, it expands immediately.
- **Modifier shortcut**: holding ⌘ or ⌥ while selecting runs the first suggestion straight away,
  with no card. It is a zero-latency path and **never calls the AI** (AI still needs an explicit click).
  > Note: this path **cannot be self-tested with synthetic events** — a synthesized `flagsChanged`
  > does not change `NSEvent.modifierFlags` (which is why there is no debug command for it), so it
  > can only be confirmed by actually holding the key.

The "Ignored apps" list in the settings lets you pick from **currently running apps**
instead of typing bundle ids (manually entered ids still work for apps that are closed).

See [Permissions](#permissions) and [Selection not working? Check permissions first](#selection-not-working-check-permissions-first).

## How it works

```
     ⌘C                              select text
      │                                   │
      ▼                                   ▼
PasteboardWatcher                   SelectionWatcher
polls changeCount every 0.35s       reads the focused element's selection every 0.35s
(macOS has no clipboard             (through the Accessibility API:
 notification; content is read        AXSelectedText / AXSelectedTextRange /
 only when it actually changed)       AXBoundsForRange → selection rect on screen)
      │                                   │
      └──────────────┬────────────────────┘
                     ▼
              Analyzer (pure Foundation, unit-testable)
                classify    url / file path / JSON / color / timestamp / email / phone /
                            math expression / base64 / code / plain text
                facts       conclusions you get without clicking anything: math result,
                            timestamp conversions, color RGB, JSON shape…
                suggestions up to 6 useful actions + 3 AI suggestions for that kind
                     │
                     ▼
              PopupController
                copy trigger  → next to the mouse; selection trigger → right below the selection
                                (flips above when there is no room)
                non-activating NSPanel: never steals focus, never switches Space;
                closes on Esc / click outside / timeout
```

Both trigger paths de-duplicate the same text within 1.2s, so it never pops twice.

The full selection decision flow (every step is visible in the diagnostics log):

```
mouse drag-select / double-click word / triple-click line finished
   │
   ├─ the app exposes its selection through AX  →  normal path (anchored to the selection)
   │
   └─ it does not (Chrome / Electron / self-drawn text)
         ├─ focus is in a secure text field (AXSecureTextField) → skip
         ├─ system "secure keyboard entry" is on                 → skip
         ├─ source app is on the ignore list                     → skip
         └─ otherwise: synthesize ⌘C → (clipboard watching paused) → read content → restore
                       clipboard unchanged = nothing was selected, do nothing at all
```

## What it recognizes and what it can do

(The selection mode uses a **compact card** by default: no preview, at most 3 suggestions plus an
"expand" button.)

(The table applies to both the copy and the selection sources.)

| Selected / copied content | What the card shows | Actions you can click |
| --- | --- | --- |
| `https://github.com/apple/swift` | host, scheme | Open in browser / Copy as Markdown link / Copy host only / Google search |
| `/Users/me/notes.md`, a file copied in Finder | size, modification date | Reveal in Finder / Open with default app / Copy parent folder / Copy `cd` command |
| `{"a":1,"b":[…]}` | object · 2 keys | Pretty-print JSON (preview) / Minify / Copy original |
| `#3C8DEE`, `rgb(60,141,238)` | HEX / RGB / HSB | Copy HEX / rgb() / SwiftUI `Color(...)` / HSB |
| `1700000000`, `2024-03-05 18:30` | local time, UTC | Copy local time / ISO 8601 / Unix seconds / Unix millis / Create calendar event |
| `dev@example.com` | domain | Compose mail / Copy address / Extract domain |
| `+86 138 1234 5678` | — | Send message / FaceTime call / Copy digits only |
| `(128+64)*2-10` | `= 374` | Copy the result |
| `aGVsbG8gd29ybGQ=` | decoded preview | Decode / Copy original |
| code / stack trace | line count, language, stack-trace hint | Search the error / Collapse blank lines / Google; with AI configured: explain code, find bugs, analyze errors |
| any plain text | character and line count | Open links inside / Google search / Google Translate / Copy as plain text; with AI: summarize, translate, key points |

Keyboard: `1`-`9` trigger the matching suggestion, `Esc` closes the card.

## Build & run

Requires an Xcode / Swift toolchain (macOS 13+).

```bash
swift test                 # 30 unit tests: classification, math, JSON, base64, color, time, suggestions
./scripts/build_app.sh     # produces build/AnywhereDo.app (ad-hoc signed)
open build/AnywhereDo.app  # launches; the spark icon appears in the menu bar
```

For distribution (arm64 + x86_64 universal binary):

```bash
UNIVERSAL=1 ./scripts/build_app.sh
```

Pushing to `main` runs GitHub Actions: build + unit tests + packaging the universal `.app` as a
downloadable artifact.

The app icon (`Resources/AppIcon.icns`) and the menu-bar icon are already generated; just build.
To change the identity or try another concept, run `./scripts/build_icons.sh [concept]` and rebuild;
see [`design/logo/README.md`](design/logo/README.md) for the design notes.

### Selection not working? Check permissions first

In this order — it usually nails it in one pass:

1. **Menu-bar icon → 自检 / Self-check: read current selection**: it tells you the permission state
   and whether a selection can be read.
2. **Menu-bar icon → Open diagnostics log**: `~/Library/Application Support/AnywhereDo/diagnostics.log`
   records the permission state at launch, every trigger event (source app, content length, anchor)
   and the popup position — **state only, never content**. Typical lines:

   | What you see in the log | Meaning |
   | --- | --- |
   | `权限=未授予` (permission not granted) | the selection watcher never starts; run the grant flow |
   | `划词未启用：缺少辅助功能权限` | same as above, and the guide was already shown once |
   | `触发：com.xxx 长度=… 锚点=选区` | selection was read; the card is anchored to the selection |
   | only `锚点=鼠标` (mouse anchor) | you are in copy mode, or the app exposes no selection rect |
   | nothing at all | that app exposes no selection and the fallback is off |
   | `划词：xxx 长度=241 换行符=0 估算行数=- 选区坐标=无` | typical Chromium behaviour: text yes, newlines and rect no |
   | `⌘C 兜底：跳过（起点在标题栏/标签栏）` | an ordinary drag, not a selection — clipboard untouched by design |
   | `⌘C 兜底：xxx 取到 长度=41 已还原=是` | fallback worked, clipboard restored |
   | `⌘C 兜底：跳过（焦点在安全输入框）` | password field — skipped by design |

3. Command-line self-check (run in a terminal; prints the same information).
   **Careful with `--accessibility`:** TCC attributes the decision to the "responsible process", and a
   process launched from a terminal inherits the terminal's (or its parent's) grant — so it can report
   granted while the app itself is not. **For the app's own state use the in-app "Self-check: read the
   current selection" menu item, or the `权限=` line in the diagnostics log.**

   ```bash
   .build/release/AnywhereDo --accessibility   # note: run from a terminal it may inherit the terminal's grant
   .build/release/AnywhereDo --selection
   .build/release/AnywhereDo --copy-probe   # verifies "synthesize ⌘C + restore clipboard"
   .build/release/AnywhereDo --check-update # ask GitHub whether a newer release exists
   .build/release/AnywhereDo --render-hover   # render the hover icon as a PNG (debug)
   .build/release/AnywhereDo --hover-demo     # verify the hover-to-expand wiring (tries to move the pointer)
   ```

4. **Chrome / Lark / VS Code not exposing a selection is normal** (they draw text themselves).
   The only way in is to synthesize ⌘C, which touches the clipboard — that is why the fallback is
   **off** by default. Enable it from the menu when you really need it.

5. **The most common cause**: the app was launched from Finder / `open`, while Accessibility was
   granted to your terminal. Permission is per process identity — the terminal having it does not
   mean the app has it.

6. **After rebuilding from source you must grant again**: an ad-hoc signature changes on every
   build, which invalidates the TCC entry (the checkbox stays on but no longer applies). Remove the
   entry with `-` and add the app again with `+`. To avoid this, keep the app in `/Applications` and
   stop rebuilding it.

### Granting Accessibility (required for selection mode)

Reading the selected text and its position in other apps is only possible through the Accessibility
API, so a one-time manual grant is required:

1. On first launch, if selection mode is on without permission, a short guide appears — click
   **"Open Accessibility settings"** (the system prompt adds the app to the list);
2. In **System Settings → Privacy & Security → Accessibility**, tick **AnywhereDo**;
3. No restart needed: it takes effect within 3 seconds. Verify with
   **Self-check: read current selection** in the menu.

A permanent **⚠️ selection needs Accessibility permission** entry is always available in the menu.

If you prefer not to grant it, just use copy mode: untick "select-to-suggest" — **copy mode needs no
permission at all**.

To launch at login, move `AnywhereDo.app` into `/Applications` and tick "Launch at login" in the
settings window.

Debugging (without the GUI):

```bash
.build/release/AnywhereDo --analyze "https://github.com/apple/swift"
printf '%s' '{"a":1}' | .build/release/AnywhereDo --analyze -
.build/release/AnywhereDo --accessibility   # Accessibility grant state
.build/release/AnywhereDo --selection       # print the selection in the focused app
```

## Settings

Menu-bar icon → **Settings…**, or edit `~/Library/Application Support/AnywhereDo/settings.json`
(mode 600) directly:

| Key | Meaning |
| --- | --- |
| `enabled` | master switch; when off, neither the clipboard nor the selection is read |
| `watchClipboard` | suggest after copy (default `false`) |
| `watchSelection` | select-to-suggest (needs Accessibility, default `true`) |
| `selectionCompact` | compact card for selections (no preview, at most 3 suggestions) |
| `selectionCopyFallback` | ⌘C fallback for apps that expose no selection (default `false`) |
| `showPreview` | show the content preview inside the card |
| `keyboardShortcuts` | let the card receive `1-9` / `Esc` |
| `autoDismissSeconds` | auto-close delay; `0` = never |
| `maxContentLength` | max characters kept for the card (default 3000, keeps huge copies from freezing the UI) |
| `ignoreSensitive` | ignore content flagged with `org.nspasteboard.ConcealedType` etc. |
| `ignoredBundleIDs` | source-app block list (1Password / Bitwarden / Keychain by default) |
| `selectionModifierInstant` | hold ⌘/⌥ while selecting to run the first suggestion directly (default `false`, never calls AI) |
| `selectionHoverIcon` | show a 26pt icon after selecting; hover or click to expand the card (default `false`) |
| `ignoredBundleIDs` | ignored apps (array of bundle ids; pickable from running apps in the settings) |
| `checkForUpdates` | check for a new release at launch (default `true`) |
| `lastUpdateCheck` | timestamp of the last check, used for rate limiting (written automatically) |
| `ai.*` | OpenAI-compatible endpoint: `baseURL` + `model` + `apiKey` (DeepSeek / OpenAI / Ollama) |

With AI configured, extra sparkle entries appear (summarize / translate / polish / explain code /
find bugs / analyze errors / extract todos); the result is rendered inside the card and can be copied
with one click.

## Privacy

- Only **text** is processed. Nothing is written to disk and nothing is logged; the card only shows
  analysis results.
- Selections are read only from "the focused element of the current frontmost app"; **secure text
  fields (`AXSecureTextField`) are skipped outright**. While our own card or settings window holds
  focus, no reading happens at all.
- The ⌘C fallback is off by default. When enabled it briefly rewrites the clipboard (then writes the
  original back type by type, including Finder file references and HTML) and **only fires on a real
  mouse selection gesture**: window drags, scrollbar drags, slider drags, file drags and double
  clicks on buttons never trigger it. Clipboards larger than 12MB, or ones that cannot be
  snapshotted, are left alone — we would rather skip the fallback than damage your clipboard.
- Content flagged as concealed/transient by a password manager is skipped.
- Content copied from apps on the block list (common password managers and Keychain) is skipped.
- Clipboard writes we perform ourselves ("Copy as Markdown link", …) are acknowledged through
  `changeCount` so they never re-trigger the app.
- There are exactly two network requests, both switchable off:
  - **Update check** (on by default): one GET to GitHub's releases API at launch, at most once every
    6 hours, carrying no personal data. Turn it off in the settings, or trigger it manually from the
    menu with "Check for updates…".
  - **AI suggestions**: only after you configure an endpoint and click the action yourself.

## Permissions

- Copy mode: **no permission** needed. The global mouse monitor is only used to close on outside clicks.
- Selection mode: needs **Accessibility** (reads selection text and rect).
- If macOS shows a "allow paste" prompt when reading the clipboard, choose **Allow**, otherwise
  content cannot be read.
- Compatibility:

  | App type | Selection text | Selection rect | Result |
  | --- | --- | --- | --- |
  | Native apps (TextEdit / Safari / Xcode / Notes / Mail) | ✅ | ✅ | card right below the selection |
  | Chromium family (Chrome / Lark / VS Code) | ✅ | ❌ | card next to the mouse (where the drag ended) |
  | Some self-drawn apps | ❌ | ❌ | nothing (unless the ⌘C fallback is enabled) |

- **Chromium flattens block-rendered code**: the text obtained through the Accessibility API has no
  newline characters, so such content shows a character count but no line count — and never claims
  "1 line".

## Implementation notes

- Menu-bar apps have no main menu by default, and AppKit dispatches **⌘X / ⌘C / ⌘V / ⌘A / ⌘Z
  through the key equivalents of an Edit menu** — without that menu, text fields in the settings
  window cannot paste or select all. `AppDelegate.installMainMenu()` therefore installs an invisible
  main menu (including an Edit menu).
- The card is a `.nonactivatingPanel`: it never steals focus or switches Space, so the selection is
  still there after `⌘C`.
- **Only a "mouse selection gesture" triggers it**: drag-select, double-click word, triple-click
  line. Two reasons — keyboard selection (Shift+arrows, ⌘A) should not interrupt you, and more
  importantly the **IME composition string (pre-edit pinyin) is a selection in the text field too**,
  so without a gate every typed letter would pop a card. Any key press immediately invalidates the
  mouse-selection eligibility and dismisses a visible card.
- Although the card accepts Esc / 1-9, it **never swallows your keystrokes**: an unrecognized key
  dismisses the card and lets the event through.

## Code layout

```
Sources/AnywhereDoCore/         pure Foundation kernel, unit-testable on its own
  Analyzer.swift                classification + facts + suggestion building (the place to extend)
  ContentKind.swift             content kinds and their icons/accents
  Suggestion.swift / AIPreset.swift
  MathEval.swift                recursive-descent expression evaluator (+ - * / % ^ parens, × ÷)
  JSONTools / Base64Tools / ColorTools / TimeTools / TextTransforms.swift
Sources/AnywhereDo/             AppKit shell (menu-bar app, LSUIElement)
  main.swift                    entry point + --analyze CLI
  AppDelegate.swift             status item menu, event routing, action execution
  PasteboardWatcher.swift       changeCount polling, file URLs, sensitive-type filtering
  SelectionWatcher.swift        selection: AX text/rect reading, grant state, coordinate conversion
  PopupController.swift         mouse/selection anchoring, dismissal, global mouse monitor
  CopyFallback.swift            synthesized ⌘C + clipboard snapshot/restore
  CardViews.swift               suggestion / result / toast cards (plain Auto Layout)
  ActionRunner.swift            open URL, Finder, clipboard, transforms, AI
  AIClient.swift                OpenAI-compatible /chat/completions
  Diagnostics.swift             diagnostics log (state only, never content)
  SettingsWindowController.swift settings window
  AppSettings.swift             settings I/O (Application Support JSON, 0600)
```

### Adding a new rule

1. Add a kind in `ContentKind` (optional).
2. Insert a detection branch in `Analyzer.classify`.
3. Add suggestions to the `switch` in `Analyzer.buildSuggestions`, reusing the existing
   `SuggestionAction` cases.
4. Add an assertion to `Tests/AnywhereDoCoreTests/CoreTests.swift` and make `swift test` pass.

## Localization

The UI follows the system language (Simplified Chinese and English; anything else falls back to English):

- Every user-visible string goes through `Sources/AnywhereDoCore/L10n.swift`, with the tables in
  `Sources/AnywhereDoCore/Resources/<language>.lproj/Localizable.strings` — Core and the app share one table.
- **The AI system prompts live in the same table**, so an English UI also gets English answers from the model.
- **Diagnostics logs stay Chinese on purpose**: any pasted log can be read against a single
  troubleshooting table without first working out its language.
- Adding a language: copy `en.lproj` to `<new-language>.lproj` and translate the values
  (**never change the keys**), then run `swift test` — `LocalizationTests` asserts that both tables
  have identical keys, that every `L10n.t("…")` call site has an entry, and that every enumerated key resolves.
- Debugging: `AnywhereDo --strings` prints the preferred languages, the bundled languages and the active one.

## Known limitations

- Polling interval is 0.35s: extremely fast consecutive copies or selection changes only react to the
  last one.
- If the target app does not support `AXBoundsForRange`, the card falls back to the mouse position.
- Only text and file paths are processed; copied images and rich text are not analyzed yet.
- The card never steals focus, so the `1-9` shortcuts depend on non-activating panel keyboard
  behaviour; turn them off in the settings if they get in the way.

## License

[MIT](LICENSE)
