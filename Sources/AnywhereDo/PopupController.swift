import AppKit
import AnywhereDoCore

/// 弹窗贴哪儿：鼠标位置，还是文本选区。
enum PopupAnchor {
    case point(NSPoint)
    /// Cocoa 全局坐标下的选区矩形。
    case selection(NSRect)

    var isSelection: Bool {
        if case .selection = self { return true }
        return false
    }

    /// 用来判断落在哪块屏幕上。
    var probePoint: NSPoint {
        switch self {
        case .point(let point): return point
        case .selection(let rect): return NSPoint(x: rect.midX, y: rect.midY)
        }
    }
}

/// 负责把卡片放到指定位置旁边，并处理关闭时机。
final class PopupController {
    private var panel: PopupPanel?
    private var dismissTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastAnchor: PopupAnchor = .point(.zero)

    var keyboardShortcuts: Bool = true
    var offset: CGFloat = 14
    /// 当卡片是「建议卡片」时，数字键要转发给它。
    var activeSuggestionCard: SuggestionCardView?

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - 展示

    func showCard(_ card: CardView, at point: NSPoint, dismissAfter: TimeInterval?) {
        showCard(card, anchor: .point(point), dismissAfter: dismissAfter)
    }

    func showCard(_ card: CardView, anchor: PopupAnchor, dismissAfter: TimeInterval?) {
        close()
        lastAnchor = anchor

        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize
        card.frame = NSRect(origin: .zero, size: size)

        let panel = PopupPanel(size: size)
        panel.contentView = card
        panel.onEscape = { [weak self] in self?.close() }
        panel.onNumberKey = { [weak self] number in
            self?.activeSuggestionCard?.trigger(index: number - 1)
        }
        self.panel = panel
        self.activeSuggestionCard = card as? SuggestionCardView

        position(panel: panel, anchor: anchor)
        Diagnostics.log("弹窗：锚点=\(describe(anchor)) 尺寸=\(Int(size.width))x\(Int(size.height)) 位置=\(Int(panel.frame.origin.x)),\(Int(panel.frame.origin.y)) 屏幕=\(NSScreen.screens.count)块")

        if keyboardShortcuts {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        } else {
            panel.orderFrontRegardless()
        }

        installMonitors()
        if let dismissAfter, dismissAfter > 0 {
            let timer = Timer(timeInterval: dismissAfter, repeats: false) { [weak self] _ in
                self?.close()
            }
            RunLoop.main.add(timer, forMode: .common)
            dismissTimer = timer
        }
    }

    func close() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        removeMonitors()
        activeSuggestionCard = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// 卡片内容变化后重新摆一次（例如展开全部建议）。
    func relayout(at anchor: PopupAnchor? = nil) {
        let target = anchor ?? lastAnchor
        guard let panel, let card = panel.contentView as? CardView else { return }
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize
        card.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        position(panel: panel, anchor: target)
    }

    private func describe(_ anchor: PopupAnchor) -> String {
        switch anchor {
        case .point(let point): return "鼠标(\(Int(point.x)),\(Int(point.y)))"
        case .selection(let rect): return "选区(\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width))x\(Int(rect.height)))"
        }
    }

    // MARK: - 位置

    private func position(panel: NSPanel, anchor: PopupAnchor) {
        let size = panel.frame.size
        let probe = anchor.probePoint
        let screen = NSScreen.screens.first { NSMouseInRect(probe, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin: NSPoint
        switch anchor {
        case .point(let point):
            // 默认放在鼠标右下方，贴边时自动翻转。
            origin = NSPoint(x: point.x + offset, y: point.y - size.height - offset)
            if origin.x + size.width > visible.maxX - 8 {
                origin.x = point.x - size.width - offset
            }
            if origin.y < visible.minY + 8 {
                origin.y = point.y + offset
            }

        case .selection(let rect):
            // 划词：优先贴在选区正下方、左边缘对齐；下方放不下就翻到上方。
            let gap: CGFloat = 8
            origin = NSPoint(x: rect.minX, y: rect.minY - size.height - gap)
            if origin.y < visible.minY + 8 {
                origin.y = rect.maxY + gap
            }
            if origin.x + size.width > visible.maxX - 8 {
                origin.x = rect.maxX - size.width
            }
        }

        origin.x = min(max(origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        origin.y = min(max(origin.y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8))
        panel.setFrameOrigin(origin)
    }

    // MARK: - 关闭时机

    private func installMonitors() {
        removeMonitors()
        // 全局鼠标监听：点到别处就收起。不需要辅助功能权限（键盘事件才需要）。
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.close() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            // 点在面板内部由按钮自己处理，点在面板外则收起。
            let location = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            if !panel.frame.contains(location) {
                self.close()
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }
}
