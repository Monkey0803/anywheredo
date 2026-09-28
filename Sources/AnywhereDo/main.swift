import AppKit
import AnywhereDoCore

// MARK: - 命令行模式（不开 GUI，方便调试分析逻辑）

func printAnalysis(_ text: String) {
    let analysis = Analyzer().analyze(text, options: AnalysisOptions(maxLength: 1200, aiEnabled: false))
    print("类型     : \(analysis.kind.rawValue)（\(analysis.kind.displayName)）")
    print("摘要     : \(analysis.headline)")
    print("规模     : \(analysis.charCount) 字符 / \(analysis.lineCount) 行\(analysis.truncated ? "（已截断）" : "")")
    if !analysis.facts.isEmpty {
        print("事实     :")
        for fact in analysis.facts {
            print("  · \(fact.label)：\(fact.value)")
        }
    }
    print("建议     :")
    for (index, suggestion) in analysis.suggestions.enumerated() {
        let subtitle = suggestion.subtitle.map { "  —— \($0)" } ?? ""
        print("  \(index + 1). \(suggestion.title)\(subtitle)")
    }
}

let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    AnywhereDo —— macOS 复制即建议

      AnywhereDo                        启动菜单栏应用
      AnywhereDo --analyze "文本"       只做一次分析并打印结果（调试用）
      AnywhereDo --analyze -            从 stdin 读取内容再分析
      AnywhereDo --check-update         检查 GitHub 上是否有新版本
      AnywhereDo --accessibility        打印辅助功能授权状态
      AnywhereDo --selection            打印当前聚焦 App 里选中的文字（验证划词）
      AnywhereDo --copy-probe           在终端里验证「合成 ⌘C + 还原剪贴板」兜底
      AnywhereDo --version              打印版本
      AnywhereDo --settings             启动并直接打开设置窗口
    """)
    exit(0)
}

if arguments.contains("--version") {
    print("AnywhereDo \(AnywhereDoVersion.marketing)")
    exit(0)
}

if let index = arguments.firstIndex(of: "--analyze") {
    let rest = Array(arguments.dropFirst(index + 1))
    var text = rest.joined(separator: " ")
    if text == "-" || text.isEmpty {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        text = String(data: data, encoding: .utf8) ?? ""
    }
    printAnalysis(text)
    exit(0)
}

if arguments.contains("--check-update") {
    // 需要一个 run loop 来收 URLSession 回到主队列的回调，不能直接 wait 信号量。
    var finished = false
    var info: UpdateInfo?
    UpdateChecker.check { result in
        info = result
        finished = true
    }
    let deadline = Date().addingTimeInterval(20)
    while !finished && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    guard finished else {
        print("检查更新超时（网络不可达？）")
        exit(2)
    }
    print("当前版本：\(AnywhereDoVersion.marketing)")
    if let info {
        print("有新版本：\(info.version)")
        print("下载页：\(info.url.absoluteString)")
        exit(0)
    } else {
        print("已是最新")
        exit(0)
    }
}

if arguments.contains("--accessibility") {
    let trusted = SelectionWatcher.isTrusted
    let line = trusted
        ? "辅助功能权限：已授予，划词可用"
        : "辅助功能权限：未授予（系统设置 → 隐私与安全性 → 辅助功能 里勾选本 App）"
    Diagnostics.section("--accessibility")
    Diagnostics.log(line + " path=" + Bundle.main.bundlePath)
    print(line)
    exit(0)
}

if arguments.contains("--selection") {
    guard SelectionWatcher.isTrusted else {
        print("没有辅助功能权限，读不到选区。可执行 --accessibility 查看状态。")
        exit(2)
    }
    if let app = NSWorkspace.shared.frontmostApplication {
        print("焦点 App：\(app.localizedName ?? "未知")")
    }
    if let text = Accessibility.currentSelectionText(), !text.isEmpty {
        Diagnostics.log("--selection：读到 \(text.count) 字，焦点 App=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        print("选区文本（\(text.count) 字）：")
        print(text)
    } else {
        Diagnostics.log("--selection：没有读到选区，焦点 App=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        print("当前没有选中文字（先选中一段文字再运行）。")
    }
    exit(0)
}

if arguments.contains("--copy-probe") {
    let before = NSPasteboard.general.string(forType: .string) ?? ""
    let beforeCount = NSPasteboard.general.changeCount
    Diagnostics.section("--copy-probe")
    Diagnostics.log("原剪贴板 长度=\(before.count)")
    print("原剪贴板长度：\(before.count)")
    if let result = CopyFallback.copySelection() {
        Diagnostics.log("兜底取到 长度=\(result.text.count) 已还原=\(result.restored ? "是" : "否")")
        print("复制到 \(result.text.count) 字：")
        print(result.text)
        print("已还原：\(result.restored ? "是" : "否")")
    } else {
        Diagnostics.log("兜底没有复制到内容")
        print("没有复制到内容（剪贴板未改动）。先在前台 App 里选中一段文字再试。")
    }
    let after = NSPasteboard.general.string(forType: .string) ?? ""
    print("现剪贴板长度：\(after.count)（应与原剪贴板一致） 变化次数=+\(NSPasteboard.general.changeCount - beforeCount)")
    exit(0)
}

// MARK: - GUI 模式

let application = NSApplication.shared
let delegate = AppDelegate()
delegate.openSettingsOnLaunch = arguments.contains("--settings")
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
