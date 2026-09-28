import AppKit
import AnywhereDoCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// 仅用于 `--settings` 调试。
    var openSettingsOnLaunch = false

    private let store = SettingsStore()
    private let analyzer = Analyzer()
    private let watcher = PasteboardWatcher()
    private let selectionWatcher = SelectionWatcher()
    private let popup = PopupController()
    private let runner = ActionRunner()

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var lastAnalysis: ClipboardAnalysis?
    private var lastSourceApp: String?
    private var lastAnchor: PopupAnchor = .point(.zero)
    /// 「划词」和「复制」可能对同一段文字各触发一次，短时间内去重。
    private var lastTrigger: (text: String, date: Date)?
    /// 检查更新发现的可用新版本（nil = 已是最新或还没查到）。
    private var availableUpdate: UpdateInfo?
    private var recent: [(text: String, analysis: ClipboardAnalysis)] = []
    private var aiTask: Task<Void, Never>?
    /// 用户在系统设置里勾选「辅助功能」后，不需要重启 App 就能生效。
    private var permissionTimer: Timer?
    /// 正在为兜底合成 ⌘C：这期间出现剪贴板变化是「自己人干的」，不当作复制事件。
    private var isSynthesizingCopy = false

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        runner.onPasteboardWrite = { [weak self] in
            self?.watcher.acknowledgeCurrentChange()
        }
        watcher.onEvent = { [weak self] event in
            self?.handleClipboard(event)
        }
        selectionWatcher.onEvent = { [weak self] event in
            self?.handleSelection(event)
        }
        selectionWatcher.shouldUseCopyFallback = { [weak self] in
            guard let self else { return false }
            let settings = self.store.settings
            guard settings.enabled, settings.watchSelection, settings.selectionCopyFallback else { return false }
            if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               settings.ignoredBundleIDs.contains(bundleID) {
                return false
            }
            return true
        }
        selectionWatcher.onTyping = { [weak self] in
            // 用户开始打字，说明他不需要建议了，弹窗立刻让开。
            guard let self, self.popup.isVisible else { return }
            self.popup.close()
        }
        selectionWatcher.willSynthesizeCopy = { [weak self] in
            self?.isSynthesizingCopy = true
        }
        selectionWatcher.didSynthesizeCopy = { [weak self] in
            guard let self else { return }
            // 先把我们写回去的那次改动消费掉，再解除标记。
            self.watcher.acknowledgeCurrentChange()
            self.isSynthesizingCopy = false
        }
        // 我们自己的弹窗 / 设置窗口拿着焦点时，暂停划词判断。
        selectionWatcher.isSuppressed = { [weak self] in
            guard let self else { return true }
            if self.popup.isVisible { return true }
            // 只有「我们自己的窗口正在被操作」时才抑制。
            // 设置窗口仅仅「开着」不算——否则你在别的 App 里划词会被它一直拦掉。
            return NSApp.isActive
        }
        store.onChange = { [weak self] settings in
            self?.apply(settings)
        }

        Diagnostics.section("启动")
        Diagnostics.log("权限=" + (SelectionWatcher.isTrusted ? "已授予" : "未授予"))
        Diagnostics.log("bundle=" + (Bundle.main.bundleIdentifier ?? "nil") + " path=" + Bundle.main.bundlePath)
        Diagnostics.log("参数=" + CommandLine.arguments.joined(separator: " "))

        installMainMenu()
        setupStatusItem()
        apply(store.settings)
        promptForAccessibilityIfNeeded()

        let permissionTimer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.syncWatchersWithSettings()
        }
        RunLoop.main.add(permissionTimer, forMode: .common)
        self.permissionTimer = permissionTimer

        if openSettingsOnLaunch {
            openSettings()
        }

        scheduleAutomaticUpdateCheck()
    }

    // MARK: - 检查更新

    private func scheduleAutomaticUpdateCheck() {
        guard store.settings.checkForUpdates else { return }
        if let last = store.settings.lastUpdateCheck,
           Date().timeIntervalSince(last) < UpdateChecker.minimumInterval {
            Diagnostics.log("检查更新：距上次不足 6 小时，跳过自动检查")
            return
        }
        // 启动后晚一点再查，别和权限引导之类抢戏。
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.performUpdateCheck(manual: false)
        }
    }

    private func performUpdateCheck(manual: Bool) {
        guard manual || store.settings.checkForUpdates else { return }
        UpdateChecker.check { [weak self] info in
            guard let self else { return }
            self.store.update { $0.lastUpdateCheck = Date() }
            self.availableUpdate = info
            self.rebuildMenu()
            guard manual else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            if let info {
                alert.messageText = L10n.t("alert.updateAvailable", info.version)
                alert.informativeText = L10n.t("alert.updateAvailableBody", AnywhereDoVersion.marketing)
                alert.addButton(withTitle: L10n.t("alert.openDownload"))
                alert.addButton(withTitle: L10n.t("alert.later"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(info.url)
                }
            } else {
                alert.messageText = L10n.t("alert.upToDate")
                alert.informativeText = L10n.t("alert.upToDateBody", AnywhereDoVersion.marketing)
                alert.addButton(withTitle: L10n.t("alert.ok"))
                alert.runModal()
            }
        }
    }

    @objc private func checkForUpdatesNow() {
        performUpdateCheck(manual: true)
    }

    @objc private func openUpdatePage() {
        guard let info = availableUpdate else { return }
        NSWorkspace.shared.open(info.url)
    }

    /// 权限可能在使用过程中才被授予：定期比对一下运行状态，需要时重新应用设置。
    private func syncWatchersWithSettings() {
        let settings = store.settings
        let shouldWatchSelection = settings.enabled && settings.watchSelection && SelectionWatcher.isTrusted
        if shouldWatchSelection != selectionWatcher.isRunning {
            apply(settings)
        }
    }

    /// 划词开着却没有权限时，主动提醒一次（否则用户只会觉得「没效果」）。
    private func promptForAccessibilityIfNeeded() {
        let settings = store.settings
        guard settings.enabled, settings.watchSelection, !SelectionWatcher.isTrusted else { return }
        guard !settings.didPromptForAccessibility else {
            Diagnostics.log("划词未启用：缺少辅助功能权限（已提醒过，只留菜单里的警告）")
            return
        }
        store.update { $0.didPromptForAccessibility = true }
        Diagnostics.log("划词未启用：弹出授权引导")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            // 先只弹自己的说明框；用户点了「打开设置」再触发系统授权框，
            // 系统框会把 App 自动加进辅助功能列表，避免两个弹窗叠在一起。
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.t("alert.accessibilityTitle")
            alert.informativeText = L10n.t("alert.accessibilityBody", Bundle.main.bundlePath)
            alert.addButton(withTitle: L10n.t("alert.openAccessibility"))
            alert.addButton(withTitle: L10n.t("alert.later"))
            if alert.runModal() == .alertFirstButtonReturn {
                _ = SelectionWatcher.requestPermission()
                SelectionWatcher.openAccessibilitySettings()
                Diagnostics.log("用户同意授权，已打开系统设置")
            } else {
                Diagnostics.log("用户选择稍后授权")
            }
            self.refreshRuntimeState()
        }
    }

    private func refreshRuntimeState() {
        apply(store.settings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
    }

    private func apply(_ settings: AppSettings) {
        popup.offset = CGFloat(settings.popupOffset)
        popup.keyboardShortcuts = settings.keyboardShortcuts

        if settings.enabled && settings.watchClipboard {
            watcher.isPaused = false
            watcher.start()
        } else {
            watcher.stop()
        }

        selectionWatcher.setCopyFallbackEnabled(settings.selectionCopyFallback)
        if settings.enabled && settings.watchSelection && SelectionWatcher.isTrusted {
            selectionWatcher.isPaused = false
            selectionWatcher.start()
        } else {
            selectionWatcher.stop()
        }
        if !settings.enabled {
            popup.close()
        }
        updateStatusItemAppearance()
    }

    // MARK: - 剪贴板事件

    private func handleClipboard(_ event: ClipboardEvent) {
        // 兜底合成的 ⌘C 也会改剪贴板，那是我们自己制造的，不算用户复制。
        guard !isSynthesizingCopy else { return }
        handle(
            text: event.text,
            sourceAppName: event.sourceAppName,
            sourceBundleID: event.sourceBundleID,
            isSensitive: event.isSensitive,
            anchor: .point(NSEvent.mouseLocation),
            compact: false
        )
    }

    private func handleSelection(_ event: SelectionEvent) {
        let anchor: PopupAnchor = event.bounds.map { PopupAnchor.selection($0) }
            ?? .point(event.anchorPoint ?? NSEvent.mouseLocation)
        handle(
            text: event.text,
            sourceAppName: event.sourceAppName,
            sourceBundleID: event.sourceBundleID,
            isSensitive: event.isSensitive,
            anchor: anchor,
            compact: store.settings.selectionCompact,
            estimatedLineCount: event.estimatedLineCount
        )
    }

    private func handle(
        text: String,
        sourceAppName: String?,
        sourceBundleID: String?,
        isSensitive: Bool,
        anchor: PopupAnchor,
        compact: Bool,
        estimatedLineCount: Int? = nil
    ) {
        let settings = store.settings
        guard settings.enabled, !text.isEmpty else { return }
        if let sourceBundleID {
            if sourceBundleID == Bundle.main.bundleIdentifier { return }
            if settings.ignoredBundleIDs.contains(sourceBundleID) { return }
        }
        if settings.ignoreSensitive && isSensitive { return }

        // 同一段文字在 1.2s 内被「复制」和「划词」各触发一次时，只弹一次。
        if let last = lastTrigger, last.text == text, Date().timeIntervalSince(last.date) < 1.2 {
            return
        }
        lastTrigger = (text, Date())
        Diagnostics.log("触发：\(sourceBundleID ?? "?") 长度=\(text.count) 锚点=\(anchor.isSelection ? "选区" : "鼠标")")

        let analysis = analyzer.analyze(
            text,
            options: AnalysisOptions(
                maxLength: settings.maxContentLength,
                aiEnabled: settings.ai.isUsable,
                estimatedLineCount: estimatedLineCount
            )
        )
        guard analysis.kind != .empty else { return }

        lastAnalysis = analysis
        lastSourceApp = sourceAppName
        lastAnchor = anchor
        remember(analysis)
        present(analysis: analysis, sourceApp: sourceAppName, anchor: anchor, compact: compact)
    }

    private func remember(_ analysis: ClipboardAnalysis) {
        recent.insert((analysis.text, analysis), at: 0)
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
    }

    private func present(analysis: ClipboardAnalysis, sourceApp: String?, anchor: PopupAnchor, compact: Bool) {
        let card = SuggestionCardView(
            analysis: analysis,
            sourceApp: sourceApp,
            showPreview: store.settings.showPreview,
            compact: compact
        )
        card.onSelect = { [weak self] suggestion in
            self?.perform(suggestion)
        }
        card.onExpand = { [weak self] in
            guard let self else { return }
            self.present(analysis: analysis, sourceApp: sourceApp, anchor: anchor, compact: false)
        }
        let delay = store.settings.autoDismissSeconds > 0 ? store.settings.autoDismissSeconds : nil
        popup.showCard(card, anchor: anchor, dismissAfter: delay)
    }

    // MARK: - 执行建议

    private func perform(_ suggestion: Suggestion) {
        switch runner.perform(suggestion.action) {
        case .done(let message):
            showToast(message)
        case .failure(let message):
            showToast(message, symbol: "exclamationmark.triangle.fill", tint: .systemRed)
        case .showResult(let title, let body, let monospaced):
            showResult(title: title, body: body, monospaced: monospaced)
        case .aiPending(let preset, let source):
            runAI(preset: preset, source: source)
        }
    }

    private func showToast(_ message: String, symbol: String = "checkmark.circle.fill", tint: NSColor = .systemGreen) {
        let card = ToastCardView(message: message, symbol: symbol, tint: tint)
        popup.showCard(card, anchor: lastAnchor, dismissAfter: 1.1)
    }

    private func showResult(title: String, body: String, monospaced: Bool, isError: Bool = false) {
        let card = ResultCardView(title: title, body: body, monospaced: monospaced, isError: isError)
        card.onCopy = { [weak self] text in
            self?.runner.writeToPasteboard(text)
            self?.showToast(L10n.t("toast.copiedResult"))
        }
        card.onBack = { [weak self] in
            guard let self, let analysis = self.lastAnalysis else { return }
            self.present(analysis: analysis, sourceApp: self.lastSourceApp, anchor: self.lastAnchor, compact: false)
        }
        popup.showCard(card, anchor: lastAnchor, dismissAfter: nil)
    }

    private func runAI(preset: AIPreset, source: String) {
        guard store.settings.ai.isUsable else {
            showToast(L10n.t("toast.aiNotConfigured"), symbol: "gearshape", tint: .systemOrange)
            return
        }
        let client = AIClient(config: store.settings.ai)
        popup.showCard(LoadingCardView(title: "\(preset.title)…"), anchor: lastAnchor, dismissAfter: nil)

        aiTask?.cancel()
        aiTask = Task { [self] in
            do {
                let text = try await client.complete(preset: preset, content: source)
                await MainActor.run {
                    self.showResult(title: preset.title, body: text, monospaced: false)
                }
            } catch {
                await MainActor.run {
                    self.showResult(title: L10n.t("toast.aiFailed", preset.title), body: error.localizedDescription, monospaced: false, isError: true)
                }
            }
        }
    }

    // MARK: - 主菜单

    /// 菜单栏 App（LSUIElement）默认没有主菜单，而 AppKit 的
    /// ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z 是靠「编辑」菜单的快捷键派发到响应链的——
    /// 没有这个菜单，我们设置窗口里的文本框就不能粘贴、不能全选。
    /// 这个菜单不会显示出来（App 没有菜单栏），但快捷键会正常工作。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: L10n.t("menu.diagnostics"), action: #selector(openDiagnostics), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: L10n.t("menu.about"), action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("menu.quitApp"), action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // 关键：这些 item 不给 target，nil-target 动作会沿响应链找到当前文本框。
        let editMenu = NSMenu(title: L10n.t("menu.edit"))
        editMenu.addItem(withTitle: L10n.t("menu.undo"), action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.t("menu.redo"), action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.t("menu.cut"), action: NSSelectorFromString("cut:"), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("menu.copy"), action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("menu.paste"), action: NSSelectorFromString("paste:"), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("menu.delete"), action: NSSelectorFromString("delete:"), keyEquivalent: "")
        editMenu.addItem(withTitle: L10n.t("menu.selectAll"), action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowMenu = NSMenu(title: L10n.t("menu.window"))
        windowMenu.addItem(withTitle: L10n.t("menu.close"), action: NSSelectorFromString("performClose:"), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusItemAppearance()
        rebuildMenu()
    }

    /// 菜单栏图标：优先用 Resources/MenuBarIconTemplate.png（scripts/build_icons.sh 生成），
    /// 直接 `swift run` 时没有 bundle 资源，退回 SF Symbol。
    private static func statusBarImage() -> NSImage? {
        let size = NSSize(width: 18, height: 18)

        // 按名字查 bundle：AppKit 会自动把 @2x 一起加载进来，Retina 不糊。
        if let image = NSImage(named: NSImage.Name("MenuBarIconTemplate")) {
            image.isTemplate = true
            image.size = size
            return image
        }

        // 兜底：名字查找失败时，手动把 1x / 2x 两个表示拼起来。
        let image = NSImage(size: size)
        for name in ["MenuBarIconTemplate", "MenuBarIconTemplate@2x"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = size          // 点尺寸固定 18pt，像素数决定倍率
            image.addRepresentation(rep)
        }
        if image.representations.isEmpty {
            return NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "AnywhereDo")
        }
        image.isTemplate = true
        return image
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let image = Self.statusBarImage()
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !store.settings.enabled
        if !store.settings.enabled {
            button.toolTip = L10n.t("status.paused")
        } else if store.settings.watchSelection && !SelectionWatcher.isTrusted {
            button.toolTip = L10n.t("status.needsAccessibility")
        } else {
            button.toolTip = L10n.t("status.listening")
        }
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let header = NSMenuItem(title: L10n.t("menu.header"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if let update = availableUpdate {
            let item = NSMenuItem(
                title: L10n.t("menu.newVersion", update.version),
                action: #selector(openUpdatePage),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let master = NSMenuItem(title: L10n.t("menu.enable"), action: #selector(toggleEnabled), keyEquivalent: "")
        master.target = self
        master.state = store.settings.enabled ? .on : .off
        menu.addItem(master)

        let clipboard = NSMenuItem(title: L10n.t("menu.watchClipboard"), action: #selector(toggleClipboard), keyEquivalent: "")
        clipboard.target = self
        clipboard.state = store.settings.watchClipboard ? .on : .off
        menu.addItem(clipboard)

        let selection = NSMenuItem(title: L10n.t("menu.watchSelection"), action: #selector(toggleSelection), keyEquivalent: "")
        selection.target = self
        selection.state = store.settings.watchSelection ? .on : .off
        menu.addItem(selection)

        let fallback = NSMenuItem(
            title: L10n.t("menu.copyFallback"),
            action: #selector(toggleCopyFallback),
            keyEquivalent: ""
        )
        fallback.target = self
        fallback.state = store.settings.selectionCopyFallback ? .on : .off
        menu.addItem(fallback)

        if store.settings.watchSelection && !SelectionWatcher.isTrusted {
            let permission = NSMenuItem(
                title: L10n.t("menu.grantAccessibility"),
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            permission.target = self
            menu.addItem(permission)
        }

        menu.addItem(.separator())

        let analyze = NSMenuItem(title: L10n.t("menu.analyzeClipboard"), action: #selector(analyzeNow), keyEquivalent: "")
        analyze.target = self
        menu.addItem(analyze)

        let diagnose = NSMenuItem(title: L10n.t("menu.selfCheck"), action: #selector(diagnoseSelection), keyEquivalent: "")
        diagnose.target = self
        menu.addItem(diagnose)

        let logItem = NSMenuItem(title: L10n.t("menu.diagnostics"), action: #selector(openDiagnostics), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        if !recent.isEmpty {
            menu.addItem(.separator())
            let recentItem = NSMenuItem(title: L10n.t("menu.recent"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (index, entry) in recent.enumerated() {
                let title = "\(index + 1). " + shortLabel(entry.analysis)
                let item = NSMenuItem(title: title, action: #selector(showRecent(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.toolTip = entry.analysis.headline
                submenu.addItem(item)
            }
            recentItem.submenu = submenu
            menu.addItem(recentItem)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let config = NSMenuItem(title: L10n.t("menu.openConfig"), action: #selector(openConfigFile), keyEquivalent: "")
        config.target = self
        menu.addItem(config)

        let checkUpdate = NSMenuItem(title: L10n.t("menu.checkUpdate"), action: #selector(checkForUpdatesNow), keyEquivalent: "")
        checkUpdate.target = self
        menu.addItem(checkUpdate)

        let about = NSMenuItem(title: L10n.t("menu.about"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func shortLabel(_ analysis: ClipboardAnalysis) -> String {
        let preview = analysis.text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let trimmed = preview.count > 28 ? String(preview.prefix(28)) + "…" : preview
        return "[\(analysis.kind.displayName)] \(trimmed)"
    }

    // MARK: - 菜单动作

    @objc private func toggleEnabled() {
        store.update { $0.enabled.toggle() }
    }

    @objc private func toggleClipboard() {
        store.update { $0.watchClipboard.toggle() }
    }

    @objc private func toggleCopyFallback() {
        store.update { $0.selectionCopyFallback.toggle() }
        Diagnostics.log("⌘C 兜底：" + (store.settings.selectionCopyFallback ? "开启" : "关闭"))
    }

    @objc private func toggleSelection() {
        let turningOn = !store.settings.watchSelection
        store.update { $0.watchSelection = turningOn }
        if turningOn && !SelectionWatcher.isTrusted {
            _ = SelectionWatcher.requestPermission()
            SelectionWatcher.openAccessibilitySettings()
        }
    }

    @objc private func openDiagnostics() {
        Diagnostics.log("用户打开了诊断日志；权限=" + (SelectionWatcher.isTrusted ? "已授予" : "未授予")
            + L10n.t("selfcheck.running", selectionWatcher.isRunning ? L10n.t("cli.yes") : L10n.t("cli.no")))
        Diagnostics.reveal()
    }

    @objc private func requestAccessibility() {
        _ = SelectionWatcher.requestPermission()
        SelectionWatcher.openAccessibilitySettings()
    }

    /// 自检：确认当前 App 能不能通过辅助功能读到选区。
    @objc private func diagnoseSelection() {
        NSApp.activate(ignoringOtherApps: true)
        let selectionInfo = Accessibility.currentSelectionText().map { L10n.t("selfcheck.readSome", $0.count) } ?? L10n.t("selfcheck.noSelectionShort")
        Diagnostics.log("自检：权限=" + (SelectionWatcher.isTrusted ? "已授予" : "未授予") + " " + selectionInfo)
        let alert = NSAlert()
        alert.messageText = L10n.t("selfcheck.title")
        var lines: [String] = []

        lines.append(SelectionWatcher.isTrusted ? L10n.t("selfcheck.granted") : L10n.t("selfcheck.denied"))
        if let app = NSWorkspace.shared.frontmostApplication {
            lines.append(L10n.t("selfcheck.frontmost", app.localizedName ?? L10n.t("cli.unknownApp")))
        }
        if let text = Accessibility.currentSelectionText(), !text.isEmpty {
            let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
            lines.append(L10n.t("selfcheck.readSelection", text.count, preview))
            lines.append(L10n.t("selfcheck.boundsNote"))
        } else {
            lines.append(L10n.t("selfcheck.noSelection"))
            lines.append(L10n.t("selfcheck.permissionHint"))
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: L10n.t("alert.ok"))
        if !SelectionWatcher.isTrusted {
            alert.addButton(withTitle: L10n.t("selfcheck.openSettings"))
            if alert.runModal() == .alertSecondButtonReturn {
                SelectionWatcher.openAccessibilitySettings()
            }
        } else {
            alert.runModal()
        }
    }

    @objc private func analyzeNow() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            showToast(L10n.t("toast.noTextOnClipboard"), symbol: "clipboard", tint: .systemOrange)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        handle(
            text: text,
            sourceAppName: frontmost?.localizedName,
            sourceBundleID: frontmost?.bundleIdentifier,
            isSensitive: false,
            anchor: .point(NSEvent.mouseLocation),
            compact: false
        )
    }

    @objc private func showRecent(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < recent.count else { return }
        let entry = recent[sender.tag]
        lastAnalysis = entry.analysis
        lastAnchor = .point(NSEvent.mouseLocation)
        present(analysis: entry.analysis, sourceApp: nil, anchor: lastAnchor, compact: false)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: store)
        }
        settingsWindow?.show()
    }

    @objc private func openConfigFile() {
        store.revealInFinder()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AnywhereDo \(AnywhereDoVersion.marketing)"
        alert.informativeText = """
        复制任意内容，鼠标旁边就会出现针对内容的建议。

        · 链接 → 打开 / 复制 Markdown
        · JSON → 格式化
        · 颜色 → HEX / RGB / SwiftUI
        · 时间戳 → 本地时间
        · 算式 → 结果
        · 代码 → 搜索报错 / AI 解释

        设置文件：\(SettingsStore.fileURL.path)
        """
        alert.addButton(withTitle: L10n.t("alert.ok"))
        alert.runModal()
    }

    @objc private func quit() {
        watcher.stop()
        NSApp.terminate(nil)
    }
}
