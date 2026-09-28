import XCTest
@testable import AnywhereDoCore

final class ClassifierTests: XCTestCase {
    private let analyzer = Analyzer()
    private let noFiles: (String) -> Bool = { _ in false }
    private let allFiles: (String) -> Bool = { _ in true }

    func testURL() {
        XCTAssertEqual(analyzer.classify("https://github.com/apple/swift", fileExists: noFiles), .url)
        XCTAssertEqual(analyzer.classify("  http://example.com/a?b=1  ", fileExists: noFiles), .url)
        XCTAssertEqual(analyzer.classify("www.apple.com", fileExists: noFiles), .url)
    }

    func testNotURLForTextWithSpaces() {
        XCTAssertNotEqual(analyzer.classify("看看这个 https://example.com 很不错的", fileExists: noFiles), .url)
    }

    func testJSON() {
        XCTAssertEqual(analyzer.classify("{\"a\": 1, \"b\": [2, 3]}", fileExists: noFiles), .json)
        XCTAssertEqual(analyzer.classify("[1, 2, 3]", fileExists: noFiles), .json)
        // 拼错的 JSON 应该落到文本/代码，而不是 JSON
        XCTAssertNotEqual(analyzer.classify("{\"a\": }", fileExists: noFiles), .json)
    }

    func testColor() {
        for input in ["#fff", "#FF8800", "#ff880080", "rgb(255, 136, 0)", "rgba(255,136,0,0.5)", "0x336699"] {
            XCTAssertEqual(analyzer.classify(input, fileExists: noFiles), .color, "应识别为颜色：\(input)")
        }
    }

    func testTimestamp() {
        XCTAssertEqual(analyzer.classify("1700000000", fileExists: noFiles), .timestamp)
        XCTAssertEqual(analyzer.classify("1700000000000", fileExists: noFiles), .timestamp)
        XCTAssertEqual(analyzer.classify("2024-03-05 18:30:00", fileExists: noFiles), .timestamp)
        // 超出合理范围的不算时间戳
        XCTAssertNotEqual(analyzer.classify("9999999999999", fileExists: noFiles), .timestamp)
    }

    func testEmailAndPhone() {
        XCTAssertEqual(analyzer.classify("dev@example.com", fileExists: noFiles), .email)
        XCTAssertEqual(analyzer.classify("13812345678", fileExists: noFiles), .phoneNumber)
        XCTAssertEqual(analyzer.classify("+1 (415) 555-0132", fileExists: noFiles), .phoneNumber)
    }

    func testMath() {
        XCTAssertEqual(analyzer.classify("12 * 8 + 4", fileExists: noFiles), .mathExpression)
        XCTAssertEqual(analyzer.classify("(3+5)*2^3", fileExists: noFiles), .mathExpression)
        XCTAssertEqual(analyzer.classify("2 x 3", fileExists: noFiles), .mathExpression)
    }

    func testBase64() {
        XCTAssertEqual(analyzer.classify("aGVsbG8gd29ybGQ=", fileExists: noFiles), .base64)
        // 普通英文单词不该被当成 Base64
        XCTAssertNotEqual(analyzer.classify("hello world", fileExists: noFiles), .base64)
        XCTAssertNotEqual(analyzer.classify("test", fileExists: noFiles), .base64)
    }

    func testFilePath() {
        XCTAssertEqual(analyzer.classify("/usr/local/bin", fileExists: allFiles), .filePath)
        XCTAssertEqual(analyzer.classify("/Applications/Safari.app", fileExists: noFiles), .filePath)
        XCTAssertEqual(analyzer.classify("~/Documents/notes.md", fileExists: allFiles), .filePath)
    }

    func testCode() {
        XCTAssertEqual(analyzer.classify("func add(a: Int, b: Int) -> Int {\n    return a + b\n}", fileExists: noFiles), .code)
        XCTAssertEqual(analyzer.classify("import os\n\ndef main():\n    print('hi')", fileExists: noFiles), .code)
        XCTAssertEqual(analyzer.classify("<html><body>hi</body></html>", fileExists: noFiles), .code)
    }

    func testPlainText() {
        XCTAssertEqual(analyzer.classify("今天下午三点开会，记得带上笔记本", fileExists: noFiles), .plainText)
        XCTAssertEqual(analyzer.classify("The quick brown fox jumps over the lazy dog.", fileExists: noFiles), .plainText)
    }

