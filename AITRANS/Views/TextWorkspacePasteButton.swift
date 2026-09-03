import SwiftUI
import UniformTypeIdentifiers

struct TextWorkspacePasteButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let onPaste: ([String]) -> Void

    var body: some View {
        PasteButton(supportedContentTypes: [.text], payloadAction: loadText)
            .buttonStyle(.plain)
            .foregroundStyle(.clear)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
            .overlay {
                ZStack {
                    Color.appSurfaceRaised
                    AppTheme.TextWorkspace.paste.opacity(isEnabled ? 0.12 : 0.07)
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.TextWorkspace.paste)
                        .padding(.horizontal, AppTheme.Spacing.control)
                }
                .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: AppTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .stroke(AppTheme.TextWorkspace.paste.opacity(isEnabled ? 0.72 : 0.42), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.56)
            .contentShape(.rect)
    }

    private func loadText(from providers: [NSItemProvider]) {
        guard let provider = providers.first(where: {
            $0.canLoadObject(ofClass: NSString.self)
        }) else {
            onPaste([])
            return
        }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            let text = value as? String ?? ""
            Task { @MainActor in
                onPaste(text.isEmpty ? [] : [text])
            }
        }
    }
}
