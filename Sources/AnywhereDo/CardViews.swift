import AppKit
import AnywhereDoCore

/// 不会抢走输入焦点的悬浮面板（Spotlight 那种 palettes 用的就是这套配置）。
final class PopupPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onNumberKey: ((Int) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        if let characters = event.charactersIgnoringModifiers,
           let value = Int(characters),
           value >= 1, value <= 9 {
            onNumberKey?(value)
            return
        }
        // 其它按键说明用户已经在打字了：收起面板，别把按键吞掉、也别响一声。
        onEscape?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

// MARK: - 卡片基础

class CardView: NSVisualEffectView {
    static let width: CGFloat = 380
    static let padding: CGFloat = 14
    static var contentWidth: CGFloat { width - padding * 2 }

    let stack = NSStackView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 120))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError(L10n.t("card.nibUnsupported")) }

    /// 让一行占满内容宽度。
    @discardableResult
    func addFullWidth(_ view: NSView) -> NSView {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        return view
    }

    func addSeparator() {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
    }

    func makeLabel(_ text: String, font: NSFont, color: NSColor, monospaced: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func accentColor(for kind: ContentKind) -> NSColor {
        switch kind.accentName {
        case "blue": return .systemBlue
        case "orange": return .systemOrange
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "teal": return .systemTeal
        case "green": return .systemGreen
        case "indigo": return .systemIndigo
        case "brown": return .systemBrown
        default: return .secondaryLabelColor
        }
    }

}

// MARK: - 建议卡片

final class SuggestionCardView: CardView {
    private var buttons: [NSButton] = []
    private var suggestions: [Suggestion] = []
    var onSelect: ((Suggestion) -> Void)?
    /// 紧凑模式里点「展开全部」。
    var onExpand: (() -> Void)?

