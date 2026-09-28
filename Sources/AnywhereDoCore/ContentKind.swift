import Foundation

/// 剪贴板内容被识别出的类型。决定面板标题、图标与建议集合。
public enum ContentKind: String, CaseIterable, Equatable, Sendable {
    case empty
    case url
    case filePath
    case json
    case color
    case timestamp
    case email
    case phoneNumber
    case mathExpression
    case base64
    case code
    case plainText

    public var displayName: String {
        switch self {
        case .empty: return "空内容"
        case .url: return "链接"
        case .filePath: return "文件路径"
        case .json: return "JSON"
        case .color: return "颜色"
        case .timestamp: return "时间"
        case .email: return "邮箱"
        case .phoneNumber: return "电话号码"
        case .mathExpression: return "算式"
        case .base64: return "Base64"
        case .code: return "代码"
        case .plainText: return "文本"
        }
    }

    /// SF Symbol 名称（macOS 13+ 均可用）。
    public var symbolName: String {
        switch self {
        case .empty: return "clipboard"
        case .url: return "link"
        case .filePath: return "folder"
        case .json: return "curlybraces"
        case .color: return "paintpalette"
        case .timestamp: return "clock"
        case .email: return "envelope"
        case .phoneNumber: return "phone"
        case .mathExpression: return "function"
        case .base64: return "shippingbox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .plainText: return "text.alignleft"
        }
    }

    /// 面板配色用的强调色名（App 侧映射为 NSColor）。
    public var accentName: String {
        switch self {
        case .url: return "blue"
        case .filePath: return "orange"
        case .json, .code: return "purple"
        case .color: return "pink"
        case .timestamp: return "teal"
        case .email, .phoneNumber: return "green"
        case .mathExpression: return "indigo"
        case .base64: return "brown"
        case .empty, .plainText: return "gray"
        }
    }
}
