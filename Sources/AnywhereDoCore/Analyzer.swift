import Foundation

public struct AnalysisOptions {
    /// 面板里保留的最大字符数，避免复制几十 MB 时把界面拖死。
    public var maxLength: Int
    /// 是否把 AI 建议一并生成（需要 App 侧配置好模型）。
    public var aiEnabled: Bool
    /// 划词时由选区几何估算出的行数：文本里没有换行符时用它兜底（见 lineCountIsEstimated）。
    public var estimatedLineCount: Int?

    public init(maxLength: Int = 3000, aiEnabled: Bool = false, estimatedLineCount: Int? = nil) {
        self.maxLength = maxLength
        self.aiEnabled = aiEnabled
        self.estimatedLineCount = estimatedLineCount
    }
}

/// 剪贴板内容 -> 类型 + 事实 + 建议。纯函数，方便单测与 CLI 调试。
public struct Analyzer {
    public init() {}

    public func analyze(
        _ raw: String,
        options: AnalysisOptions = AnalysisOptions(),
        fileExists: ((String) -> Bool)? = nil
    ) -> ClipboardAnalysis {
        let exists = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let charCount = raw.count
        let hardLineCount = raw.isEmpty ? 0 : raw.components(separatedBy: .newlines).count
        // 文本里有换行符就以它为准；没有（浏览器拍平了代码块）才用选区几何的估算值。
        let hasLineBreaks = hardLineCount > 1
        let estimate = options.estimatedLineCount.map { max(1, $0) }
        let lineCount = hasLineBreaks ? hardLineCount : (estimate ?? hardLineCount)
        let lineCountIsEstimated = !hasLineBreaks && (estimate ?? 1) > 1

        guard !trimmed.isEmpty else {
            return ClipboardAnalysis(
                kind: .empty,
                text: "",
                headline: "剪贴板里没有文本内容",
                facts: [],
                suggestions: [],
                charCount: charCount,
                lineCount: lineCount,
                lineCountIsEstimated: false,
                truncated: false
            )
        }

        let truncated = trimmed.count > options.maxLength
        let body = truncated ? String(trimmed.prefix(options.maxLength)) : trimmed
        let kind = classify(body, fileExists: exists)
        let context = Context(
            text: body,
            fullText: trimmed,
            kind: kind,
            fileExists: exists,
            aiEnabled: options.aiEnabled,
            lineCount: lineCount,
            lineCountIsEstimated: lineCountIsEstimated
        )
        let suggestions = buildSuggestions(context)
        let facts = buildFacts(context)
        let headline = buildHeadline(context, charCount: charCount, lineCount: lineCount, estimated: lineCountIsEstimated)

        return ClipboardAnalysis(
            kind: kind,
            text: body,
            headline: headline,
            facts: facts,
            suggestions: suggestions,
            charCount: charCount,
            lineCount: lineCount,
            lineCountIsEstimated: lineCountIsEstimated,
            truncated: truncated
        )
    }

    // MARK: - 分类

    public func classify(_ text: String, fileExists: ((String) -> Bool)? = nil) -> ContentKind {
        let exists = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if detectURL(trimmed) != nil { return .url }
        if detectFilePath(trimmed, fileExists: exists) != nil { return .filePath }
        if JSONTools.isJSON(trimmed) { return .json }
        if ColorTools.parse(trimmed) != nil { return .color }
        if TimeTools.interpret(trimmed) != nil { return .timestamp }
        if isEmail(trimmed) { return .email }
        if isPhoneNumber(trimmed) { return .phoneNumber }
        if MathEval.looksLikeExpression(trimmed) { return .mathExpression }
        if Base64Tools.looksLikeBase64(trimmed) { return .base64 }
        if looksLikeStackTrace(trimmed) { return .code }
        if looksLikeCode(trimmed) { return .code }
        return .plainText
    }

    // MARK: - 识别器

    func detectURL(_ text: String) -> URL? {
        let single = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !single.contains(" "), !single.contains("\n"), single.count <= 2048 else { return nil }
        let lowered = single.lowercased()
        if let url = URL(string: single), let scheme = url.scheme?.lowercased() {
            if ["http", "https", "ftp"].contains(scheme), url.host?.isEmpty == false {
                return url
            }
            if scheme == "mailto" { return nil }
            return nil
        }
        if lowered.hasPrefix("www."), URL(string: "https://\(single)") != nil {
            return URL(string: "https://\(single)")
        }
        return nil
    }