    /// - Parameter compact: 划词触发时用的轻量样式：不显示预览、建议只留前 3 条。
    init(analysis: ClipboardAnalysis, sourceApp: String?, showPreview: Bool, compact: Bool = false) {
        super.init()
        buildHeader(analysis: analysis, sourceApp: sourceApp)
        if showPreview && !compact && !analysis.text.isEmpty {
            buildPreview(analysis: analysis)
        }
        if !analysis.facts.isEmpty {
            buildFacts(analysis.facts)
        }
        let visible = compact ? Array(analysis.suggestions.prefix(3)) : analysis.suggestions
        if !visible.isEmpty {
            addSeparator()
            buildSuggestions(visible)
        }
        if compact && analysis.suggestions.count > visible.count {
            buildExpandRow(hidden: analysis.suggestions.count - visible.count)
        }
        buildFooter(analysis: analysis)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildHeader(analysis: ClipboardAnalysis, sourceApp: String?) {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: analysis.kind.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        icon.contentTintColor = accentColor(for: analysis.kind)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let kindLabel = makeLabel(analysis.kind.displayName, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        let detail = analysis.headline + (sourceApp.map { L10n.t("card.sourceAppSuffix", $0) } ?? "")
        let detailLabel = makeLabel(detail, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        titleStack.addArrangedSubview(kindLabel)
        titleStack.addArrangedSubview(detailLabel)

        let header = NSStackView(views: [icon, titleStack, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        header.setHuggingPriority(.defaultLow, for: .horizontal)

        addFullWidth(header)
    }

    private func buildPreview(analysis: ClipboardAnalysis) {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        box.layer?.cornerRadius = 6
        box.translatesAutoresizingMaskIntoConstraints = false

        let monospaced = [.code, .json, .base64].contains(analysis.kind)
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            : NSFont.systemFont(ofSize: 11.5)
        let label = makeLabel(analysis.text, font: font, color: .labelColor)
        label.maximumNumberOfLines = 5
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -7),
        ])
        addFullWidth(box)
    }

    private func buildFacts(_ facts: [Fact]) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 3
        container.translatesAutoresizingMaskIntoConstraints = false

        for fact in facts {
            let label = makeLabel(fact.label, font: .systemFont(ofSize: 10.5), color: .tertiaryLabelColor)
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.widthAnchor.constraint(equalToConstant: 46).isActive = true

            let valueFont = fact.monospaced
                ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                : NSFont.systemFont(ofSize: 11)
            let value = makeLabel(fact.value, font: valueFont, color: .labelColor)
            value.isSelectable = true
            value.lineBreakMode = .byTruncatingMiddle

            let row = NSStackView(views: [label, value])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 6
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
            container.addArrangedSubview(row)
        }
        addFullWidth(container)
    }

    private func buildSuggestions(_ suggestions: [Suggestion]) {
        self.suggestions = suggestions
        for (index, suggestion) in suggestions.enumerated() {
            let button = makeSuggestionButton(suggestion, index: index)
            buttons.append(button)
            addFullWidth(button)
        }
    }

    private func makeSuggestionButton(_ suggestion: Suggestion, index: Int) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(suggestionTapped(_:)))
        button.tag = index
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        button.alignment = .left
        button.focusRingType = .none
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.contentTintColor = suggestion.isAI ? .controlAccentColor : accentColor(for: .plainText)
        button.image = NSImage(systemSymbolName: suggestion.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        button.toolTip = suggestion.subtitle
        button.translatesAutoresizingMaskIntoConstraints = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 1
        let title = NSMutableAttributedString(
            string: "\(index + 1). \(suggestion.title)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
            title.append(NSAttributedString(
                string: "\n" + subtitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10.5),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        button.attributedTitle = title
        button.cell?.wraps = true
        button.cell?.usesSingleLineMode = false
        button.heightAnchor.constraint(equalToConstant: (suggestion.subtitle?.isEmpty == false) ? 44 : 31).isActive = true
        return button
    }

    private func buildFooter(analysis: ClipboardAnalysis) {
        var hint = analysis.suggestions.isEmpty ? L10n.t("card.noSuggestions") : L10n.t("card.keyboardHint")
        if analysis.truncated {
            hint += L10n.t("card.truncatedSuffix", analysis.charCount)
        }
        let label = makeLabel(hint, font: .systemFont(ofSize: 10), color: .tertiaryLabelColor)
        addFullWidth(label)
    }

    private func buildExpandRow(hidden: Int) {
        let button = NSButton(
            title: L10n.t("card.expand", hidden),
            target: self,
            action: #selector(expandTapped)
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(button)
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    @objc private func expandTapped() {
        onExpand?()
    }

    @objc private func suggestionTapped(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < suggestions.count else { return }
        onSelect?(suggestions[sender.tag])
    }

    func trigger(index: Int) {
        guard index >= 0, index < buttons.count else { return }
        buttons[index].performClick(nil)
    }
}

// MARK: - 结果卡片

final class ResultCardView: CardView {
    var onCopy: ((String) -> Void)?
    var onBack: (() -> Void)?

    init(title: String, body: String, monospaced: Bool, isError: Bool = false) {
        super.init()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: isError ? "exclamationmark.triangle" : "checkmark.seal", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        icon.contentTintColor = isError ? .systemRed : .systemGreen
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        let header = NSStackView(views: [icon, titleLabel, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(header)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        scroll.layer?.cornerRadius = 6
        scroll.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            : NSFont.systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = body
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        addFullWidth(scroll)
        scroll.heightAnchor.constraint(equalToConstant: min(280, max(120, CGFloat(body.count) / 3 + 40))).isActive = true

        let copyButton = NSButton(title: L10n.t("card.copyResult"), target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        let backButton = NSButton(title: L10n.t("card.back"), target: self, action: #selector(backTapped))
        backButton.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let escHint = makeLabel(L10n.t("card.escHint"), font: .systemFont(ofSize: 10), color: .tertiaryLabelColor)
        let actions = NSStackView(views: [escHint, spacer, backButton, copyButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(actions)

        self.resultBody = body
    }

    required init?(coder: NSCoder) { fatalError() }

    private var resultBody: String = ""

    @objc private func copyTapped() {
        onCopy?(resultBody)
    }

    @objc private func backTapped() {
        onBack?()
    }
}

// MARK: - 轻提示卡片

final class ToastCardView: CardView {
    init(message: String, symbol: String = "checkmark.circle", tint: NSColor = .systemGreen) {
        super.init()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = makeLabel(message, font: .systemFont(ofSize: 12.5, weight: .medium), color: .labelColor)
        let row = NSStackView(views: [icon, label, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(row)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 加载卡片

final class LoadingCardView: CardView {
    private let spinner = NSProgressIndicator()

    init(title: String) {
        super.init()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = makeLabel(title, font: .systemFont(ofSize: 12.5, weight: .medium), color: .labelColor)
        let row = NSStackView(views: [spinner, label, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(row)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 悬停小图标

/// 划词后先出现的「小图标」：只有 26pt，鼠标悬停或点击才展开成完整卡片。
///
/// 继承 `CardView` 是为了复用同一套毛玻璃背景与弹窗管线（`PopupController` 只接受 `CardView`），
/// 因此它也能享受 Esc 关闭、点别处关闭这些既有行为。
final class HoverIconView: CardView {
    static let side: CGFloat = 26

    /// 悬停或点击时调用，由 AppDelegate 换成完整卡片。
    var onExpand: (() -> Void)?

    private let iconView = NSImageView()
    private var trackingArea: NSTrackingArea?

    init(symbol: String) {
        super.init()

        // 不要 CardView 那套纵向内容栈，换成居中的图标。
        stack.removeFromSuperview()
        // CardView 把宽度固定成 380pt，这里必须解掉，否则小图标会被撑成一条 380x26 的长条。
        for constraint in constraints
        where constraint.firstAttribute == .width && constraint.constant == Self.width {
            constraint.isActive = false
        }
        frame = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
        ])
        layer?.cornerRadius = Self.side / 2

        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = base.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            ) ?? base
        }
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = L10n.t("hover.tooltip")
    }

    required init?(coder: NSCoder) { fatalError(L10n.t("card.nibUnsupported")) }

    override var fittingSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// 面板（已显示）是否盖住了当前鼠标位置。
    /// 拖拽结束时鼠标常常就停在选区旁边，这种情况要直接展开，等不到 mouseEntered。
    var isCoveringMouse: Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    override func mouseEntered(with event: NSEvent) {
        onExpand?()
    }

    override func mouseDown(with event: NSEvent) {
        onExpand?()
    }
}
