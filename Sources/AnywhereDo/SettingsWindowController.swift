import AppKit
import AnywhereDoCore
import ServiceManagement

/// 纯代码搭的设置窗口，避免依赖 xib/storyboard。
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore

    // 触发方式
    private let enabledCheckbox = NSButton(checkboxWithTitle: "启用 AnywhereDo", target: nil, action: nil)
    private let clipboardCheckbox = NSButton(checkboxWithTitle: "复制后弹出建议", target: nil, action: nil)
    private let selectionCheckbox = NSButton(checkboxWithTitle: "划词即弹：选中文字后就在选区旁弹出（需要辅助功能权限）", target: nil, action: nil)
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "请求权限", target: nil, action: nil)
    private let accessibilitySettingsButton = NSButton(title: "打开系统设置", target: nil, action: nil)

    // 弹窗
    private let previewCheckbox = NSButton(checkboxWithTitle: "在弹窗中显示内容预览", target: nil, action: nil)
    private let selectionCompactCheckbox = NSButton(checkboxWithTitle: "划词时使用紧凑卡片（不显示预览，最多 3 条建议）", target: nil, action: nil)
    private let selectionFallbackCheckbox = NSButton(checkboxWithTitle: "对读不到选区的 App 用 ⌘C 兜底（Chrome/Electron；会短暂改写剪贴板并立即还原）", target: nil, action: nil)
    private let keyboardCheckbox = NSButton(checkboxWithTitle: "启用键盘快捷键（1-9 选择、Esc 关闭）", target: nil, action: nil)
    private let autoDismissPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let maxLengthPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    // 隐私与启动
    private let sensitiveCheckbox = NSButton(checkboxWithTitle: "忽略密码管理器等标记为敏感/临时的内容", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "登录时自动启动", target: nil, action: nil)
    private let checkUpdatesCheckbox = NSButton(checkboxWithTitle: "启动时检查更新（只向 GitHub 发一个 GET，不含任何个人信息）", target: nil, action: nil)
    private let ignoredAppsField = NSTextField(string: "")

    // AI
    private let aiEnabledCheckbox = NSButton(checkboxWithTitle: "启用 AI 建议（需要 OpenAI 兼容接口）", target: nil, action: nil)
    private let aiBaseURLField = NSTextField(string: "")
    private let aiModelField = NSTextField(string: "")
    private let aiKeyField = NSSecureTextField(string: "")
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let testStatusLabel = NSTextField(labelWithString: "")

    private let autoDismissOptions: [(title: String, seconds: Double)] = [
        ("不自动关闭", 0), ("3 秒", 3), ("5 秒", 5), ("8 秒", 8), ("15 秒", 15), ("30 秒", 30),
    ]
    private let maxLengthOptions: [Int] = [1000, 3000, 6000, 12000]

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AnywhereDo 设置"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 580, height: 420)
        super.init(window: window)
        buildUI()
        syncFromSettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        syncFromSettings()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        // 菜单栏 App 不一定能抢到激活权，这里强制前置一次。
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 触发方式
        stack.addArrangedSubview(sectionTitle("触发方式"))
        for control in [enabledCheckbox, clipboardCheckbox, selectionCheckbox] {
            wire(control)
            stack.addArrangedSubview(control)
        }
        wire(selectionFallbackCheckbox)
        stack.addArrangedSubview(selectionFallbackCheckbox)
        accessibilityStatusLabel.font = .systemFont(ofSize: 11)
        accessibilityStatusLabel.textColor = .secondaryLabelColor
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibility)
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.controlSize = .small
        accessibilitySettingsButton.target = self
        accessibilitySettingsButton.action = #selector(openAccessibilitySettings)
        accessibilitySettingsButton.bezelStyle = .rounded
        accessibilitySettingsButton.controlSize = .small
        let accessibilityRow = NSStackView(views: [accessibilityStatusLabel, accessibilityButton, accessibilitySettingsButton])
        accessibilityRow.orientation = .horizontal
        accessibilityRow.alignment = .centerY
        accessibilityRow.spacing = 8
        stack.addArrangedSubview(accessibilityRow)

        stack.addArrangedSubview(separatorBox())
        stack.addArrangedSubview(sectionTitle("弹窗"))

        for control in [previewCheckbox, selectionCompactCheckbox, keyboardCheckbox] {
            wire(control)
            stack.addArrangedSubview(control)
        }

        for option in autoDismissOptions {
            autoDismissPopup.addItem(withTitle: option.title)
        }
        autoDismissPopup.target = self
        autoDismissPopup.action = #selector(generalChanged)
        for length in maxLengthOptions {
            maxLengthPopup.addItem(withTitle: "\(length) 字符")
        }
        maxLengthPopup.target = self
        maxLengthPopup.action = #selector(generalChanged)
        stack.addArrangedSubview(grid(rows: [
            ("弹窗停留时间", autoDismissPopup),
            ("分析的最大长度", maxLengthPopup),
        ]))

        stack.addArrangedSubview(separatorBox())
        stack.addArrangedSubview(sectionTitle("隐私与启动"))

        wire(sensitiveCheckbox)
        stack.addArrangedSubview(sensitiveCheckbox)
        ignoredAppsField.placeholderString = "com.example.app, com.other.app"
        ignoredAppsField.target = self
        ignoredAppsField.action = #selector(generalChanged)
        stack.addArrangedSubview(grid(rows: [
            ("忽略这些 App", ignoredAppsField),
        ]))
        wire(launchAtLoginCheckbox)
        stack.addArrangedSubview(launchAtLoginCheckbox)
        wire(checkUpdatesCheckbox)
        stack.addArrangedSubview(checkUpdatesCheckbox)

        stack.addArrangedSubview(separatorBox())
        stack.addArrangedSubview(sectionTitle("AI 建议"))

        wire(aiEnabledCheckbox)
        stack.addArrangedSubview(aiEnabledCheckbox)

        aiBaseURLField.placeholderString = "https://api.deepseek.com/v1"
        aiModelField.placeholderString = "deepseek-chat"
        aiKeyField.placeholderString = "sk-..."
        for field in [aiBaseURLField, aiModelField, aiKeyField] {
            field.target = self
            field.action = #selector(generalChanged)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        }
        stack.addArrangedSubview(grid(rows: [
            ("Base URL", aiBaseURLField),
            ("模型", aiModelField),
            ("API Key", aiKeyField),
        ]))

        testButton.target = self
        testButton.action = #selector(testConnection)
        testButton.bezelStyle = .rounded
        testStatusLabel.font = .systemFont(ofSize: 11)
        testStatusLabel.textColor = .secondaryLabelColor
        testStatusLabel.lineBreakMode = .byTruncatingTail
        testStatusLabel.maximumNumberOfLines = 2
        let testRow = NSStackView(views: [testButton, testStatusLabel])
        testRow.orientation = .horizontal
        testRow.alignment = .centerY
        testRow.spacing = 10
        stack.addArrangedSubview(testRow)

        stack.addArrangedSubview(separatorBox())
        let footer = NSTextField(wrappingLabelWithString:
            "配置保存在 \(SettingsStore.fileURL.path)（权限 600），可直接编辑。\n"
            + "提示：macOS 首次读取剪贴板时会询问是否允许粘贴，需要选择「允许」才能给出建议。")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.preferredMaxLayoutWidth = 520
        stack.addArrangedSubview(footer)

        // 放进滚动视图，窗口变矮时也不会裁掉内容
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = documentView

        window.contentView = scroll
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    private func wire(_ control: NSButton) {
        control.target = self
        control.action = #selector(generalChanged)
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func separatorBox() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return box
    }

    private func grid(rows: [(String, NSView)]) -> NSGridView {
        let views: [[NSView]] = rows.map { row in
            let label = NSTextField(labelWithString: row.0)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            return [label, row.1]
        }
        let grid = NSGridView(views: views)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    // MARK: - 同步

    private func syncFromSettings() {
        let settings = store.settings
        enabledCheckbox.state = settings.enabled ? .on : .off
        clipboardCheckbox.state = settings.watchClipboard ? .on : .off
        selectionCheckbox.state = settings.watchSelection ? .on : .off
        previewCheckbox.state = settings.showPreview ? .on : .off
        selectionCompactCheckbox.state = settings.selectionCompact ? .on : .off
        selectionFallbackCheckbox.state = settings.selectionCopyFallback ? .on : .off
        keyboardCheckbox.state = settings.keyboardShortcuts ? .on : .off
        sensitiveCheckbox.state = settings.ignoreSensitive ? .on : .off
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off
        checkUpdatesCheckbox.state = settings.checkForUpdates ? .on : .off

        if let index = autoDismissOptions.firstIndex(where: { $0.seconds == settings.autoDismissSeconds }) {
            autoDismissPopup.selectItem(at: index)
        } else {
            autoDismissPopup.selectItem(at: 3)
        }
        if let index = maxLengthOptions.firstIndex(of: settings.maxContentLength) {
            maxLengthPopup.selectItem(at: index)
        } else {
            maxLengthPopup.selectItem(at: 1)
        }
        ignoredAppsField.stringValue = settings.ignoredBundleIDs.joined(separator: ", ")

        aiEnabledCheckbox.state = settings.ai.enabled ? .on : .off
        aiBaseURLField.stringValue = settings.ai.baseURL
        aiModelField.stringValue = settings.ai.model
        aiKeyField.stringValue = settings.ai.apiKey

        refreshAccessibilityStatus()
    }

    private func refreshAccessibilityStatus() {
        if SelectionWatcher.isTrusted {
            accessibilityStatusLabel.textColor = .systemGreen
            accessibilityStatusLabel.stringValue = "辅助功能权限：已授予 ✅"
            accessibilityButton.isEnabled = false
        } else {
            accessibilityStatusLabel.textColor = .systemOrange
            accessibilityStatusLabel.stringValue = "辅助功能权限：未授予（划词需要，复制模式不需要）"
            accessibilityButton.isEnabled = true
        }
    }

    // MARK: - 动作

    @objc private func generalChanged() {
        store.update { settings in
            settings.enabled = enabledCheckbox.state == .on
            settings.watchClipboard = clipboardCheckbox.state == .on
            settings.watchSelection = selectionCheckbox.state == .on
            settings.showPreview = previewCheckbox.state == .on
            settings.selectionCompact = selectionCompactCheckbox.state == .on
            settings.selectionCopyFallback = selectionFallbackCheckbox.state == .on
            settings.keyboardShortcuts = keyboardCheckbox.state == .on
            settings.ignoreSensitive = sensitiveCheckbox.state == .on
            if autoDismissPopup.indexOfSelectedItem >= 0,
               autoDismissPopup.indexOfSelectedItem < autoDismissOptions.count {
                settings.autoDismissSeconds = autoDismissOptions[autoDismissPopup.indexOfSelectedItem].seconds
            }
            if maxLengthPopup.indexOfSelectedItem >= 0,
               maxLengthPopup.indexOfSelectedItem < maxLengthOptions.count {
                settings.maxContentLength = maxLengthOptions[maxLengthPopup.indexOfSelectedItem]
            }
            settings.ignoredBundleIDs = ignoredAppsField.stringValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            settings.launchAtLogin = launchAtLoginCheckbox.state == .on
            settings.checkForUpdates = checkUpdatesCheckbox.state == .on

            settings.ai.enabled = aiEnabledCheckbox.state == .on
            settings.ai.baseURL = aiBaseURLField.stringValue.trimmingCharacters(in: .whitespaces)
            settings.ai.model = aiModelField.stringValue.trimmingCharacters(in: .whitespaces)
            settings.ai.apiKey = aiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        }
        applyLaunchAtLogin()
        refreshAccessibilityStatus()
    }

    @objc private func requestAccessibility() {
        _ = SelectionWatcher.requestPermission()
        // 系统会弹框，同时把用户带到设置页；授权后回来点一下即可生效。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            SelectionWatcher.openAccessibilitySettings()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refreshAccessibilityStatus()
        }
    }

    @objc private func openAccessibilitySettings() {
        SelectionWatcher.openAccessibilitySettings()
    }

    private func applyLaunchAtLogin() {
        let shouldEnable = store.settings.launchAtLogin
        do {
            if shouldEnable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            testStatusLabel.textColor = .systemOrange
            testStatusLabel.stringValue = "登录项设置失败：\(error.localizedDescription)（把 App 放进 /Applications 再试）"
        }
    }

    @objc private func testConnection() {
        let config = store.settings.ai
        testStatusLabel.textColor = .secondaryLabelColor
        testStatusLabel.stringValue = "正在测试…"
        testButton.isEnabled = false
        let client = AIClient(config: config)
        Task { [self] in
            do {
                let reply = try await client.complete(system: "你是测试助手。", user: "只回复两个字：可用")
                await MainActor.run {
                    self.testStatusLabel.textColor = .systemGreen
                    self.testStatusLabel.stringValue = "连接成功：\(reply.prefix(60))"
                    self.testButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.testStatusLabel.textColor = .systemRed
                    self.testStatusLabel.stringValue = "失败：\(error.localizedDescription)"
                    self.testButton.isEnabled = true
                }
            }
        }
    }
}
