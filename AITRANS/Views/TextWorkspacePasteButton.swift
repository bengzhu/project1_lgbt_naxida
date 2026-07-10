import SwiftUI

struct TextWorkspacePasteButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let onPaste: ([String]) -> Void

    var body: some View {
        PasteButton(payloadType: String.self, onPaste: onPaste)
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
}
