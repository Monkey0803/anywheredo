import Foundation

public enum TextTransformError: Error, LocalizedError, Equatable {
    case notJSON(String)
    case notBase64
    case invalidPercentEncoding

    public var errorDescription: String? {
        switch self {
        case .notJSON(let detail): return L10n.t("error.notJSON", detail)
        case .notBase64: return L10n.t("error.notBase64")
        case .invalidPercentEncoding: return L10n.t("error.invalidPercentEncoding")
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
        L10n.t("transform.\(rawValue).title")
    }

    public var resultTitle: String {
        L10n.t("transform.\(rawValue).result")
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
