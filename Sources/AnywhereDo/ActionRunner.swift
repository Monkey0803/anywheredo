import AppKit
import AnywhereDoCore

enum ActionOutcome {
    /// 执行完成，用一个短提示收起面板。
    case done(String)
    /// 需要把结果显示在面板里。
    case showResult(title: String, body: String, monospaced: Bool)
    /// 执行失败。
    case failure(String)
    /// 交给 AI 异步处理。
    case aiPending(AIPreset, String)
}

final class ActionRunner {
    /// 我们自己写了剪贴板，通知监听器忽略这一次变化。
    var onPasteboardWrite: (() -> Void)?

    func perform(_ action: SuggestionAction) -> ActionOutcome {
        switch action {
        case .openURL(let url):
            return open(url, success: "已用默认浏览器打开")

        case .revealInFinder(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return .done("已在 Finder 中显示")

        case .openFile(let path):
            return open(URL(fileURLWithPath: path), success: "已打开文件")

        case .copyText(let text), .setClipboard(let text):
            writeToPasteboard(text)
            return .done("已复制到剪贴板")

        case .transform(let transform, let source):
            switch TextTransform.apply(transform, to: source) {
            case .success(let output):
                return .showResult(
                    title: transform.resultTitle,
                    body: output,
                    monospaced: transform == .jsonPretty || transform == .jsonMinify || transform == .base64Decode || transform == .base64Encode
                )
            case .failure(let error):
                return .failure(error.errorDescription ?? "变换失败")
            }

        case .searchWeb(let query):
            guard let url = Analyzer.webSearchURL(for: query) else {
                return .failure("无法构造搜索链接")
            }
            return open(url, success: "已打开搜索结果")

        case .composeEmail(let address):
            guard let url = URL(string: "mailto:\(address)") else {
                return .failure("邮箱地址不合法")
            }
            return open(url, success: "已打开邮件客户端")

        case .callNumber(let digits):
            if let url = URL(string: "tel://\(digits)"), NSWorkspace.shared.open(url) {
                return .done("正在拨打")
            }
            if let url = URL(string: "facetime://\(digits)"), NSWorkspace.shared.open(url) {
                return .done("正在拨打")
            }
            return .failure("无法发起呼叫")

        case .sendMessage(let digits):
            if let url = URL(string: "sms://\(digits)"), NSWorkspace.shared.open(url) {
                return .done("已打开信息 App")
            }
            if let url = URL(string: "imessage://\(digits)"), NSWorkspace.shared.open(url) {
                return .done("已打开信息 App")
            }
            return .failure("无法打开信息 App")

        case .ai(let preset, let source):
            return .aiPending(preset, source)
        }
    }

    /// 复制内容到剪贴板。所有写操作都走这里，确保监听器不会自触发。
    @discardableResult
    func writeToPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        onPasteboardWrite?()
        return ok
    }

    private func open(_ url: URL, success: String) -> ActionOutcome {
        if NSWorkspace.shared.open(url) {
            return .done(success)
        }
        return .failure("系统无法打开 \(url.absoluteString)")
    }
}
