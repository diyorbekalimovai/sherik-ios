import Foundation
import Security

enum Keychain {
    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var wakeEnabled: Bool { didSet { d.set(wakeEnabled, forKey: "wakeEnabled") } }
    @Published var keepScreenOn: Bool { didSet { d.set(keepScreenOn, forKey: "keepScreenOn") } }
    @Published var localeID: String { didSet { d.set(localeID, forKey: "localeID") } }
    @Published var cloudModel: String { didSet { d.set(cloudModel, forKey: "cloudModel") } }
    @Published var useWebSearch: Bool { didSet { d.set(useWebSearch, forKey: "useWebSearch") } }
    @Published var autoCloud: Bool { didSet { d.set(autoCloud, forKey: "autoCloud") } }
    @Published var apiKey: String { didSet { Keychain.set(apiKey, for: "anthropic_key") } }

    init() {
        d.register(defaults: [
            "wakeEnabled": true,
            "keepScreenOn": true,
            "localeID": "auto",
            "cloudModel": "claude-sonnet-5-5",
            "useWebSearch": true,
            "autoCloud": false,
        ])
        wakeEnabled = d.bool(forKey: "wakeEnabled")
        keepScreenOn = d.bool(forKey: "keepScreenOn")
        localeID = d.string(forKey: "localeID") ?? "auto"
        cloudModel = d.string(forKey: "cloudModel") ?? "claude-sonnet-5-5"
        useWebSearch = d.bool(forKey: "useWebSearch")
        autoCloud = d.bool(forKey: "autoCloud")
        apiKey = Keychain.get("anthropic_key")
    }
}