    func testEmpty() {
        XCTAssertEqual(analyzer.classify("   \n  ", fileExists: noFiles), .empty)
    }
}

final class AnalyzerSuggestionTests: XCTestCase {
    private let analyzer = Analyzer()

    func testURLSuggestions() {
        let analysis = analyzer.analyze("https://github.com/apple/swift", fileExists: { _ in false })
        XCTAssertEqual(analysis.kind, .url)
        XCTAssertTrue(analysis.suggestions.contains { $0.title.contains("打开") })
        guard let markdown = analysis.suggestions.first(where: { $0.id == "md" }),
              case .copyText(let text) = markdown.action else {
            return XCTFail("应该有 Markdown 复制建议")
        }
        XCTAssertEqual(text, "[github.com/swift](https://github.com/apple/swift)")
    }

    func testJSONSuggestionProducesPrettyOutput() {
        let analysis = analyzer.analyze("{\"a\":1}", fileExists: { _ in false })
        guard let suggestion = analysis.suggestions.first(where: { $0.id == "pretty" }),
              case .transform(let transform, let source) = suggestion.action else {
            return XCTFail("JSON 应该有格式化建议")
        }
        XCTAssertEqual(transform, .jsonPretty)
        guard case .success(let output) = TextTransform.apply(transform, to: source) else {
            return XCTFail("格式化应成功")
        }
        XCTAssertTrue(output.contains("\n"))
    }

    func testMathFact() {
        let analysis = analyzer.analyze("12*8+4", fileExists: { _ in false })
        XCTAssertEqual(analysis.kind, .mathExpression)
        XCTAssertTrue(analysis.facts.contains { $0.value == "100" })
    }

    func testTimestampFacts() {
        let analysis = analyzer.analyze("1700000000", fileExists: { _ in false })
        XCTAssertTrue(analysis.facts.contains { $0.label == "本地" })
        XCTAssertEqual(analysis.headline.isEmpty, false)
    }

    func testAIOnlyWhenEnabled() {
        let withoutAI = analyzer.analyze("这是一段需要总结的普通文本内容", options: AnalysisOptions(aiEnabled: false))
        XCTAssertFalse(withoutAI.suggestions.contains { $0.isAI })
        let withAI = analyzer.analyze("这是一段需要总结的普通文本内容", options: AnalysisOptions(aiEnabled: true))
        XCTAssertTrue(withAI.suggestions.contains { $0.isAI })
    }

    func testSuggestionCountIsBounded() {
        let analysis = analyzer.analyze("这是一段需要总结的普通文本内容，还带一个链接 https://example.com 顺便试试", options: AnalysisOptions(aiEnabled: true))
        XCTAssertLessThanOrEqual(analysis.suggestions.count, 9)
        XCTAssertLessThanOrEqual(analysis.suggestions.filter { !$0.isAI }.count, 6)
        XCTAssertLessThanOrEqual(analysis.suggestions.filter { $0.isAI }.count, 3)
    }

    func testTruncation() {
        let long = String(repeating: "字", count: 5000)
        let analysis = analyzer.analyze(long, options: AnalysisOptions(maxLength: 100))
        XCTAssertTrue(analysis.truncated)
        XCTAssertEqual(analysis.text.count, 100)
        XCTAssertEqual(analysis.charCount, 5000)
    }

    func testLineCountUsesRealNewlines() {
        let code = "func a() {\n    return 1\n}\n"
        let analysis = analyzer.analyze(code)
        XCTAssertEqual(analysis.lineCount, 4)
        XCTAssertFalse(analysis.lineCountIsEstimated)
        XCTAssertEqual(analysis.headline, "4 行代码")
        XCTAssertTrue(analysis.facts.contains { $0.label == "行数" && $0.value == "4" })
        XCTAssertTrue(analysis.facts.contains { $0.label == "字数" && $0.value.contains("· 4 行") })
    }

    /// 浏览器会把逐行渲染的代码块拍平，选区文本里没有换行符——
    /// 这时必须用估算值，不能谎报「1 行」。
    func testFlattenedTextUsesEstimatedLineCount() {
        let flattened = "func copySelection() {    let text: String    let restored: Bool    }"
        let analysis = analyzer.analyze(
            flattened,
            options: AnalysisOptions(estimatedLineCount: 9)
        )
        XCTAssertEqual(analysis.lineCount, 9)
        XCTAssertTrue(analysis.lineCountIsEstimated)
        XCTAssertEqual(analysis.headline, "约 9 行代码")
        XCTAssertTrue(analysis.facts.contains { $0.label == "行数" && $0.value == "约 9" })
        XCTAssertTrue(analysis.facts.contains { $0.label == "字数" && $0.value.contains("· 约 9 行") })
    }

