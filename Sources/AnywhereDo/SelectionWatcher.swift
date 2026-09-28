import AppKit
import ApplicationServices

struct SelectionEvent {
    let text: String
    /// 选区的屏幕坐标（Cocoa 全局坐标，原点在左下），拿不到时为 nil。
    let bounds: NSRect?
    /// 拿不到选区坐标时的兜底锚点（一般是拖选结束时的鼠标位置）。
    let anchorPoint: NSPoint?
    let sourceAppName: String?
    let sourceBundleID: String?
    let isSensitive: Bool
    /// 是否由「合成 ⌘C」兜底得到。
    let viaCopyFallback: Bool
    /// 文本里没有换行符时，用选区几何估算的行数。
    let estimatedLineCount: Int?
}

/// 「划词即弹」的核心：轮询当前焦点元素里选中的文字。
///
/// macOS 没有公开的全局「选区变化」通知，只能轮询；而选区文本与坐标必须走
/// Accessibility API（`AXUIElement`），因此需要用户授予「辅助功能」权限。
/// 所有 AX 调用都设置了很短的超时，避免目标 App 卡住时把我们也拖死。
final class SelectionWatcher {
    private var timer: Timer?
    private var lastSignature = ""
    private var pendingSignature = ""
    private var pendingSince = Date.distantPast
    private let interval: TimeInterval
    private let maxLength: Int

    // 兜底用的鼠标监听
    private var mouseMonitor: Any?
    /// 键盘监听：用于判断「这次选区变化是不是键盘/输入法弄出来的」。
    private var keyMonitor: Any?
    /// 最近一次「鼠标划词动作」（拖选 / 双击选词 / 三击选行）的时间。
    /// 输入法的组合串（预编辑文本）在文本框里也是选中状态，
    /// 一旦不看这个时间戳，打字就会被当成划词。
    private var lastMouseGesture: Date = .distantPast
    private var lastGateLog: Date = .distantPast
    private var mouseDownPoint: NSPoint?
    private var maxDragDistance: CGFloat = 0
    private var fallbackWorkItem: DispatchWorkItem?

    /// 读不到选区的 App（Chrome / Electron）用「合成 ⌘C + 还原剪贴板」兜底。
    var isCopyFallbackEnabled = false
    /// 由 App 层判断当前是否允许兜底（设置 + 黑名单）。
    var shouldUseCopyFallback: (() -> Bool)?
    /// 合成 ⌘C 前后通知 App 层：期间要把剪贴板监听当作「自己人干的」。
    var willSynthesizeCopy: (() -> Void)?
    var didSynthesizeCopy: (() -> Void)?
    /// 用户开始打字（键盘事件）：弹窗应该让开。
    var onTyping: (() -> Void)?

    var onEvent: ((SelectionEvent) -> Void)?
    var isPaused = false
    /// 我们自己的 UI（弹窗 / 设置窗口）拿着焦点时返回 true。
    /// 这种情况下「读不到选区」不代表选区被清空，必须保留状态，否则会反复弹。
    var isSuppressed: (() -> Bool)?

    init(interval: TimeInterval = 0.35, maxLength: Int = 4000) {
        self.interval = interval
        self.maxLength = maxLength
    }

    var isRunning: Bool { timer != nil }

