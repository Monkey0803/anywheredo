import Foundation

/// 「忽略的 App」名单的数据逻辑。
///
/// 放在 Core 而不是设置窗口里，是为了能单测：界面上手输、从运行中的 App 挑选、
/// 点按钮移除，三条路最终都落到这几个函数上。
public enum IgnoredApps {
    /// 解析手输串：中英文逗号都认，去掉空白，去重且保持顺序。
    public static func parse(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, id in
                if !result.contains(id) { result.append(id) }
            }
    }

    /// 追加一个 bundle id；已存在或为空则原样返回（幂等）。
    public static func adding(_ id: String, to list: [String]) -> [String] {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !list.contains(trimmed) else { return list }
        return list + [trimmed]
    }

    /// 移除一个 bundle id；不存在则原样返回。
    public static func removing(_ id: String, from list: [String]) -> [String] {
        list.filter { $0 != id }
    }

    /// 转回界面上手输框的显示形式。
    public static func display(_ list: [String]) -> String {
        list.joined(separator: ", ")
    }
}
