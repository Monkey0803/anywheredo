import Foundation

public enum TextTransformError: Error, LocalizedError, Equatable {
    case notJSON(String)
    case notBase64
    case invalidPercentEncoding

    public var errorDescription: String? {
        switch self {
        case .notJSON(let detail): return "不是合法 JSON：\(detail)"
        case .notBase64: return "不是合法的 Base64 内容"
        case .invalidPercentEncoding: return "百分号编码不合法"
        }
    }
}

/// 可预览、可撤销的本地文本变换。
public enum TextTransform: String, CaseIterable, Equatable, Sendable {
    case jsonPretty
    case jsonMinify
    case base64Decode
    case base64Encode
    case percentDecode
    case percentEncode
    case trimWhitespace
    case collapseBlankLines
    case uppercase
    case lowercase

    public var title: String {
        switch self {
        case .jsonPretty: return "格式化 JSON"
        case .jsonMinify: return "压缩成一行"
        case .base64Decode: return "解码 Base64"
        case .base64Encode: return "编码为 Base64"
        case .percentDecode: return "URL 解码"
        case .percentEncode: return "URL 编码"
        case .trimWhitespace: return "去除首尾空白"
        case .collapseBlankLines: return "合并多余空行"
        case .uppercase: return "转为大写"
        case .lowercase: return "转为小写"
        }
    }

    public var resultTitle: String {
        switch self {
        case .jsonPretty: return "格式化结果"
        case .jsonMinify: return "压缩结果"
        case .base64Decode: return "解码结果"
        case .base64Encode: return "编码结果"
        case .percentDecode: return "解码结果"
        case .percentEncode: return "编码结果"
        case .trimWhitespace: return "处理结果"
        case .collapseBlankLines: return "处理结果"
        case .uppercase: return "大写结果"
        case .lowercase: return "小写结果"
        }
    }

    public static func apply(_ transform: TextTransform, to input: String) -> Result<String, TextTransformError> {
        switch transform {
        case .jsonPretty:
            return JSONTools.pretty(input).mapError { TextTransformError.notJSON($0.message) }
        case .jsonMinify:
            return JSONTools.minify(input).mapError { TextTransformError.notJSON($0.message) }
        case .base64Decode:
            guard let decoded = Base64Tools.decode(input) else { return .failure(.notBase64) }
            return .success(decoded)
        case .base64Encode:
            return .success(Base64Tools.encode(input))
        case .percentDecode:
            guard let decoded = input.removingPercentEncoding else { return .failure(.invalidPercentEncoding) }
            return .success(decoded)
        case .percentEncode:
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return .success(input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input)
        case .trimWhitespace:
            return .success(input.trimmingCharacters(in: .whitespacesAndNewlines))
        case .collapseBlankLines:
            return .success(collapseBlankLines(input))
        case .uppercase:
            return .success(input.uppercased())
        case .lowercase:
            return .success(input.lowercased())
        }
    }

    private static func collapseBlankLines(_ input: String) -> String {
        var result: [String] = []
        var lastWasBlank = false
        for line in input.components(separatedBy: .newlines) {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && lastWasBlank { continue }
            result.append(isBlank ? "" : line)
            lastWasBlank = isBlank
        }
        return result.joined(separator: "\n")
    }
}
