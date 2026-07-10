import SwiftUI

@main
struct AITRANSApp: App {
    @StateObject private var store: TranslationSessionStore

    init() {
        let store = TranslationSessionStore(modelService: MockGemmaService())
#if DEBUG
        if let scenarioName = ProcessInfo.processInfo.environment["AITRANS_UI_EVIDENCE_SCENARIO"],
           let scenario = AppPreviewScenario(rawValue: scenarioName) {
            scenario.configure(store)
        }
#endif
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
