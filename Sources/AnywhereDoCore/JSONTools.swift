import Foundation

/// JSON 解析与格式化。Core 不依赖 AppKit，可在测试里直接用。
public struct JSONError: Error, LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }

    public init(_ message: String) { self.message = message }
}

public enum JSONTools {
    public static func value(from text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// 只有对象或数组才算「一段 JSON」；裸数字/字符串（fragment）不算，
    /// 否则会和「时间戳」「算式」抢类型。
    public static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        return value(from: trimmed) != nil
    }

    public static func pretty(_ text: String) -> Result<String, JSONError> {
        guard let object = value(from: text) else {
            return .failure(JSONError(parseError(text) ?? "无法解析"))
        }
        return serialize(object, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    public static func minify(_ text: String) -> Result<String, JSONError> {
        guard let object = value(from: text) else {
            return .failure(JSONError(parseError(text) ?? "无法解析"))
        }
        return serialize(object, options: [.withoutEscapingSlashes, .fragmentsAllowed])
    }

    /// 给出结构化摘要，例如 "对象 4 个字段"。
    public static func describe(_ text: String) -> String? {
        guard let object = value(from: text) else { return nil }
        switch object {
        case let dict as [String: Any]:
            let keys = dict.keys.sorted().prefix(4).joined(separator: ", ")
            return "对象 · \(dict.count) 个字段" + (keys.isEmpty ? "" : "（\(keys)…）")
        case let array as [Any]:
            return "数组 · \(array.count) 个元素"
        case is String: return "JSON 字符串"
        case is NSNumber: return "JSON 数字"
        case is NSNull: return "JSON null"
        default: return "JSON"
        }
    }

    private static func serialize(_ object: Any, options: JSONSerialization.WritingOptions) -> Result<String, JSONError> {
        guard JSONSerialization.isValidJSONObject(object) || options.contains(.fragmentsAllowed) else {
            return .failure(JSONError("顶层不是对象或数组"))
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: options)
            guard let string = String(data: data, encoding: .utf8) else { return .failure(JSONError("编码失败")) }
            return .success(string)
        } catch {
            return .failure(JSONError(error.localizedDescription))
        }
    }

    private static func parseError(_ text: String) -> String? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else { return nil }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return nil
        } catch {
            return (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
        }
    }
}
