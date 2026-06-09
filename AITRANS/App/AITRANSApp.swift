import SwiftUI

@main
struct AITRANSApp: App {
    @StateObject private var store = TranslationSessionStore(modelService: MockGemmaService())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
