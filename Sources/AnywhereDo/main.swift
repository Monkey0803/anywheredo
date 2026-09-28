import AppKit
import AnywhereDoCore

// MARK: - 命令行模式（不开 GUI，方便调试分析逻辑）

func printAnalysis(_ text: String) {
    let analysis = Analyzer().analyze(text, options: AnalysisOptions(maxLength: 1200, aiEnabled: false))
    print(L10n.t("cli.kind", analysis.kind.rawValue, analysis.kind.displayName))
    print(L10n.t("cli.headline", analysis.headline))
    print(L10n.t("cli.size", analysis.charCount, analysis.lineCount, analysis.truncated ? L10n.t("cli.truncated") : ""))
    if !analysis.facts.isEmpty {
        print(L10n.t("cli.facts"))
        for fact in analysis.facts {
            print("  · \(fact.label): \(fact.value)")
        }
    }
    print(L10n.t("cli.suggestions"))
    for (index, suggestion) in analysis.suggestions.enumerated() {
        let subtitle = suggestion.subtitle.map { L10n.t("cli.subtitleSeparator", $0) } ?? ""
        print("  \(index + 1). \(suggestion.title)\(subtitle)")
    }
}

let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print(L10n.t("cli.help"))
    exit(0)
}

if arguments.contains("--version") {
    print("AnywhereDo \(AnywhereDoVersion.marketing)")
    exit(0)
}

if let index = arguments.firstIndex(of: "--analyze") {
    let rest = Array(arguments.dropFirst(index + 1))
    var text = rest.joined(separator: " ")
    if text == "-" || text.isEmpty {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        text = String(data: data, encoding: .utf8) ?? ""
    }
    printAnalysis(text)
    exit(0)
}

if arguments.contains("--strings") {
    print(L10n.t("cli.preferredLanguages", Locale.preferredLanguages.joined(separator: ", ")))
    print(L10n.t("cli.bundledLanguages", L10n.supportedLanguages.joined(separator: ", ")))
    print(L10n.t("cli.activeLanguage", L10n.language))
    for key in ["kind.url", "kind.color", "ai.summarize", "transform.jsonPretty.title"] {
        print("  \(key) = \(L10n.t(key))")
    }
    exit(0)
}

if arguments.contains("--check-update") {
    // 需要一个 run loop 来收 URLSession 回到主队列的回调，不能直接 wait 信号量。
    var finished = false
    var info: UpdateInfo?
    UpdateChecker.check { result in
        info = result
        finished = true
    }
    let deadline = Date().addingTimeInterval(20)
    while !finished && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    guard finished else {
        print(L10n.t("cli.updateTimeout"))
        exit(2)
    }
    print(L10n.t("cli.currentVersion", AnywhereDoVersion.marketing))
    if let info {
        print(L10n.t("cli.newVersion", info.version))
        print(L10n.t("cli.downloadPage", info.url.absoluteString))
        exit(0)
    } else {
        print(L10n.t("cli.upToDate"))
        exit(0)
    }
}

if arguments.contains("--accessibility") {
    let trusted = SelectionWatcher.isTrusted
    let line = trusted
        ? L10n.t("cli.accessibilityGranted")
        : L10n.t("cli.accessibilityDenied")
    Diagnostics.section("--accessibility")
    Diagnostics.log(line + " path=" + Bundle.main.bundlePath)
    print(line)
    exit(0)
}

if arguments.contains("--selection") {
    guard SelectionWatcher.isTrusted else {
        print(L10n.t("cli.selectionNoPermission"))
        exit(2)
    }
    if let app = NSWorkspace.shared.frontmostApplication {
        print(L10n.t("cli.focusedApp", app.localizedName ?? L10n.t("cli.unknownApp")))
    }
    if let text = Accessibility.currentSelectionText(), !text.isEmpty {
        Diagnostics.log("--selection：读到 \(text.count) 字，焦点 App=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        print(L10n.t("cli.selectionText", text.count))
        print(text)
    } else {
        Diagnostics.log("--selection：没有读到选区，焦点 App=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        print(L10n.t("cli.noSelection"))
    }
    exit(0)
}

if arguments.contains("--copy-probe") {
    let before = NSPasteboard.general.string(forType: .string) ?? ""
    let beforeCount = NSPasteboard.general.changeCount
    Diagnostics.section("--copy-probe")
    Diagnostics.log("原剪贴板 长度=\(before.count)")
    print(L10n.t("cli.clipboardBefore", before.count))
    if let result = CopyFallback.copySelection() {
        Diagnostics.log("兜底取到 长度=\(result.text.count) 已还原=\(result.restored ? "是" : "否")")
        print(L10n.t("cli.copiedText", result.text.count))
        print(result.text)
        print(L10n.t("cli.restored", result.restored ? L10n.t("cli.yes") : L10n.t("cli.no")))
    } else {
        Diagnostics.log("兜底没有复制到内容")
        print(L10n.t("cli.copyProbeEmpty"))
    }
    let after = NSPasteboard.general.string(forType: .string) ?? ""
    print(L10n.t("cli.clipboardAfter", after.count, NSPasteboard.general.changeCount - beforeCount))
    exit(0)
}

// MARK: - GUI 模式

let application = NSApplication.shared
let delegate = AppDelegate()
delegate.openSettingsOnLaunch = arguments.contains("--settings")
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