    func testFlattenedTextWithoutEstimateDoesNotClaimOneLine() {
        let flattened = "func copySelection() {    " + String(repeating: "let x = 1    ", count: 20) + "}"
        let analysis = analyzer.analyze(flattened)
        XCTAssertEqual(analysis.lineCount, 1)
        XCTAssertFalse(analysis.lineCountIsEstimated)
        XCTAssertFalse(analysis.headline.contains("1 行代码"))
        XCTAssertTrue(analysis.facts.allSatisfy { !$0.value.contains("1 行") })
    }

    func testPlainTextWithoutNewlines() {
        let analysis = analyzer.analyze("这是一段没有换行的普通文本，只是比较长而已，用来确认标题不会写成一行。")
        XCTAssertEqual(analysis.headline.contains("· 1 行"), false)
        XCTAssertTrue(analysis.headline.hasSuffix("字符"))
    }

    func testStackTraceDetection() {
        let trace = """
        Fatal error: Index out of range
        at /Users/dev/App/Sources/Main.swift:42
        """
        let analysis = analyzer.analyze(trace, options: AnalysisOptions(aiEnabled: true))
        XCTAssertEqual(analysis.kind, .code)
        XCTAssertTrue(analysis.suggestions.contains { $0.id == "searchError" })
        XCTAssertTrue(analysis.suggestions.contains { $0.isAI })
    }
}

final class LocalizationTests: XCTestCase {
    func testTablesHaveIdenticalKeys() {
        guard let zh = L10n.table(for: "zh-Hans"), let en = L10n.table(for: "en") else {
            return XCTFail("读不到 Localizable.strings（资源没打进 bundle？）")
        }
        XCTAssertGreaterThan(zh.count, 50, "中文表条目太少，可能漏了文件")
        let missingInEn = Set(zh.keys).subtracting(en.keys)
        let missingInZh = Set(en.keys).subtracting(zh.keys)
        XCTAssertTrue(missingInEn.isEmpty, "英文表缺少：\(missingInEn.sorted())")
        XCTAssertTrue(missingInZh.isEmpty, "中文表缺少：\(missingInZh.sorted())")
    }

