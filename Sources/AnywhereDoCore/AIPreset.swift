import Foundation

/// 交给大模型的预设任务。配置了 AI 后才会出现在建议列表里。
public enum AIPreset: String, CaseIterable, Equatable, Sendable {
    case summarize
    case keyPoints
    case translateToChinese
    case translateToEnglish
    case polish
    case explainCode
    case findBugs
    case explainError
    case extractTodos
    case nameAndTag

    public var title: String {
        L10n.t("ai.\(rawValue)")
    }

    public var symbol: String {
        switch self {
        case .summarize: return "sparkles"
        case .keyPoints: return "list.bullet.rectangle"
        case .translateToChinese, .translateToEnglish: return "character.book.closed"
        case .polish: return "wand.and.sparkles"
        case .explainCode: return "text.magnifyingglass"
        case .findBugs: return "ladybug"
        case .explainError: return "exclamationmark.triangle"
        case .extractTodos: return "checklist"
        case .nameAndTag: return "tag"
        }
    }

    /// AI 系统提示词随界面语言走：英文界面下要求用英文回答。
    public var systemPrompt: String {
        L10n.t("ai.\(rawValue).prompt")
    }

}