    func detectFilePath(_ text: String, fileExists: (String) -> Bool) -> String? {
        guard !text.contains("\n") else { return nil }
        var path = text
        if path.lowercased().hasPrefix("file://") {
            path = URL(string: path)?.path ?? String(path.dropFirst(7))
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        if fileExists(expanded) { return expanded }
        let parts = expanded.split(separator: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let last = parts.last.map(String.init) ?? ""
        guard last.contains(".") || expanded.hasSuffix("/") else { return nil }
        return expanded
    }

    func isEmail(_ text: String) -> Bool {
        guard !text.contains(" "), !text.contains("\n"), text.count <= 254 else { return false }
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    func isPhoneNumber(_ text: String) -> Bool {
        let single = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !single.contains("\n"), single.count <= 24 else { return false }
        let digits = single.filter { $0.isNumber }
        guard digits.count >= 7, digits.count <= 15 else { return false }
        if single.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil { return true }
        let hasSeparator = single.contains("-") || single.contains(" ") || single.contains("(") || single.contains("+")
        guard hasSeparator else { return false }
        return single.range(of: "^\\+?[0-9][0-9\\s\\-().]{5,}[0-9]$", options: .regularExpression) != nil
    }

    func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        let lowered = " " + trimmed.lowercased() + " "
        let strongMarkers = [
            "func ", "def ", "class ", "struct ", "interface ", "import ", "#include", "#import",
            "public ", "private ", "static ", "=> ", "=>\n", "::", "console.log", "println(",
            "printf(", "print(", "->", "where ",
            "select ", "insert into", "create table", "<?xml", "<html", "<!doctype", "#!/", "async ",
            "await ", "});", "};", "];", "return {", "{\n  ",
        ]
        let weakMarkers = [
            "let ", "var ", "const ", "return ", "if (", "for (", "while (", "else {", "self.",
            "this.", "null", "nil", "true", "false", "</", "/>", "<?", "?>", " = 0", "== ", "!= ",
            "from ", "limit ",
        ]
        var score = 0
        for marker in strongMarkers where lowered.contains(marker) { score += 2 }
        for marker in weakMarkers where lowered.contains(marker) { score += 1 }

        let hasBraces = trimmed.contains("{") && trimmed.contains("}")
        let hasStatementEndings = trimmed.contains(";")
        let looksMarkup = trimmed.hasPrefix("<") && trimmed.contains(">")
        let structural = hasBraces || looksMarkup || (hasStatementEndings && trimmed.contains("("))
        guard structural else { return score >= 4 }
        return score >= 2
    }

    func looksLikeStackTrace(_ text: String) -> Bool {
        let lowered = text.lowercased()
        var score = 0
        for signal in ["exception", "traceback (most recent call last)", "error:", "panic:", "fatal error",
                       "caused by:", "stack trace", "uncaught", "segmentation fault", "assertion failed"] {
            if lowered.contains(signal) { score += 1 }
        }
        if text.range(of: "[A-Za-z0-9_./-]+\\.(swift|java|kt|py|js|ts|tsx|go|rs|cs|cpp|c|h|m|mm):[0-9]+",
                      options: .regularExpression) != nil {
            score += 2
        }
        if lowered.contains(" at ") && lowered.contains("(") { score += 1 }
        return score >= 2
    }

    func guessLanguage(_ text: String) -> String? {
        let lowered = text.lowercased()
        if lowered.contains("#!/bin/bash") || lowered.contains("#!/bin/sh") { return "Shell" }
        if lowered.contains("import swift") || lowered.contains("@objc") || lowered.contains("guard let ") { return "Swift" }
        if lowered.contains(":= ") || lowered.contains("package main") { return "Go" }
        if lowered.contains("func ") && (lowered.contains("->") || lowered.contains("let ") || lowered.contains("var ")) { return "Swift" }
        if lowered.contains("func ") && lowered.contains("func (") { return "Go" }
        if lowered.contains("#include") || lowered.contains("std::") { return "C/C++" }
        if lowered.contains("def ") || lowered.contains("import ") && lowered.contains(":") { return "Python" }
        if lowered.contains("</") || lowered.contains("<!doctype") { return "HTML" }
        if lowered.contains("select ") && lowered.contains("from ") { return "SQL" }
        if lowered.contains("interface ") && lowered.contains(";") { return "TypeScript" }
        if lowered.contains("console.log") || lowered.contains("=> ") { return "JavaScript" }
        if lowered.contains("public class") || lowered.contains("system.out") { return "Java" }
        if lowered.contains("func ") || lowered.contains("package ") { return "Go" }
        return nil
    }

    // MARK: - 上下文与建议

    struct Context {
        let text: String
        let fullText: String
        let kind: ContentKind
        let fileExists: (String) -> Bool
        let aiEnabled: Bool
        let lineCount: Int
        let lineCountIsEstimated: Bool
    }

    func buildSuggestions(_ context: Context) -> [Suggestion] {
        var items: [Suggestion] = []
        let text = context.text

        switch context.kind {
        case .empty:
            break

        case .url:
            if let url = detectURL(text) {
                items.append(Suggestion(id: "open", title: "在浏览器打开", subtitle: url.host, symbol: "safari", action: .openURL(url)))
                let label = markdownLabel(for: url)
                items.append(Suggestion(id: "md", title: "复制为 Markdown 链接", subtitle: "[\(label)](\(url.absoluteString))", symbol: "text.badge.plus", action: .copyText("[\(label)](\(url.absoluteString))")))
                if let host = url.host {
                    items.append(Suggestion(id: "site", title: "只复制域名", subtitle: host, symbol: "doc.on.doc", action: .copyText(host)))
                }
                items.append(Suggestion(id: "search", title: "用 Google 搜索这个链接", symbol: "magnifyingglass", action: .searchWeb(url.absoluteString)))
            }

        case .filePath:
            if let path = detectFilePath(text, fileExists: context.fileExists) {
                let name = (path as NSString).lastPathComponent
                if context.fileExists(path) {
                    items.append(Suggestion(id: "reveal", title: "在 Finder 中显示", subtitle: name, symbol: "folder", action: .revealInFinder(path)))
                    items.append(Suggestion(id: "open", title: "用默认应用打开", subtitle: name, symbol: "arrow.up.forward.app", action: .openFile(path)))
                } else {
                    items.append(Suggestion(id: "copy", title: "复制绝对路径", subtitle: path, symbol: "doc.on.doc", action: .copyText(path)))
                }
                items.append(Suggestion(id: "parent", title: "复制所在文件夹", subtitle: (path as NSString).deletingLastPathComponent, symbol: "folder.badge.plus", action: .copyText((path as NSString).deletingLastPathComponent)))
                items.append(Suggestion(id: "terminal", title: "复制 cd 命令", subtitle: "cd \(quotedShell(path))", symbol: "terminal", action: .copyText("cd \(quotedShell(path))")))
            }

        case .json:
            items.append(Suggestion(id: "pretty", title: "格式化 JSON", subtitle: "缩进后在新窗口预览", symbol: "text.alignleft", action: .transform(.jsonPretty, source: text)))
            items.append(Suggestion(id: "minify", title: "压缩成一行", symbol: "arrow.down.right.and.arrow.up.left", action: .transform(.jsonMinify, source: text)))
            items.append(Suggestion(id: "copy", title: "复制原文", symbol: "doc.on.doc", action: .copyText(text)))

        case .color:
            if let color = ColorTools.parse(text) {
                items.append(Suggestion(id: "hex", title: "复制 HEX", subtitle: color.hex, symbol: "number", action: .copyText(color.hex)))
                items.append(Suggestion(id: "rgb", title: "复制 rgb()", subtitle: color.rgbString, symbol: "circle.grid.cross", action: .copyText(color.rgbString)))
                items.append(Suggestion(id: "swift", title: "复制 SwiftUI Color", subtitle: color.swiftLiteral, symbol: "swift", action: .copyText(color.swiftLiteral)))
                items.append(Suggestion(id: "hsb", title: "复制 HSB", subtitle: color.hsbString, symbol: "paintbrush", action: .copyText(color.hsbString)))
            }

        case .timestamp:
            if let interpreted = TimeTools.interpret(text) {
                let date = interpreted.date
                items.append(Suggestion(id: "copyLocal", title: "复制本地时间", subtitle: TimeTools.localString(date), symbol: "calendar", action: .copyText(TimeTools.localString(date))))
                items.append(Suggestion(id: "copyISO", title: "复制 ISO 8601", subtitle: TimeTools.isoString(date), symbol: "clock.arrow.circlepath", action: .copyText(TimeTools.isoString(date))))
                items.append(Suggestion(id: "copySeconds", title: "复制 Unix 秒", subtitle: TimeTools.unixSeconds(date), symbol: "timer", action: .copyText(TimeTools.unixSeconds(date))))
                items.append(Suggestion(id: "copyMillis", title: "复制 Unix 毫秒", subtitle: TimeTools.unixMillis(date), symbol: "timer.square", action: .copyText(TimeTools.unixMillis(date))))
                items.append(Suggestion(id: "calendar", title: "创建日历事件", subtitle: "在日历中新建这天的事件", symbol: "calendar.badge.plus", action: .openURL(calendarURL(date))))
            }

        case .email:
            let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(Suggestion(id: "mail", title: "写邮件", subtitle: "mailto:\(address)", symbol: "envelope", action: .composeEmail(address)))
            items.append(Suggestion(id: "copy", title: "复制邮箱地址", symbol: "doc.on.doc", action: .copyText(address)))
            items.append(Suggestion(id: "domain", title: "提取域名", subtitle: address.split(separator: "@").last.map(String.init) ?? "", symbol: "globe", action: .copyText(address.split(separator: "@").last.map(String.init) ?? address)))

        case .phoneNumber:
            let number = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = number.filter { $0.isNumber || $0 == "+" }
            items.append(Suggestion(id: "sms", title: "发信息", subtitle: number, symbol: "message", action: .sendMessage(digits)))
            items.append(Suggestion(id: "call", title: "用 FaceTime 拨打", subtitle: number, symbol: "phone", action: .callNumber(digits)))
            items.append(Suggestion(id: "copy", title: "只复制数字", subtitle: digits, symbol: "doc.on.doc", action: .copyText(digits)))

        case .mathExpression:
            if let value = MathEval.evaluate(text) {
                let formatted = MathEval.format(value)
                items.append(Suggestion(id: "copyResult", title: "复制计算结果", subtitle: formatted, symbol: "equal.circle", action: .copyText(formatted)))
            }
            items.append(Suggestion(id: "copy", title: "复制原算式", symbol: "doc.on.doc", action: .copyText(text)))

        case .base64:
            if let decoded = Base64Tools.decode(text) {
                items.append(Suggestion(id: "decode", title: "查看解码结果", subtitle: previewLine(decoded), symbol: "lock.open", action: .transform(.base64Decode, source: text)))
            }
            items.append(Suggestion(id: "copy", title: "复制原文", symbol: "doc.on.doc", action: .copyText(text)))

        case .code:
            let isTrace = looksLikeStackTrace(text)
            if isTrace {
                items.append(Suggestion(id: "searchError", title: "搜索这条报错", subtitle: previewLine(firstErrorLine(text)), symbol: "magnifyingglass", action: .searchWeb(firstErrorLine(text))))
            }
            items.append(Suggestion(id: "copy", title: "复制代码", subtitle: "\(context.text.components(separatedBy: .newlines).count) 行", symbol: "doc.on.doc", action: .copyText(text)))
            items.append(Suggestion(id: "trim", title: "去除首尾空白", symbol: "text.alignleft", action: .transform(.trimWhitespace, source: text)))
            items.append(Suggestion(id: "collapse", title: "合并多余空行", symbol: "arrow.up.and.down.text.horizontal", action: .transform(.collapseBlankLines, source: text)))
            if let language = guessLanguage(text) {
                items.append(Suggestion(id: "searchLang", title: "搜索 \(language) 相关写法", subtitle: previewLine(firstCodeLine(text)), symbol: "magnifyingglass", action: .searchWeb(firstCodeLine(text))))
            }

        case .plainText:
            if let url = firstURL(in: text) {
                items.append(Suggestion(id: "openFirst", title: "打开文中的链接", subtitle: url.absoluteString, symbol: "link", action: .openURL(url)))
            }
            let query = previewLine(text, limit: 100)
            items.append(Suggestion(id: "search", title: "用 Google 搜索", subtitle: query, symbol: "magnifyingglass", action: .searchWeb(query)))
            let target = isMostlyChinese(text) ? "en" : "zh-CN"
            items.append(Suggestion(id: "translate", title: target == "en" ? "用 Google 翻译成英文" : "用 Google 翻译成中文", subtitle: "在浏览器中打开翻译页", symbol: "character.book.closed", action: .openURL(translateURL(text, target: target))))
            items.append(Suggestion(id: "copy", title: "复制为纯文本", subtitle: "去除首尾空白", symbol: "doc.on.doc", action: .copyText(text)))
            items.append(Suggestion(id: "collapse", title: "合并多余空行", symbol: "arrow.up.and.down.text.horizontal", action: .transform(.collapseBlankLines, source: text)))
        }

        if context.aiEnabled {
            items.append(contentsOf: aiSuggestions(for: context))
        }

        // 去掉重复，最多 6 条普通建议 + 2 条 AI 建议。
        var seen = Set<String>()
        let deduped = items.filter { seen.insert($0.id).inserted }
        let ai = deduped.filter { $0.isAI }.prefix(3)
        let plain = deduped.filter { !$0.isAI }.prefix(6)
        return Array(plain) + Array(ai)
    }

    func aiSuggestions(for context: Context) -> [Suggestion] {
        let text = context.text
        var presets: [AIPreset] = []
        switch context.kind {
        case .code:
            presets = looksLikeStackTrace(text) ? [.explainError, .findBugs, .explainCode] : [.explainCode, .findBugs, .extractTodos]
        case .json:
            presets = [.explainCode, .summarize]
        case .plainText:
            presets = [isMostlyChinese(text) ? .translateToEnglish : .translateToChinese, .summarize, .keyPoints]
        default:
            presets = [.summarize]
        }
        return presets.map { preset in
            Suggestion(id: "ai.\(preset.rawValue)", title: preset.title, subtitle: "使用已配置的模型", symbol: preset.symbol, action: .ai(preset, source: text))
        }
    }

    func buildFacts(_ context: Context) -> [Fact] {
        var facts: [Fact] = []
        let text = context.text

        switch context.kind {
        case .json:
            if let description = JSONTools.describe(text) {
                facts.append(Fact(label: "结构", value: description))
            }
            facts.append(Fact(label: "大小", value: "\(text.count) 字符"))
        case .color:
            if let color = ColorTools.parse(text) {
                facts.append(Fact(label: "HEX", value: color.hex, monospaced: true))
                facts.append(Fact(label: "RGB", value: color.rgbString, monospaced: true))
                facts.append(Fact(label: "HSB", value: color.hsbString, monospaced: true))
            }
        case .timestamp:
            if let interpreted = TimeTools.interpret(text) {
                facts.append(Fact(label: "识别为", value: interpreted.source))
                facts.append(Fact(label: "本地", value: TimeTools.localString(interpreted.date), monospaced: true))
                facts.append(Fact(label: "UTC", value: utcString(interpreted.date), monospaced: true))
            }
        case .mathExpression:
            if let value = MathEval.evaluate(text) {
                facts.append(Fact(label: "结果", value: MathEval.format(value), monospaced: true))
            }
        case .base64:
            if let decoded = Base64Tools.decode(text) {
                facts.append(Fact(label: "解码预览", value: previewLine(decoded, limit: 80)))
            }
        case .code:
            if context.lineCount > 1 {
                facts.append(Fact(label: "行数", value: context.lineCountIsEstimated ? "约 \(context.lineCount)" : "\(context.lineCount)"))
            }
            if let language = guessLanguage(text) {
                facts.append(Fact(label: "语言", value: language))
            }
            if looksLikeStackTrace(text) {
                facts.append(Fact(label: "类型", value: "疑似报错 / 堆栈"))
            }
        case .url:
            if let url = detectURL(text) {
                if let scheme = url.scheme { facts.append(Fact(label: "协议", value: scheme)) }
                if let host = url.host { facts.append(Fact(label: "域名", value: host)) }
            }
        case .filePath:
            if let path = detectFilePath(text, fileExists: context.fileExists) {
                if context.fileExists(path), let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                    if let size = attributes[.size] as? NSNumber {
                        facts.append(Fact(label: "大小", value: ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)))
                    }
                    if let modified = attributes[.modificationDate] as? Date {
                        facts.append(Fact(label: "修改时间", value: TimeTools.localString(modified)))
                    }
                }
                facts.append(Fact(label: "路径", value: path, monospaced: true))
            }
        case .email, .phoneNumber, .empty, .plainText:
            break
        }

        if [.plainText, .code, .email, .phoneNumber, .base64].contains(context.kind) {
            // 没有换行符时不谎报「1 行」——要么给出估算，要么只说字符数。
            var value = "\(text.count) 字符"
            if context.lineCount > 1 {
                value += context.lineCountIsEstimated ? " · 约 \(context.lineCount) 行" : " · \(context.lineCount) 行"
            }
            facts.append(Fact(label: "字数", value: value))
        }
        return facts
    }

