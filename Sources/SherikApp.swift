import SwiftUI

@main
struct SherikApp: App {
    @StateObject private var assistant = Assistant.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assistant)
                .preferredColorScheme(.dark)
        }
    }
}
