import SwiftUI
import Translation

/// Owns the SwiftUI-only `TranslationSession` lifecycle while product requests
/// and results remain inside `TranslationSessionStore` and its adapter.
struct AppleTranslationTaskHost<Content: View>: View {
    @ObservedObject var service: AppleTranslationService
    @ViewBuilder let content: Content

    init(
        service: AppleTranslationService,
        @ViewBuilder content: () -> Content
    ) {
        self.service = service
        self.content = content()
    }

    var body: some View {
        if #available(iOS 18.0, *) {
            content
                .translationTask(service.configuration) { session in
                    await service.runPendingJob(with: session)
                }
        } else {
            content
        }
    }
}
