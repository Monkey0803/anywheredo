import Foundation

/// 版本号的**唯一来源**。
///
/// `scripts/build_app.sh` 会把这个常量注入 `.app` 的 `Info.plist`（替换 `__VERSION__`），
/// `--version` 与「检查更新」也读它——所以发版只需要改这一个地方。
public enum AnywhereDoVersion {
    public static let marketing = "1.1.0"

    /// 语义化版本比较，返回 -1 / 0 / 1。
    ///
    /// 支持 `v1.2.3`、`1.2.3`、`1.2`，以及 `1.2.0-beta.1` 这种预发布形式
    /// （数字部分相同时，预发布比正式版**旧**）。
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = parse(lhs)
        let right = parse(rhs)

        let count = max(left.numbers.count, right.numbers.count)
        for index in 0..<count {
            let a = index < left.numbers.count ? left.numbers[index] : 0
            let b = index < right.numbers.count ? right.numbers[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }

        switch (left.prerelease, right.prerelease) {
        case (nil, nil):
            return 0
        case (.some, nil):
            return -1
        case (nil, .some):
            return 1
        case (.some(let a), .some(let b)):
            if a == b { return 0 }
            return a < b ? -1 : 1
        }
    }

    /// 远端版本是否比本地新。
    public static func isNewer(remote: String, than local: String) -> Bool {
        compare(remote, local) > 0
    }

    private static func parse(_ raw: String) -> (numbers: [Int], prerelease: String?) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numeric = parts.first.map(String.init) ?? ""
        let numbers = numeric.split(separator: ".").map { component -> Int in
            Int(component.prefix(while: { $0.isNumber })) ?? 0
        }
        let prerelease = parts.count > 1 ? String(parts[1]) : nil
        return (numbers, prerelease)
    }
}