    func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = interval / 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // 鼠标监听是「鼠标划词判定」的基础，和 ⌘C 兜底无关：兜底关掉也必须装。
        installMouseMonitor()
        installKeyMonitor()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fallbackWorkItem?.cancel()
        fallbackWorkItem = nil
        removeMouseMonitor()
        removeKeyMonitor()
    }

    /// 只切换「⌘C 兜底」这个功能本身；鼠标监听不归它管。
    func setCopyFallbackEnabled(_ enabled: Bool) {
        isCopyFallbackEnabled = enabled
    }

    func reset() {
        lastSignature = ""
        pendingSignature = ""
    }

    // MARK: - 权限

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统授权对话框；用户仍需在「系统设置 → 隐私与安全性 → 辅助功能」里打开开关。
    @discardableResult
    static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
    }

    // MARK: - 轮询

    private func poll() {
        guard !isPaused else { return }
        guard isSuppressed?() != true else { return }
        // 正在拖拽选择时不要打断。
        guard NSEvent.pressedMouseButtons == 0 else { return }
        guard Self.isTrusted else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        switch Accessibility.readSelection(app: frontmost) {
        case .unavailable:
            // 读不到（焦点在非文本元素、App 不支持、或焦点在我们自己身上）：保留状态。
            return

        case .empty:
            // 选区真的被清空了，允许之后重新选中同一段文字再次弹出。
            lastSignature = ""
            pendingSignature = ""
            return

        case .selected(let text, let range, let bounds, let estimatedLines):
            guard !text.isEmpty, text.count <= maxLength else { return }
            guard isFromMouseGesture else {
                if Date().timeIntervalSince(lastGateLog) > 3 {
                    lastGateLog = Date()
                    let gap = Date().timeIntervalSince(lastMouseGesture)
                    Diagnostics.log("划词：忽略（不是鼠标划出来的：键盘选择或输入法组合串）距上次鼠标手势=\(gap > 3600 ? "从未" : String(format: "%.1fs", gap))")
                }
                return
            }
            let signature = [
                frontmost.bundleIdentifier ?? "?",
                String(range.location),
                String(range.length),
                String(text.count),
                String(text.hashValue),
            ].joined(separator: "|")
            guard signature != lastSignature else { return }
            // 连续两次轮询签名一致，才认为是「稳定选区」，避免拖选途中乱弹。
            guard signature == pendingSignature else {
                pendingSignature = signature
                pendingSince = Date()
                return
            }
            guard Date().timeIntervalSince(pendingSince) >= 0.15 else { return }

            lastSignature = signature
            Diagnostics.log("划词：" + (frontmost.localizedName ?? "?")
                + " 长度=\(text.count)"
                + " 换行符=\(max(0, text.components(separatedBy: .newlines).count - 1))"
                + " 估算行数=\(estimatedLines.map(String.init) ?? "-")"
                + " 选区坐标=\(bounds == nil ? "无" : "有")")
            onEvent?(SelectionEvent(
                text: text,
                bounds: bounds,
                anchorPoint: nil,
                sourceAppName: frontmost.localizedName,
                sourceBundleID: frontmost.bundleIdentifier,
                isSensitive: false,
                viaCopyFallback: false,
                estimatedLineCount: estimatedLines
            ))
        }
    }
}

// MARK: - 合成 ⌘C 兜底

extension SelectionWatcher {
    /// 鼠标划词的判定窗口：够覆盖「松手 → 轮询两次确认选区」的延迟。
    fileprivate var isFromMouseGesture: Bool {
        Date().timeIntervalSince(lastMouseGesture) < 2.5
    }

