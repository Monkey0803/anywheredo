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
        switch self {
        case .summarize: return "AI 总结"
        case .keyPoints: return "AI 提取要点"
        case .translateToChinese: return "AI 翻译成中文"
        case .translateToEnglish: return "AI 翻译成英文"
        case .polish: return "AI 润色"
        case .explainCode: return "AI 解释这段代码"
        case .findBugs: return "AI 找 Bug"
        case .explainError: return "AI 分析报错"
        case .extractTodos: return "AI 提取待办"
        case .nameAndTag: return "AI 起标题与标签"
        }
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

    public var systemPrompt: String {
        switch self {
        case .summarize:
            return "你是一个精准的文本摘要助手。用原文的语言输出，先给一句话结论，再给 3 条以内的要点。不要寒暄，不要重复原文。"
        case .keyPoints:
            return "你是一个信息提炼助手。只输出要点列表（- 开头），每条不超过 25 字，最多 6 条，使用原文语言。"
        case .translateToChinese:
            return "你是一个专业翻译。把用户内容翻译成地道简体中文，只输出译文，保留代码、命令、专有名词与原有格式。"
        case .translateToEnglish:
            return "You are a professional translator. Translate the user content into natural English. Output only the translation, preserving code, commands and formatting."
        case .polish:
            return "你是一个文字编辑。在不改变原意的前提下润色用户文本，使其更通顺、专业、简洁，只输出润色后的文本。"
        case .explainCode:
            return "你是一个资深工程师。用简体中文解释用户提供的代码：先一句话说明它做什么，再列出关键步骤，最后指出潜在风险。使用 Markdown。"
        case .findBugs:
            return "你是一个严格的代码审查者。找出用户代码中的 bug、边界问题和安全隐患，按严重程度排序，给出最小修复建议。使用简体中文与 Markdown。若确实没有明显问题，直接说明。"
        case .explainError:
            return "你是一个排错专家。根据用户提供的报错或堆栈：解释根因、指出最可能的出错位置、给出按优先级排序的修复步骤。使用简体中文。"
        case .extractTodos:
            return "你是一个任务整理助手。从用户内容中抽取可执行的待办事项，输出 Markdown 复选框列表（- [ ] ），每条包含负责人或时间（若原文提到）。"
        case .nameAndTag:
            return "你是一个信息组织助手。为用户的文本拟一个不超过 20 字的标题，并给出 3-5 个标签（#开头），用简体中文，只输出标题和标签两行。"
        }
    }
}
