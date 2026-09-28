import AppKit
import AnywhereDoCore
import ServiceManagement

/// 纯代码搭的设置窗口，避免依赖 xib/storyboard。
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore

    // 触发方式
    private let enabledCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.enable"), target: nil, action: nil)
    private let clipboardCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.watchClipboard"), target: nil, action: nil)
    private let selectionCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.watchSelection"), target: nil, action: nil)
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: L10n.t("settings.requestPermission"), target: nil, action: nil)
    private let accessibilitySettingsButton = NSButton(title: L10n.t("settings.openSystemSettings"), target: nil, action: nil)

    // 弹窗
    private let previewCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.showPreview"), target: nil, action: nil)
    private let selectionCompactCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.compactCard"), target: nil, action: nil)
    private let selectionFallbackCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.copyFallback"), target: nil, action: nil)
    private let keyboardCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.keyboard"), target: nil, action: nil)
    private let autoDismissPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let maxLengthPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    // 隐私与启动
    private let sensitiveCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.ignoreSensitive"), target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.launchAtLogin"), target: nil, action: nil)
    private let checkUpdatesCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.checkUpdates"), target: nil, action: nil)
    private let ignoredAppsField = NSTextField(string: "")

    // AI
    private let aiEnabledCheckbox = NSButton(checkboxWithTitle: L10n.t("settings.aiEnabled"), target: nil, action: nil)
    private let aiBaseURLField = NSTextField(string: "")
    private let aiModelField = NSTextField(string: "")
    private let aiKeyField = NSSecureTextField(string: "")
    private let testButton = NSButton(title: L10n.t("settings.testConnection"), target: nil, action: nil)
    private let testStatusLabel = NSTextField(labelWithString: "")

    private let autoDismissOptions: [(title: String, seconds: Double)] = [
        (L10n.t("settings.autoDismiss.never"), 0),
        (L10n.t("settings.autoDismiss.seconds", 3), 3),
        (L10n.t("settings.autoDismiss.seconds", 5), 5),
        (L10n.t("settings.autoDismiss.seconds", 8), 8),
        (L10n.t("settings.autoDismiss.seconds", 15), 15),
        (L10n.t("settings.autoDismiss.seconds", 30), 30),
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
        window.title = L10n.t("settings.title")
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
        stack.addArrangedSubview(sectionTitle(L10n.t("settings.section.triggers")))
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
        stack.addArrangedSubview(sectionTitle(L10n.t("settings.section.popup")))

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
            maxLengthPopup.addItem(withTitle: L10n.t("common.charCount", length))
        }
        maxLengthPopup.target = self
        maxLengthPopup.action = #selector(generalChanged)
        stack.addArrangedSubview(grid(rows: [
            (L10n.t("settings.autoDismissLabel"), autoDismissPopup),
            (L10n.t("settings.maxLengthLabel"), maxLengthPopup),
        ]))

        stack.addArrangedSubview(separatorBox())
        stack.addArrangedSubview(sectionTitle(L10n.t("settings.section.privacy")))

        wire(sensitiveCheckbox)
        stack.addArrangedSubview(sensitiveCheckbox)
        ignoredAppsField.placeholderString = "com.example.app, com.other.app"
        ignoredAppsField.target = self
        ignoredAppsField.action = #selector(generalChanged)
        stack.addArrangedSubview(grid(rows: [
            (L10n.t("settings.ignoredAppsLabel"), ignoredAppsField),
        ]))
        wire(launchAtLoginCheckbox)
        stack.addArrangedSubview(launchAtLoginCheckbox)
        wire(checkUpdatesCheckbox)
        stack.addArrangedSubview(checkUpdatesCheckbox)

        stack.addArrangedSubview(separatorBox())
        stack.addArrangedSubview(sectionTitle(L10n.t("settings.section.ai")))

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
            (L10n.t("settings.modelLabel"), aiModelField),
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
            L10n.t("settings.footer", SettingsStore.fileURL.path) + "\n"
            + L10n.t("settings.clipboardHint"))
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
            accessibilityStatusLabel.stringValue = L10n.t("selfcheck.granted")
            accessibilityButton.isEnabled = false
        } else {
            accessibilityStatusLabel.textColor = .systemOrange
            accessibilityStatusLabel.stringValue = L10n.t("settings.accessibilityMissing")
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
            testStatusLabel.stringValue = L10n.t("settings.loginItemFailed", error.localizedDescription)
        }
    }

    @objc private func testConnection() {
        let config = store.settings.ai
        testStatusLabel.textColor = .secondaryLabelColor
        testStatusLabel.stringValue = L10n.t("settings.testing")
        testButton.isEnabled = false
        let client = AIClient(config: config)
        Task { [self] in
            do {
                let reply = try await client.complete(system: L10n.t("settings.testSystem"), user: L10n.t("settings.testUser"))
                await MainActor.run {
                    self.testStatusLabel.textColor = .systemGreen
                    self.testStatusLabel.stringValue = L10n.t("settings.testSuccess", String(reply.prefix(60)))
                    self.testButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.testStatusLabel.textColor = .systemRed
                    self.testStatusLabel.stringValue = L10n.t("settings.testFailed", error.localizedDescription)
                    self.testButton.isEnabled = true
                }
            }
        }
    }
}
