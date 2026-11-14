import Foundation
import Network

enum CloudError: LocalizedError {
    case noKey
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .noKey: return "Internet kaliti kiritilmagan."
        case .http(let code, let body): return "Server xatosi \(code): \(body)"
        case .empty: return "Bo'sh javob keldi."
        }
    }
}

/// Og'ir savollar uchun Claude API (faqat foydalanuvchi ruxsat bergandan keyin chaqiriladi).
enum CloudClient {
    static func ask(messages: [(role: String, text: String)], apiKey: String, model: String, webSearch: Bool) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudError.noKey }

        func call(tools: Bool) async throws -> (Int, Data) {
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 90
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            var body: [String: Any] = [
                "model": model,
                "max_tokens": 800,
                "system": Persona.cloudSystem,
                "messages": messages.map { ["role": $0.role, "content": $0.text] },
            ]
            if tools {
                body["tools"] = [["type": "web_search_20250305", "name": "web_search", "max_uses": 3]]
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
        }

        var result = try await call(tools: webSearch)
        if result.0 == 400 && webSearch { result = try await call(tools: false) }
        guard result.0 == 200 else {
            let body = String(data: result.1, encoding: .utf8) ?? ""
            throw CloudError.http(result.0, String(body.prefix(160)))
        }
        guard let json = try JSONSerialization.jsonObject(with: result.1) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else { throw CloudError.empty }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw CloudError.empty }
        return text
    }
}

final class NetworkMonitor: ObservableObject {
    @Published var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.isOnline = (path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "uz.sherik.net"))
    }
}
