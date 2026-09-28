import Foundation
import AnywhereDoCore

struct UpdateInfo {
    let version: String
    let url: URL
}

/// 查 GitHub 上的最新 release 并与当前版本比较。
///
/// 刻意不引入 Sparkle：只要一次 GET，失败就静默（网络不通不该打扰用户）。
/// 注意：未认证的 GitHub API 限速是 60 次/小时/IP，所以自动检查有最小间隔。
enum UpdateChecker {
    static let repository = "Monkey0803/anywheredo"
    /// 自动检查的最小间隔（手动点「检查更新…」不受限制）。
    static let minimumInterval: TimeInterval = 6 * 3600

    /// 回调在主线程；没有新版本或失败时 info 为 nil。
    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("AnywhereDo/\(AnywhereDoVersion.marketing)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            var info: UpdateInfo?
            var message: String

            if let error {
                message = "检查更新：请求失败（\(error.localizedDescription)）"
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                message = "检查更新：HTTP \(http.statusCode)"
            } else if let data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = object["tag_name"] as? String,
                      let link = object["html_url"] as? String,
                      let releaseURL = URL(string: link) {
                if AnywhereDoVersion.isNewer(remote: tag, than: AnywhereDoVersion.marketing) {
                    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                    info = UpdateInfo(version: version, url: releaseURL)
                    message = "检查更新：发现新版本 \(version)（当前 \(AnywhereDoVersion.marketing)）"
                } else {
                    message = "检查更新：已是最新（远端 \(tag)，当前 \(AnywhereDoVersion.marketing)）"
                }
            } else {
                message = "检查更新：响应无法解析"
            }

            DispatchQueue.main.async {
                Diagnostics.log(message)
                completion(info)
            }
        }.resume()
    }
}