    func buildHeadline(_ context: Context, charCount: Int, lineCount: Int, estimated: Bool = false) -> String {
        switch context.kind {
        case .empty: return "没有可分析的文本"
        case .url: return detectURL(context.text)?.host ?? "链接"
        case .filePath:
            return detectFilePath(context.text, fileExists: context.fileExists)
                .map { ($0 as NSString).lastPathComponent } ?? "文件路径"
        case .json: return JSONTools.describe(context.text) ?? "JSON"
        case .color: return ColorTools.parse(context.text)?.hex ?? "颜色"
        case .timestamp: return TimeTools.interpret(context.text).map { TimeTools.localString($0.date) } ?? "时间"
        case .email: return "邮件地址"
        case .phoneNumber: return "电话号码"
        case .mathExpression:
            if let value = MathEval.evaluate(context.text) { return "= \(MathEval.format(value))" }
            return "算式"
        case .base64: return "Base64 编码内容"
        case .code:
            if looksLikeStackTrace(context.text) { return "疑似报错 / 堆栈" }
            guard lineCount > 1 else { return "代码片段" }
            return estimated ? "约 \(lineCount) 行代码" : "\(lineCount) 行代码"
        case .plainText:
            return lineCount > 1 ? "\(charCount) 字符 · \(estimated ? "约 " : "")\(lineCount) 行" : "\(charCount) 字符"
        }
    }

