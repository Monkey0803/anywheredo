import AppKit
import Foundation

struct AIConfig: Codable, Equatable {
    var enabled: Bool = false
    var baseURL: String = "https://api.deepseek.com/v1"
    var model: String = "deepseek-chat"
    var apiKey: String = ""
    var temperature: Double = 0.3

    var isUsable: Bool {
        guard enabled, !apiKey.isEmpty, !model.isEmpty else { return false }
        guard let url = URL(string: baseURL), url.scheme?.hasPrefix("http") == true else { return false }
        return true
    }
}

struct AppSettings: Codable, Equatable {
    /// 总开关：关闭后完全不读剪贴板、也不读选区。
    var enabled: Bool = true
    /// 复制后弹出建议（需要读剪贴板）。默认关闭：不想让「每次 ⌘C 都弹窗」打扰。
    var watchClipboard: Bool = false
    /// 划词后弹出建议（需要「辅助功能」权限）。
    var watchSelection: Bool = true
    /// 划词时使用紧凑卡片：不显示预览、建议只留前 3 条。
    var selectionCompact: Bool = true
    /// 对读不到选区的 App（Chrome/Electron）用「合成 ⌘C + 还原剪贴板」兜底。
    /// 默认关闭：它会短暂改写剪贴板，只有在你能接受时才打开。
    var selectionCopyFallback: Bool = false
    /// 按住 ⌘/⌥ 划词时直接执行第一条建议（不弹卡片，也不调用 AI）。
    var selectionModifierInstant: Bool = false
    /// 是否在弹窗里显示内容预览。
    var showPreview: Bool = true
    /// 是否让弹窗可以接受 Esc / 数字快捷键。
    var keyboardShortcuts: Bool = true
    /// 自动关闭秒数，0 表示不自动关闭。
    var autoDismissSeconds: Double = 8
    /// 面板里保留的最大字符数。
    var maxContentLength: Int = 3000
    /// 忽略带「敏感/临时」标记的内容（密码管理器会打这类标记）。
    var ignoreSensitive: Bool = true
    /// 来源 App 黑名单（bundle id）。
    var ignoredBundleIDs: [String] = AppSettings.defaultIgnoredBundleIDs
    /// 弹窗相对鼠标的偏移量。
    var popupOffset: Double = 14
    /// 登录时启动。
    var launchAtLogin: Bool = false
    /// 是否已经就「划词需要辅助功能权限」提醒过用户（只提醒一次）。
    var didPromptForAccessibility: Bool = false
    /// 启动时检查新版本（只发一个 GET 到 GitHub releases API，不含任何个人信息）。
    var checkForUpdates: Bool = true
    /// 上次检查更新的时间，用于限流。
    var lastUpdateCheck: Date?
    var ai: AIConfig = AIConfig()

    static let defaultIgnoredBundleIDs: [String] = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "in.sinew.Enpass-Desktop",
    ]

    init() {}

    // 手写解码：新增字段后旧配置文件仍然可用。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        watchClipboard = try container.decodeIfPresent(Bool.self, forKey: .watchClipboard) ?? defaults.watchClipboard
        watchSelection = try container.decodeIfPresent(Bool.self, forKey: .watchSelection) ?? defaults.watchSelection
        selectionCompact = try container.decodeIfPresent(Bool.self, forKey: .selectionCompact) ?? defaults.selectionCompact
        selectionCopyFallback = try container.decodeIfPresent(Bool.self, forKey: .selectionCopyFallback) ?? defaults.selectionCopyFallback
        selectionModifierInstant = try container.decodeIfPresent(Bool.self, forKey: .selectionModifierInstant) ?? defaults.selectionModifierInstant
        showPreview = try container.decodeIfPresent(Bool.self, forKey: .showPreview) ?? defaults.showPreview
        keyboardShortcuts = try container.decodeIfPresent(Bool.self, forKey: .keyboardShortcuts) ?? defaults.keyboardShortcuts
        autoDismissSeconds = try container.decodeIfPresent(Double.self, forKey: .autoDismissSeconds) ?? defaults.autoDismissSeconds
        maxContentLength = try container.decodeIfPresent(Int.self, forKey: .maxContentLength) ?? defaults.maxContentLength
        ignoreSensitive = try container.decodeIfPresent(Bool.self, forKey: .ignoreSensitive) ?? defaults.ignoreSensitive
        ignoredBundleIDs = try container.decodeIfPresent([String].self, forKey: .ignoredBundleIDs) ?? defaults.ignoredBundleIDs
        popupOffset = try container.decodeIfPresent(Double.self, forKey: .popupOffset) ?? defaults.popupOffset
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        didPromptForAccessibility = try container.decodeIfPresent(Bool.self, forKey: .didPromptForAccessibility) ?? defaults.didPromptForAccessibility
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? defaults.checkForUpdates
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        ai = try container.decodeIfPresent(AIConfig.self, forKey: .ai) ?? defaults.ai
    }
}

final class SettingsStore {
    static let directoryName = "AnywhereDo"
    static let fileName = "settings.json"

    private(set) var settings: AppSettings
    var onChange: ((AppSettings) -> Void)?

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var fileURL: URL { directoryURL.appendingPathComponent(fileName) }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
        writeTemplateIfNeeded()
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard copy != settings else { return }
        settings = copy
        save()
        onChange?(settings)
    }

    func reload() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        settings = decoded
        onChange?(settings)
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: Self.fileURL, options: [.atomic])
            // 里面可能存了 API key，收紧权限。
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
        } catch {
            NSLog("AnywhereDo: 保存设置失败 \(error.localizedDescription)")
        }
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Self.fileURL])
    }

    private func writeTemplateIfNeeded() {
        guard !FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        save()
    }
}
