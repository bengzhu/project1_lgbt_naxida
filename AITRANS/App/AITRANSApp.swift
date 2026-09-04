import SwiftUI

@main
@MainActor
struct AITRANSApp: App {
    @StateObject private var store: TranslationSessionStore
    @State private var adBlockStore: AdBlockStore

    init() {
        _adBlockStore = State(initialValue: AdBlockStore())
#if DEBUG
        if let scenarioName = ProcessInfo.processInfo.environment["AITRANS_UI_EVIDENCE_SCENARIO"],
           let scenario = AppPreviewScenario(rawValue: scenarioName) {
            let store = TranslationSessionStore(
                modelService: MockGemmaService(),
                persistenceURL: FileManager.default.temporaryDirectory
                    .appending(path: "aitrans-ui-evidence-\(UUID().uuidString).json"),
                performsStartupWork: false
            )
            scenario.configure(store)
            _store = StateObject(wrappedValue: store)
            return
        }
#endif
        _store = StateObject(wrappedValue: TranslationSessionStore(modelService: MockGemmaService()))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(adBlockStore)
                .task { adBlockStore.send(.bootstrap) }
        }
    }
}
