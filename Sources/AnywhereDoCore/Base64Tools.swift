import Foundation

public enum Base64Tools {
    /// 容忍缺失 padding 与内部换行。
    public static func decode(_ input: String) -> String? {
        var cleaned = input
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        cleaned = cleaned.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !cleaned.isEmpty else { return nil }
        let remainder = cleaned.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 {
            cleaned += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    public static func encode(_ input: String) -> String {
        Data(input.utf8).base64EncodedString()
    }

    /// 保守判断：必须是合法字符集，解码后能构成可读 UTF-8 文本。
    public static func looksLikeBase64(_ input: String) -> Bool {
        let cleaned = input.components(separatedBy: .whitespacesAndNewlines).joined()
        guard cleaned.count >= 8, cleaned.count <= 200_000 else { return false }
        guard cleaned.count % 4 == 0 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        // 纯字母数字且无 padding 的短串极易误判，要求更严格的信号。
        let hasSymbol = cleaned.contains("=") || cleaned.contains("+") || cleaned.contains("/")
        if !hasSymbol && cleaned.count < 16 { return false }
        guard let decoded = decode(cleaned), !decoded.isEmpty else { return false }
        let scalars = decoded.unicodeScalars
        guard !scalars.isEmpty else { return false }
        var printable = 0
        for scalar in scalars {
            if scalar.properties.isWhitespace || (scalar.value >= 32 && scalar.value != 127) { printable += 1 }
        }
        guard Double(printable) / Double(scalars.count) >= 0.92 else { return false }
        // 解码结果不能只是几个重复字符，否则更像标识符。
        guard Set(decoded).count >= 3 else { return false }
        return true
    }
}
