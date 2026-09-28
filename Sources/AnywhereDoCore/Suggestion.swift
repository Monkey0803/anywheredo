import Foundation

/// 建议被点击后要执行的动作。Core 只描述意图，App 负责真正执行。
public enum SuggestionAction: Equatable, Sendable {
    /// 用默认浏览器打开。
    case openURL(URL)
    /// 在 Finder 中显示。
    case revealInFinder(String)
    /// 用默认应用打开本地文件。
    case openFile(String)
    /// 复制一段新文本到剪贴板。
    case copyText(String)
    /// 把原文写回剪贴板（例如“复制为纯文本”）。
    case setClipboard(String)
    /// 对原文做一次可预览的变换。
    case transform(TextTransform, source: String)
    /// 打开搜索引擎。
    case searchWeb(String)
    /// 打开邮件客户端写新邮件。
    case composeEmail(String)
    /// 用 FaceTime / 电话应用拨打。
    case callNumber(String)
    /// 打开信息 App 发短信。
    case sendMessage(String)
    /// 交给 AI 处理。
    case ai(AIPreset, source: String)
}

/// 用户可见的一条建议。
public struct Suggestion: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbol: String
    public let action: SuggestionAction

    public init(id: String, title: String, subtitle: String? = nil, symbol: String, action: SuggestionAction) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.action = action
    }

    public var isAI: Bool {
        if case .ai = action { return true }
        return false
    }
}

/// 面板里展示的一条“事实”——帮助用户不点任何按钮就获取信息。
public struct Fact: Equatable, Sendable {
    public let label: String
    public let value: String
    public let monospaced: Bool

    public init(label: String, value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }
}

/// 一次分析的全部产出。
public struct ClipboardAnalysis: Equatable, Sendable {
    public let kind: ContentKind
    public let text: String
    public let headline: String
    public let facts: [Fact]
    public let suggestions: [Suggestion]
    public let charCount: Int
    public let lineCount: Int
    /// 文本本身没有换行符时（浏览器会把逐行渲染的代码块拍平），
    /// 行数只能靠选区几何估算，这里标记出来以便显示成「约 N 行」。
    public let lineCountIsEstimated: Bool
    public let truncated: Bool

    public init(
        kind: ContentKind,
        text: String,
        headline: String,
        facts: [Fact],
        suggestions: [Suggestion],
        charCount: Int,
        lineCount: Int,
        lineCountIsEstimated: Bool,
        truncated: Bool
    ) {
        self.kind = kind
        self.text = text
        self.headline = headline
        self.facts = facts
        self.suggestions = suggestions
        self.charCount = charCount
        self.lineCount = lineCount
        self.lineCountIsEstimated = lineCountIsEstimated
        self.truncated = truncated
    }
}
