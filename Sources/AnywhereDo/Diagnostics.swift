import AppKit
import Foundation

/// 诊断日志：只记录「状态」——权限、App 名、内容长度、坐标是否可用，
/// 绝不记录剪贴板或选区的具体内容。
enum Diagnostics {
    static var fileURL: URL {
        SettingsStore.directoryURL.appendingPathComponent("diagnostics.log")
    }

    static func log(_ message: String) {
        NSLog("AnywhereDo: %@", message)
        append("[\(timestamp())] \(message)\n")
    }

    static func section(_ title: String) {
        append("\n[\(timestamp())] ===== \(title) =====\n")
    }

    static func reveal() {
        try? FileManager.default.createDirectory(at: SettingsStore.directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Data("（还没有诊断信息）\n".utf8).write(to: fileURL)
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: SettingsStore.directoryURL, withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }

        let limit = 512 * 1024
        if let attributes = try? manager.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > limit {
            try? data.write(to: fileURL)
            return
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
