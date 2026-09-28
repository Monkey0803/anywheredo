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

if let index = arguments.firstIndex(of: "--render-hover") {
    // 把悬停小图标渲染成 PNG，用来肉眼确认外观（不需要辅助功能权限）。
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let scale: CGFloat = 6
    let canvas = NSSize(width: 60, height: 40)
    let container = NSView(frame: NSRect(origin: .zero, size: canvas))
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let icon = HoverIconView(symbol: "sparkles")
    icon.frame = NSRect(
        x: (canvas.width - HoverIconView.side) / 2,
        y: (canvas.height - HoverIconView.side) / 2,
        width: HoverIconView.side,
        height: HoverIconView.side
    )
    container.addSubview(icon)
    container.layoutSubtreeIfNeeded()

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width * scale),
        pixelsHigh: Int(canvas.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { print("无法创建位图"); exit(4) }
    rep.size = canvas
    container.cacheDisplay(in: container.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { print("PNG 编码失败"); exit(4) }
    let path = index + 1 < arguments.count ? arguments[index + 1] : "/tmp/anywheredo-hover.png"
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        print("写文件失败：\(error.localizedDescription)")
        exit(4)
    }
    print("已渲染小图标：\(path)（\(Int(canvas.width * scale))x\(Int(canvas.height * scale)) 像素，图标 \(Int(HoverIconView.side))pt）")
    exit(0)
}

if arguments.contains("--hover-demo") {
    // 验证「悬停展开」这条链路：先直接调回调（验证接线），再合成鼠标移动（验证系统投递）。
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()

    let popup = PopupController()
    var expandCount = 0
    let icon = HoverIconView(symbol: "sparkles")
    icon.onExpand = { expandCount += 1 }

    let mouse = NSEvent.mouseLocation
    popup.showCard(icon, anchor: .point(NSPoint(x: mouse.x + 60, y: mouse.y)), dismissAfter: nil)
    guard let frame = icon.window?.frame, icon.window?.isVisible == true else {
        print("小图标面板没有显示出来")
        exit(3)
    }
    print("小图标面板：\(Int(frame.width))x\(Int(frame.height))，位置=(\(Int(frame.origin.x)),\(Int(frame.origin.y)))")
    let areas = icon.trackingAreas
    print("追踪区域：\(areas.count) 个" + (areas.first.map { "，范围=\(Int($0.rect.width))x\(Int($0.rect.height))" } ?? ""))

    if let enter = NSEvent.enterExitEvent(
        with: .mouseEntered,
        location: NSPoint(x: frame.midX, y: frame.midY),
        modifierFlags: [],
        timestamp: Date().timeIntervalSince1970,
        windowNumber: icon.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 0,
        trackingNumber: 0,
        userData: nil
    ) {
        icon.mouseEntered(with: enter)
    }
    let wired = expandCount > 0
    print(wired ? "✅ 回调接线正确（mouseEntered → onExpand）" : "❌ 回调没有接到 onExpand")
    expandCount = 0

    // 合成一次「扫入」：从图标外侧一路移动到图标中心，比单次跳跃更容易触发进入事件。
    var delivered: Bool? = nil
    if let screen = NSScreen.screens.first {
        let before = NSEvent.mouseLocation
        let outside = NSPoint(x: frame.midX + 80, y: frame.midY)
        func post(_ cocoa: NSPoint) {
            let quartz = CGPoint(x: cocoa.x, y: screen.frame.height - cocoa.y)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartz, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        post(outside)
        // 合成 .mouseMoved 未必真的移动指针，先用 warp 把它强制挪到图标外侧。
        CGWarpMouseCursorPosition(CGPoint(x: outside.x, y: screen.frame.height - outside.y))
        CGAssociateMouseAndMouseCursorPosition(1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let steps = 12
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(NSPoint(x: outside.x + (frame.midX - outside.x) * t,
                         y: outside.y + (frame.midY - outside.y) * t))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        // 再补一个 warp 直接落到中心，并配一个 move 事件让追踪机制看到「进入」。
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: screen.frame.height - frame.midY))
        post(NSPoint(x: frame.midX, y: frame.midY))
        let deadline = Date().addingTimeInterval(2)
        while expandCount == 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let after = NSEvent.mouseLocation
        print(String(format: "光标位置：前=(%.0f,%.0f) 后=(%.0f,%.0f) 图标中心=(%.0f,%.0f)",
                     before.x, before.y, after.x, after.y, frame.midX, frame.midY))
        delivered = expandCount > 0
    }
    if let delivered {
        if delivered {
            print("✅ 系统投递生效：合成鼠标扫入图标触发了 mouseEntered")
        } else {
            print("⚠️ 系统没有投递 mouseEntered。本进程也无法用合成事件移动光标（warp 与 mouseMoved 都无效），")
            print("   所以「真实鼠标进入」这一段在终端里验不了 —— 请在应用里用鼠标悬停一次确认。")
        }
    } else {
        print("⚠️ 没能构造合成鼠标事件")
    }
    popup.close()
    exit(wired ? 0 : 2)
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