    fileprivate func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        // 需要辅助功能权限（划词本来就要），没有权限时这个监听不会收到事件。
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            guard let self else { return }
            // 一开始打字就撤销鼠标划词的「资格」，并让弹窗让开。
            self.lastMouseGesture = .distantPast
            self.onTyping?()
        }
    }

    fileprivate func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    fileprivate func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        Diagnostics.log("划词：鼠标监听" + (mouseMonitor == nil ? "安装失败" : "已安装"))
    }

    fileprivate func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        mouseDownPoint = nil
        maxDragDistance = 0
    }

    /// 拖选 / 双击选词 / 三击选行结束后，才值得去试一次 ⌘C。
    fileprivate func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownPoint = NSEvent.mouseLocation
            maxDragDistance = 0

        case .leftMouseDragged:
            guard let start = mouseDownPoint else { return }
            let current = NSEvent.mouseLocation
            maxDragDistance = max(maxDragDistance, hypot(current.x - start.x, current.y - start.y))

        case .leftMouseUp:
            let wasDrag = maxDragDistance >= 4
            let wasMultiClick = event.clickCount >= 2
            let pressPoint = mouseDownPoint ?? NSEvent.mouseLocation
            let endPoint = NSEvent.mouseLocation
            mouseDownPoint = nil
            maxDragDistance = 0
            guard wasDrag || wasMultiClick else { return }
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            // 拖窗口标题栏 / 滚动条 / 拉窗口边缘不算划词，不开启门控。
            guard !isInWindowChrome(pressPoint: pressPoint, app: frontmost) else { return }
            // 记下这是一次鼠标划词动作：之后 2.5 秒内的选区变化才算「划词」。
            lastMouseGesture = Date()
            scheduleCopyProbe(pressPoint: pressPoint, endPoint: endPoint, app: frontmost)

        default:
            break
        }
    }

    /// 控件的角色：起点落在这些元素上，一定不是在划词。
    static let controlRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXSlider",
        "AXScrollBar", "AXToolbar", "AXMenuBar", "AXMenuItem", "AXDisclosureTriangle",
        "AXProgressIndicator", "AXImage", "AXTabGroup", "AXColorWell", "AXSegmentedControl",
    ]

    /// 只有「看起来真的是鼠标划词」的拖拽才会往下走；
    /// 拖窗口、滚滚动条、拉滑块、拖文件这些一律不碰剪贴板。
    /// 按下点是否落在窗口「非内容区」（标题栏 / 滚动条 / 底部边缘）。
    fileprivate func isInWindowChrome(pressPoint: NSPoint, app: NSRunningApplication) -> Bool {
        guard let frame = Accessibility.focusedWindowFrame(app: app) else { return false }
        let quartz = ScreenCoordinates.quartzPoint(fromCocoa: pressPoint)
        if quartz.y < frame.minY + 36 { return true }
        if quartz.y > frame.maxY - 20 { return true }
        if quartz.x > frame.maxX - 22 { return true }
        return false
    }

    fileprivate func scheduleCopyProbe(pressPoint: NSPoint, endPoint: NSPoint, app frontmost: NSRunningApplication) {
        guard isCopyFallbackEnabled, isRunning, !isPaused else { return }
        guard isSuppressed?() != true else { return }
        guard Self.isTrusted else { return }
        guard shouldUseCopyFallback?() ?? false else { return }

        let dx = endPoint.x - pressPoint.x
        let dy = endPoint.y - pressPoint.y
        // 近乎竖直的拖拽更像滚动条/滑块，而不是选文字。
        if abs(dx) < 4 && abs(dy) > 24 {
            Diagnostics.log("⌘C 兜底：跳过（竖向拖拽，更像滚动条）")
            return
        }
        if frontmost.bundleIdentifier == "com.apple.finder" {
            Diagnostics.log("⌘C 兜底：跳过（访达，拖拽多为文件操作）")
            return
        }

        let quartz = ScreenCoordinates.quartzPoint(fromCocoa: pressPoint)
        if let role = Accessibility.roleAtPosition(quartz), Self.controlRoles.contains(role) {
            Diagnostics.log("⌘C 兜底：跳过（起点是控件 \(role)）")
            return
        }

        fallbackWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runCopyProbe(at: endPoint)
        }
        fallbackWorkItem = work
        // 等选区稳定下来再动手。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    fileprivate func runCopyProbe(at point: NSPoint) {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let appName = frontmost.localizedName ?? "?"

        // 能读到选区的 App（原生 App）走正常链路，别多此一举。
        if let text = Accessibility.currentSelectionText(app: frontmost), !text.isEmpty {
            return
        }
        guard !Accessibility.focusedElementIsSecure(app: frontmost) else {
            Diagnostics.log("⌘C 兜底：跳过（\(appName) 焦点在安全输入框）")
            return
        }
        guard !CopyFallback.isSecureInputEnabled else {
            Diagnostics.log("⌘C 兜底：跳过（系统安全输入已开启）")
            return
        }

        willSynthesizeCopy?()
        let bundleID = frontmost.bundleIdentifier
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = CopyFallback.copySelection()
            DispatchQueue.main.async {
                self.didSynthesizeCopy?()
                guard let result else {
                    Diagnostics.log("⌘C 兜底：\(appName) 没有复制到内容（剪贴板未改动）")
                    return
                }
                Diagnostics.log("⌘C 兜底：\(appName) 取到 长度=\(result.text.count) 已还原=\(result.restored ? "是" : "否")")
                let signature = "fallback|\(bundleID ?? "?")|\(result.text.count)|\(result.text.hashValue)"
                self.lastSignature = signature
                self.pendingSignature = signature
                self.onEvent?(SelectionEvent(
                    text: result.text,
                    bounds: nil,
                    anchorPoint: point,
                    sourceAppName: appName,
                    sourceBundleID: bundleID,
                    isSensitive: false,
                    viaCopyFallback: true,
                    estimatedLineCount: nil
                ))
            }
        }
    }
}

// MARK: - AX 读取

enum Accessibility {
    enum SelectionOutcome {
        /// 读不到：焦点不在文本元素上、目标 App 不支持、或读到的是安全输入框。
        case unavailable
        /// 元素支持选区，但当前没有选中任何内容。
        case empty
        case selected(text: String, range: CFRange, bounds: NSRect?, estimatedLines: Int?)
    }

