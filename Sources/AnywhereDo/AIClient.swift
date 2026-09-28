import Foundation
import AnywhereDoCore

struct AIRequestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 只实现 OpenAI 兼容的 /chat/completions，DeepSeek、OpenAI、本地 Ollama/vLLM 都能用。
final class AIClient {
    private let config: AIConfig

    init(config: AIConfig) {
        self.config = config
    }

    private var endpoint: URL? {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { return URL(string: base) }
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/chat/completions")
    }

    func complete(preset: AIPreset, content: String) async throws -> String {
        try await request(system: preset.systemPrompt, user: content)
    }

    func complete(system: String, user: String) async throws -> String {
        try await request(system: system, user: user)
    }

    private func request(system: String, user: String) async throws -> String {
        guard config.isUsable else {
            throw AIRequestError(message: "尚未配置 AI：请在「设置 → AI」里填写 Base URL、模型与 API Key。")
        }
        guard let endpoint else {
            throw AIRequestError(message: "Base URL 不合法：\(config.baseURL)")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "temperature": config.temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIRequestError(message: "没有收到有效的 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw AIRequestError(message: "HTTP \(http.statusCode)：\(String(detail.prefix(300)))")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIRequestError(message: "无法解析模型响应：\(String(raw.prefix(300)))")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIRequestError(message: "模型返回了空内容")
        }
        return trimmed
    }
}
