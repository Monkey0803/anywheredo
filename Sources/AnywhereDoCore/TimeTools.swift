import Foundation

public enum TimeTools {
    public struct Interpreted: Equatable {
        public let date: Date
        /// 命中时的解释方式，展示给用户，例如 "Unix 时间戳（秒）"。
        public let source: String
    }

    /// Unix 时间戳（秒或毫秒）、ISO8601、常见日期格式。
    public static func interpret(_ text: String) -> Interpreted? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }

        if trimmed.allSatisfy({ $0.isNumber }) {
            guard let value = Double(trimmed) else { return nil }
            let date: Date
            let source: String
            switch trimmed.count {
            case 13:
                date = Date(timeIntervalSince1970: value / 1000)
                source = "Unix 时间戳（毫秒）"
            case 10:
                date = Date(timeIntervalSince1970: value)
                source = "Unix 时间戳（秒）"
            default:
                return nil
            }
            guard isPlausible(date) else { return nil }
            return Interpreted(date: date, source: source)
        }

        if let date = isoFormatter.date(from: trimmed) ?? isoFractionalFormatter.date(from: trimmed) {
            guard isPlausible(date) else { return nil }
            return Interpreted(date: date, source: "ISO 8601")
        }
        for (formatter, label) in localFormatters() {
            if let date = formatter.date(from: trimmed) {
                guard isPlausible(date) else { return nil }
                return Interpreted(date: date, source: label)
            }
        }
        return nil
    }

    public static func isPlausible(_ date: Date) -> Bool {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return year >= 1990 && year <= 2100
    }

    public static func localString(_ date: Date) -> String {
        localFormatter.string(from: date)
    }

    public static func isoString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    public static func unixSeconds(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970.rounded()))
    }

    public static func unixMillis(_ date: Date) -> String {
        String(Int((date.timeIntervalSince1970 * 1000).rounded()))
    }

    // MARK: - Formatters

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter
    }()

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        return formatter
    }()

    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func makeFormatter(_ format: String, label: String) -> (DateFormatter, String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return (formatter, label)
    }

    private static func localFormatters() -> [(DateFormatter, String)] {
        [
            makeFormatter("yyyy-MM-dd HH:mm:ss", label: "本地日期时间"),
            makeFormatter("yyyy-MM-dd HH:mm", label: "本地日期时间"),
            makeFormatter("yyyy-MM-dd'T'HH:mm:ss", label: "本地日期时间"),
            makeFormatter("yyyy-MM-dd", label: "本地日期"),
            makeFormatter("yyyy/MM/dd HH:mm:ss", label: "本地日期时间"),
            makeFormatter("yyyy/MM/dd", label: "本地日期"),
            makeFormatter("yyyy年MM月dd日 HH:mm", label: "本地日期时间"),
            makeFormatter("yyyy年MM月dd日", label: "本地日期"),
            makeFormatter("dd/MM/yyyy", label: "日期（日/月/年）"),
            makeFormatter("MM/dd/yyyy", label: "日期（月/日/年）"),
        ]
    }
}