    static func readSelection(app: NSRunningApplication? = nil) -> SelectionOutcome {
        guard let element = focusedElement(app: app) else { return .unavailable }

        // 密码框一概不读。
        if let subrole = stringAttribute(element, kAXSubroleAttribute), subrole == "AXSecureTextField" {
            return .unavailable
        }

        switch stringAttributeResult(element, kAXSelectedTextAttribute) {
        case .unsupported:
            return .unavailable
        case .value(let text):
            guard !text.isEmpty else { return .empty }
            let range = rangeAttribute(element, kAXSelectedTextRangeAttribute) ?? CFRange(location: 0, length: 0)
            let bounds = boundsForRange(element, range)
            // 浏览器把逐行渲染的代码块拍平后，选区文本里是没有换行符的，
            // 这时靠「选区高度 ÷ 单行高度」把行数估出来，别谎报 1 行。
            let estimatedLines = (bounds == nil || text.contains("\n"))
                ? nil
                : estimatedLineCount(element: element, range: range, selectionBounds: bounds!)
            return .selected(text: text, range: range, bounds: bounds, estimatedLines: estimatedLines)
        }
    }

    /// 当前焦点元素的选区文本（给 `--selection` 自检用）。
    /// 焦点窗口的矩形（Quartz 坐标）。
    static func focusedWindowFrame(app: NSRunningApplication) -> CGRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let window = elementAttribute(appElement, kAXFocusedWindowAttribute),
              let origin = pointAttribute(window, kAXPositionAttribute),
              let size = sizeAttribute(window, kAXSizeAttribute) else { return nil }
        guard size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// 屏幕某个位置上的元素角色。用来判断「这次拖拽的起点是不是文字」。
    /// 失败时返回 nil（调用方按「未知」处理，不阻断）。
    static func roleAtPosition(_ quartzPoint: CGPoint) -> String? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(quartzPoint.x),
            Float(quartzPoint.y),
            &element
        )
        guard error == .success, let element else { return nil }
        return stringAttribute(element, kAXRoleAttribute)
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }

    /// 焦点是否在安全输入框（密码框）上：这种一律不碰。
    static func focusedElementIsSecure(app: NSRunningApplication? = nil) -> Bool {
        guard let element = focusedElement(app: app) else { return false }
        return stringAttribute(element, kAXSubroleAttribute) == "AXSecureTextField"
    }

    static func currentSelectionText(app: NSRunningApplication? = nil) -> String? {
        guard let element = focusedElement(app: app) else { return nil }
        if case .value(let text) = stringAttributeResult(element, kAXSelectedTextAttribute) {
            return text
        }
        return nil
    }

    /// 注意：不要用 AXUIElementCreateSystemWide + kAXFocusedApplicationAttribute——
    /// 在本机 macOS 上它返回 kAXErrorCannotComplete(-25204)。
    /// 用「当前最前台 App 的 PID」建元素既稳定，也不会读到我们自己的弹窗。
    static func focusedElement(app: NSRunningApplication? = nil) -> AXUIElement? {
        guard let target = app ?? NSWorkspace.shared.frontmostApplication else { return nil }
        guard target.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        // 目标 App 无响应时不要让 AX 调用阻塞我们太久。
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        return elementAttribute(appElement, kAXFocusedUIElementAttribute)
    }

    // MARK: 底层调用

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private enum StringResult {
        case unsupported
        case value(String)
    }

    private static func stringAttributeResult(_ element: AXUIElement, _ attribute: String) -> StringResult {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == CFStringGetTypeID() else {
            return .unsupported
        }
        return .value(value as? String ?? "")
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        if case .value(let text) = stringAttributeResult(element, attribute) { return text }
        return nil
    }

    private static func rangeAttribute(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    /// 用几何比例估算行数：整段选区的高度 ÷ 单个字符的高度。
    private static func estimatedLineCount(element: AXUIElement, range: CFRange, selectionBounds: NSRect) -> Int? {
        guard range.length > 1, selectionBounds.height > 0.5 else { return nil }
        guard let single = boundsForRange(element, CFRange(location: range.location, length: 1)),
              single.height > 0.5 else { return nil }
        let ratio = selectionBounds.height / single.height
        guard ratio.isFinite, ratio >= 1.2, ratio <= 500 else { return nil }
        return max(1, Int(ratio.rounded()))
    }

    private static func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> NSRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard error == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect), rect.width.isFinite, rect.height.isFinite else { return nil }
        guard rect.width > 0 || rect.height > 0 else { return nil }
        return ScreenCoordinates.cocoaRect(fromQuartz: rect)
    }
}

// MARK: - 坐标换算

enum ScreenCoordinates {
    /// Accessibility / Quartz 用的是「主屏左上角为原点、y 向下」的坐标，
    /// AppKit 用的是「主屏左下角为原点、y 向上」，需要翻转一次。
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    static func quartzPoint(fromCocoa point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func cocoaRect(fromQuartz rect: CGRect) -> NSRect {
        NSRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: max(rect.width, 1),
            height: max(rect.height, 1)
        )
    }
}
