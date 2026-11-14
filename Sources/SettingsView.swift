import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var a: Assistant
    @ObservedObject private var s = AppSettings.shared
    @ObservedObject private var llm: LocalLLM
    @Environment(\.dismiss) private var dismiss

    init() {
        _llm = ObservedObject(wrappedValue: Assistant.shared.llm)
    }

    private let locales: [(id: String, name: String)] = [
        ("auto", "Avtomatik (o'zbekcha → ruscha → turkcha)"),
        ("uz-UZ", "O'zbekcha"),
        ("ru-RU", "Ruscha"),
        ("tr-TR", "Turkcha"),
        ("en-US", "Inglizcha"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Uyg'otuvchi so'z") {
                    Toggle("“Hey Sherik” ni doim tingla", isOn: $s.wakeEnabled)
                        .onChange(of: s.wakeEnabled) { _, _ in a.restartListening() }
                    Toggle("Ishlayotganda ekranni o'chirma", isOn: $s.keepScreenOn)
                }

                Section("Ovoz tanish") {
                    Picker("Til", selection: $s.localeID) {
                        ForEach(locales, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: s.localeID) { _, _ in a.restartListening() }
                    Text(a.sttInfo).font(.footnote).foregroundStyle(.secondary)
                }

                Section("Internet (og'ir savollar uchun)") {
                    SecureField("Claude API kaliti (sk-ant-…)", text: $s.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model", text: $s.cloudModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Internetda qidirishga ruxsat", isOn: $s.useWebSearch)
                    Toggle("Har safar so'ramasdan internetga chiq", isOn: $s.autoCloud)
                    Text("Odatda Sherik internetga chiqishdan oldin sizdan ruxsat so'raydi. Internetni o'zi yoqa olmaydi — Wi-Fi yoki mobil internet telefonda yoqilgan bo'lishi kerak.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Offline miya (Gemma 3 1B)") {
                    switch llm.state {
                    case .ready: Label("Tayyor — internetsiz ishlaydi", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .downloading: Text("Yuklanmoqda: \(Int(llm.progress * 100))%")
                    case .notLoaded: Text("Yuklanmagan")
                    case .failed(let e): Text("Xato: \(e)").foregroundStyle(.red)
                    }
                    Button("Qayta yuklash") { Task { await llm.load() } }
                    Button("Suhbatni tozalash", role: .destructive) { a.clearConversation() }
                }
            }
            .navigationTitle("Sozlamalar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tayyor") { dismiss() } } }
        }
    }
}
