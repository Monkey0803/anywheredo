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
            return open(url, success: L10n.t("action.openedInBrowser"))

        case .revealInFinder(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return .done(L10n.t("action.revealedInFinder"))

        case .openFile(let path):
            return open(URL(fileURLWithPath: path), success: L10n.t("action.openedFile"))

        case .copyText(let text), .setClipboard(let text):
            writeToPasteboard(text)
            return .done(L10n.t("action.copied"))

        case .transform(let transform, let source):
            switch TextTransform.apply(transform, to: source) {
            case .success(let output):
                return .showResult(
                    title: transform.resultTitle,
                    body: output,
                    monospaced: transform == .jsonPretty || transform == .jsonMinify || transform == .base64Decode || transform == .base64Encode
                )
            case .failure(let error):
                return .failure(error.errorDescription ?? L10n.t("action.transformFailed"))
            }

        case .searchWeb(let query):
            guard let url = Analyzer.webSearchURL(for: query) else {
                return .failure(L10n.t("action.searchURLFailed"))
            }
            return open(url, success: L10n.t("action.openedSearch"))

        case .composeEmail(let address):
            guard let url = URL(string: "mailto:\(address)") else {
                return .failure(L10n.t("action.invalidEmail"))
            }
            return open(url, success: L10n.t("action.openedMail"))

        case .callNumber(let digits):
            if let url = URL(string: "tel://\(digits)"), NSWorkspace.shared.open(url) {
                return .done(L10n.t("action.calling"))
            }
            if let url = URL(string: "facetime://\(digits)"), NSWorkspace.shared.open(url) {
                return .done(L10n.t("action.calling"))
            }
            return .failure(L10n.t("action.callFailed"))

        case .sendMessage(let digits):
            if let url = URL(string: "sms://\(digits)"), NSWorkspace.shared.open(url) {
                return .done(L10n.t("action.openedMessages"))
            }
            if let url = URL(string: "imessage://\(digits)"), NSWorkspace.shared.open(url) {
                return .done(L10n.t("action.openedMessages"))
            }
            return .failure(L10n.t("action.messageFailed"))

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
        return .failure(L10n.t("action.openFailed", url.absoluteString))
    }
}
