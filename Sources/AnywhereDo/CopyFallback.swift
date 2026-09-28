import AppKit
import Carbon

/// 给「读不到选区」的 App（Chrome / Electron / 自绘文本）兜底：
/// 合成一次 ⌘C，读出剪贴板，然后**把用户原来的剪贴板原样写回去**。
///
/// 需要辅助功能权限（合成键盘事件）；只在选区读不到时才会用到。
enum CopyFallback {
    struct Result {
        let text: String
        /// 原剪贴板是否已还原。
        let restored: Bool
    }

    /// 系统「安全键盘输入」打开时（部分密码输入场景），合成按键会被系统丢弃，直接跳过。
    static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    /// 合成 ⌘C 并读取结果。没有复制到东西时返回 nil（此时剪贴板未被动过）。
    static func copySelection(timeout: TimeInterval = 0.5) -> Result? {
        let pasteboard = NSPasteboard.general
        let existingItems = pasteboard.pasteboardItems ?? []
        let snapshot = PasteboardSnapshot.capture(pasteboard)

        // 有内容却快照不下来（太大/异常）时绝不合成 ⌘C——
        // 否则会把用户的剪贴板永久换成选区内容，那是不可接受的破坏。
        if snapshot == nil && !existingItems.isEmpty {
            Diagnostics.log("⌘C 兜底：放弃（剪贴板内容过大或无法快照，不冒险改动）")
            return nil
        }

        let before = pasteboard.changeCount

        postCommandC()

        guard waitForChangeCount(pasteboard, from: before, timeout: timeout) else {
            return nil
        }
        // 再多给一点时间，确保内容写入完整。
        usleep(30_000)

        let text = pasteboard.string(forType: .string) ?? ""

        var restored = false
        if let snapshot {
            snapshot.restore(to: pasteboard)
            restored = true
        }

        guard !text.isEmpty else { return nil }
        return Result(text: text, restored: restored)
    }

    // MARK: - 合成按键

    static func postCommandC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCodeC: CGKeyCode = 8 // 'c'
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(15_000)
        up.post(tap: .cghidEventTap)
    }

    private static func waitForChangeCount(_ pasteboard: NSPasteboard, from: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != from { return true }
            usleep(10_000)
        }
        return false
    }
}

/// 剪贴板的完整快照：把每个 item 的每种类型都抄成 Data，之后再原样写回。
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    private let sizeLimit = 12 * 1024 * 1024

    static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        guard let objects = pasteboard.pasteboardItems, !objects.isEmpty else { return nil }
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        var total = 0
        for item in objects {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // 有些类型（例如 Finder 复制的 public.file-url）没有 Data 形态，
                // 只有字符串形态，退回 string(forType:) 取，否则还原时会丢掉这类内容。
                let data: Data?
                if let raw = item.data(forType: type) {
                    data = raw
                } else if let text = item.string(forType: type) {
                    data = Data(text.utf8)
                } else {
                    data = nil
                }
                guard let data, !data.isEmpty else { continue }
                total += data.count
                // 太大了就不掺和，免得为了兜底把系统的内存吃掉。
                if total > 12 * 1024 * 1024 { return nil }
                values[type] = data
            }
            guard !values.isEmpty else { continue }
            captured.append(values)
        }
        guard !captured.isEmpty else { return nil }
        return PasteboardSnapshot(items: captured)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let objects = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(objects)
    }
}