    func testNoEmptyOrPlaceholderTranslations() {
        for language in ["zh-Hans", "en"] {
            guard let table = L10n.table(for: language) else { return XCTFail("缺 \(language)") }
            for (key, value) in table {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) 的 \(key) 是空的")
                XCTAssertNotEqual(value, key, "\(language) 的 \(key) 没翻译")
            }
        }
    }

    /// 扫源码里所有 `L10n.t("key")` 调用点，确保 key 在两张表里都存在。
    /// 少了这条，漏 key 的后果是界面直接显示成 key 本身——很难在测试里被发现。
    func testEveryCallSiteKeyExists() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AnywhereDoCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "找不到 Sources 下的 Swift 文件")

        let pattern = try NSRegularExpression(pattern: #"L10n\.t\("([^"]+)""#)
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) { keys.insert(String(text[r])) }
            }
        }
        XCTAssertGreaterThan(keys.count, 150, "扫描到的 key 太少（\(keys.count)），正则可能失效")
        // 动态拼出来的 key（"kind.\(rawValue)" 这类）由下面的枚举测试逐个覆盖
        keys = keys.filter { !$0.contains("\\(") }

        for language in ["zh-Hans", "en"] {
            guard let table = L10n.table(for: language) else { return XCTFail("缺 \(language)") }
            let missing = keys.subtracting(table.keys).sorted()
            XCTAssertTrue(missing.isEmpty, "\(language) 表缺少这些 key：\(missing)")
        }
    }

    /// 动态 key 的覆盖面：每个枚举 case 拼出来的 key 必须在两张表里都能查到。
    func testEnumeratedKeysResolveInBothLanguages() {
        for language in ["zh-Hans", "en"] {
            guard let table = L10n.table(for: language) else { return XCTFail("缺 \(language)") }
            func check(_ key: String, _ what: String) {
                XCTAssertNotNil(table[key], "\(language) 表缺少 \(what) 的 key：\(key)")
            }
            for kind in ContentKind.allCases { check("kind.\(kind.rawValue)", "内容类型") }
            for transform in TextTransform.allCases {
                check("transform.\(transform.rawValue).title", "变换标题")
                check("transform.\(transform.rawValue).result", "变换结果标题")
            }
            for preset in AIPreset.allCases {
                check("ai.\(preset.rawValue)", "AI 动作")
                check("ai.\(preset.rawValue).prompt", "AI 提示词")
            }
        }
    }

    /// 枚举出来的文案不能等于 key 本身（等于就是漏翻）。
    func testEnumeratedTitlesAreTranslated() {
        for kind in ContentKind.allCases {
            XCTAssertNotEqual(kind.displayName, "kind.\(kind.rawValue)", "内容类型 \(kind.rawValue) 没翻译")
        }
        for transform in TextTransform.allCases {
            XCTAssertNotEqual(transform.title, "transform.\(transform.rawValue).title", "\(transform.rawValue) 标题没翻译")
            XCTAssertNotEqual(transform.resultTitle, "transform.\(transform.rawValue).result", "\(transform.rawValue) 结果标题没翻译")
        }
        for preset in AIPreset.allCases {
            XCTAssertNotEqual(preset.title, "ai.\(preset.rawValue)", "\(preset.rawValue) 没翻译")
            XCTAssertFalse(preset.systemPrompt.isEmpty, "\(preset.rawValue) 提示词为空")
            XCTAssertNotEqual(preset.systemPrompt, "ai.\(preset.rawValue).prompt", "\(preset.rawValue) 提示词没翻译")
        }
    }

    func testLanguageResolution() {
        XCTAssertEqual(L10n.resolveLanguage(from: ["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(L10n.resolveLanguage(from: ["zh-Hans"]), "zh-Hans")
        XCTAssertEqual(L10n.resolveLanguage(from: ["en-US"]), "en")
        XCTAssertEqual(L10n.resolveLanguage(from: ["ja-JP"]), "en", "不支持的语言应回退到开发语言")
        XCTAssertEqual(L10n.resolveLanguage(from: ["fr-FR", "zh-Hans-CN"]), "zh-Hans", "应取第一个能提供的")
        XCTAssertEqual(L10n.resolveLanguage(from: []), "en")
    }

    func testCurrentLanguageIsSupported() {
        XCTAssertTrue(L10n.supportedLanguages.contains(L10n.language))
        XCTAssertTrue(["en", "zh-Hans"].contains(L10n.language))
    }

    func testSpotChecks() {
        XCTAssertFalse(L10n.t("kind.url").isEmpty)
        XCTAssertEqual(L10n.t("error.notJSON", "{oops").contains("{oops"), true, "带参数的文案要能替换 %@")
    }
}

final class VersionTests: XCTestCase {
    func testDetectsNewerVersion() {
        XCTAssertTrue(AnywhereDoVersion.isNewer(remote: "v1.1.0", than: "1.0.0"))
        XCTAssertTrue(AnywhereDoVersion.isNewer(remote: "1.0.1", than: "1.0.0"))
        XCTAssertTrue(AnywhereDoVersion.isNewer(remote: "2.0", than: "1.9.9"))
        XCTAssertTrue(AnywhereDoVersion.isNewer(remote: "1.0.10", than: "1.0.9"))
        XCTAssertTrue(AnywhereDoVersion.isNewer(remote: "v1.1.0", than: "1.1.0-beta.1"))
    }

    func testDoesNotFlagSameOrOlder() {
        XCTAssertFalse(AnywhereDoVersion.isNewer(remote: "1.0.0", than: "1.0.0"))
        XCTAssertFalse(AnywhereDoVersion.isNewer(remote: "v1.0.0", than: "1.0.0"))
        XCTAssertFalse(AnywhereDoVersion.isNewer(remote: "1.0.0", than: "1.1.0"))
        XCTAssertFalse(AnywhereDoVersion.isNewer(remote: "1.1.0-beta.1", than: "1.1.0"))
    }

    func testHandlesGarbage() {
        XCTAssertFalse(AnywhereDoVersion.isNewer(remote: "not-a-version", than: "1.0.0"))
        XCTAssertTrue(AnywhereDoVersion.isNewer(remote: "1.0.0", than: "not-a-version"))
        XCTAssertEqual(AnywhereDoVersion.compare("v1.2.3", "1.2.3"), 0)
        XCTAssertEqual(AnywhereDoVersion.compare("", ""), 0)
    }
}

final class ToolTests: XCTestCase {
    func testMathEval() {
        XCTAssertEqual(MathEval.evaluate("12*8+4"), 100)
        XCTAssertEqual(MathEval.evaluate("(3+5)*2^3"), 64)
        XCTAssertEqual(MathEval.evaluate("10/4"), 2.5)
        XCTAssertEqual(MathEval.evaluate("-5 + 2"), -3)
        XCTAssertEqual(MathEval.evaluate("100 % 7"), 2)
        XCTAssertEqual(MathEval.evaluate("2 x 3"), 6)
        XCTAssertNil(MathEval.evaluate("10/0"))
        XCTAssertNil(MathEval.evaluate("abc"))
        XCTAssertEqual(MathEval.format(100), "100")
        XCTAssertEqual(MathEval.format(2.5), "2.5")
    }

    func testJSONTools() {
        XCTAssertTrue(JSONTools.isJSON("{\"a\":1}"))
        XCTAssertFalse(JSONTools.isJSON("{a:1}"))
        guard case .success(let pretty) = JSONTools.pretty("{\"b\":1,\"a\":[1,2]}") else {
            return XCTFail("应该格式化成功")
        }
        XCTAssertTrue(pretty.contains("\n  "))
        guard case .success(let minified) = JSONTools.minify("{\n  \"a\": 1\n}") else {
            return XCTFail("应该压缩成功")
        }
        XCTAssertEqual(minified, "{\"a\":1}")
    }

    func testBase64Tools() {
        XCTAssertEqual(Base64Tools.decode("aGVsbG8gd29ybGQ="), "hello world")
        XCTAssertEqual(Base64Tools.encode("hello world"), "aGVsbG8gd29ybGQ=")
        XCTAssertTrue(Base64Tools.looksLikeBase64("aGVsbG8gd29ybGQ="))
        XCTAssertFalse(Base64Tools.looksLikeBase64("hello world"))
        XCTAssertNil(Base64Tools.decode("!!!not base64!!!"))
    }

    func testColorTools() {
        let short = ColorTools.parse("#f80")
        XCTAssertEqual(short?.hex, "#FF8800")
        XCTAssertEqual(short?.rgbString, "rgb(255, 136, 0)")
        let withAlpha = ColorTools.parse("#FF880080")
        XCTAssertEqual(withAlpha?.hex, "#FF880080")
        XCTAssertEqual(ColorTools.parse("rgb(0,0,0)")?.hex, "#000000")
        XCTAssertNil(ColorTools.parse("#12345"))
        XCTAssertNil(ColorTools.parse("not a color"))
    }

    func testTimeTools() {
        let seconds = TimeTools.interpret("1700000000")
        XCTAssertNotNil(seconds)
        XCTAssertEqual(seconds?.date.timeIntervalSince1970, 1_700_000_000)
        let millis = TimeTools.interpret("1700000000000")
        XCTAssertEqual(millis?.date.timeIntervalSince1970, 1_700_000_000)
        XCTAssertNotNil(TimeTools.interpret("2024-03-05 18:30:00"))
        XCTAssertNotNil(TimeTools.interpret("2024-03-05T18:30:00Z"))
        XCTAssertNil(TimeTools.interpret("不是时间"))
    }

    func testTextTransforms() {
        XCTAssertEqual(TextTransform.apply(.trimWhitespace, to: "  hi  "), .success("hi"))
        XCTAssertEqual(TextTransform.apply(.collapseBlankLines, to: "a\n\n\n\nb"), .success("a\n\nb"))
        XCTAssertEqual(TextTransform.apply(.uppercase, to: "ab"), .success("AB"))
        guard case .success(let encoded) = TextTransform.apply(.base64Encode, to: "hello") else {
            return XCTFail("编码应成功")
        }
        XCTAssertEqual(encoded, "aGVsbG8=")
        XCTAssertEqual(TextTransform.apply(.base64Decode, to: encoded), .success("hello"))
        guard case .failure = TextTransform.apply(.jsonPretty, to: "{oops") else {
            return XCTFail("非法 JSON 应该失败")
        }
    }
}
