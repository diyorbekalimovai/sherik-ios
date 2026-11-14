import AppIntents

struct ListenIntent: AppIntent {
    static let title: LocalizedStringResource = "Sherikni chaqirish"
    static let description = IntentDescription("Sherik ochiladi va buyruqni tinglay boshlaydi.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Assistant.shared.requestActivation()
        return .result()
    }
}

struct SherikShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ListenIntent(),
            phrases: [
                "\(.applicationName)",
                "Hey \(.applicationName)",
                "\(.applicationName)ni och",
                "\(.applicationName)ni chaqir",
            ],
            shortTitle: "Sherik",
            systemImageName: "mic.circle.fill")
    }
}