    // MARK: - 小工具

    func markdownLabel(for url: URL) -> String {
        if let host = url.host {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.isEmpty { return host }
            let last = (path as NSString).lastPathComponent
            return last.isEmpty ? host : "\(host)/\(last)"
        }
        return url.absoluteString
    }

    func quotedShell(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func previewLine(_ text: String, limit: Int = 60) -> String {
        let line = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return String(line.prefix(limit))
    }

    func firstErrorLine(_ text: String) -> String {
        let keywords = ["error", "exception", "panic", "fatal", "failed", "traceback"]
        let lines = text.components(separatedBy: .newlines)
        for line in lines where keywords.contains(where: { line.lowercased().contains($0) }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(160)) }
        }
        return previewLine(text, limit: 160)
    }

    func firstCodeLine(_ text: String) -> String {
        previewLine(text, limit: 120)
    }

    func isMostlyChinese(_ text: String) -> Bool {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) { cjk += 1 }
            else if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) { latin += 1 }
        }
        if cjk == 0 { return false }
        return cjk * 4 >= latin
    }

    func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector.firstMatch(in: text, options: [], range: range)
        guard let url = match?.url else { return nil }
        return url
    }

    func utcString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }

    func translateURL(_ text: String, target: String) -> URL {
        var components = URLComponents(string: "https://translate.google.com/") ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "op", value: "translate"),
            URLQueryItem(name: "text", value: String(text.prefix(1500))),
        ]
        return components.url ?? URL(string: "https://translate.google.com/")!
    }

    func calendarURL(_ date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = formatter.string(from: date)
        let end = formatter.string(from: date.addingTimeInterval(3600))
        var components = URLComponents(string: "https://calendar.google.com/calendar/render") ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "dates", value: "\(stamp)/\(end)"),
        ]
        return components.url ?? URL(string: "https://calendar.google.com/")!
    }

    /// 供 App 侧执行 `.searchWeb` 时构造真实地址。
    public static func webSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: String(query.prefix(500)))]
        return components?.url
    }
}
