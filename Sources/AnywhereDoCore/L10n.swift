import Foundation

/// 多语言入口。
///
/// 所有用户可见文案都走这里，Core 与 App 共用同一张表：
/// `Sources/AnywhereDoCore/Resources/<语言>.lproj/Localizable.strings`。
///
/// 为什么不用 `NSLocalizedString(key, bundle: .module)` 的默认解析：
/// 裸可执行文件（`swift run` / CI 里的 CLI 冒烟测试）没有 Info.plist，
/// `Bundle.main` 的偏好语言解析会退化成英文，导致中文系统也出英文。
/// 这里改成「拿系统偏好语言去匹配我们真正提供的语言」，行为可预测、可测。
public enum L10n {
    /// 我们**确实**提供了哪些语言，与 `Resources/*.lproj` 目录一一对应。
    ///
    /// 刻意不用 `Bundle.localizations` 枚举：不同 SwiftPM/Xcode 版本对本地化资源的处理不一致
    /// （实测同一个包在 CI runner 上只报 `en`，而 `path(forResource:forLocalization:)` 却能正常取到中文表），
    /// 那会让「系统是中文还是英文」的判断随工具链漂移。
    /// 语言文件是否真的打进包里，由 `LocalizationTests` 逐张读表来保证。
    public static let supportedLanguages = ["en", "zh-Hans"]

    /// 当前生效语言：取系统偏好语言里第一个我们能提供的，进行前缀匹配（`zh-Hans-CN` → `zh-Hans`）。
    public static let language: String = resolveLanguage(from: Locale.preferredLanguages)

    private static let table: [String: String] = load(language) ?? [:]

    /// 当前语言下的文案；缺 key 时返回 key 本身，方便一眼看出漏翻。
    public static func t(_ key: String) -> String {
        table[key] ?? key
    }

    /// 带参数的文案，例如 `L10n.t("error.notJSON", detail)` 对应 `"error.notJSON" = "不是合法 JSON：%@";`
    public static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: table[key] ?? key, arguments: arguments)
    }

    /// 读取指定语言的整张表（测试用它保证两种语言 key 集合一致）。
    public static func table(for language: String) -> [String: String]? {
        load(language)
    }

    static func resolveLanguage(from preferred: [String]) -> String {
        let supported = supportedLanguages
        guard !supported.isEmpty else { return "en" }
        for candidate in preferred {
            if let exact = supported.first(where: { candidate == $0 || candidate.hasPrefix($0 + "-") }) {
                return exact
            }
            if let base = candidate.split(separator: "-").first,
               let match = supported.first(where: { $0 == base }) {
                return match
            }
        }
        return supported.contains("en") ? "en" : supported[0]
    }

    private static func load(_ language: String) -> [String: String]? {
        guard let path = Bundle.module.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: language
        ) else { return nil }
        return NSDictionary(contentsOfFile: path) as? [String: String]
    }
}
