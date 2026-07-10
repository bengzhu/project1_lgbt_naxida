import SwiftUI

struct TextWorkspacePasteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Label("粘贴", systemImage: "doc.on.clipboard")
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
            .padding(.horizontal, AppTheme.Spacing.control)
            .foregroundStyle(AppTheme.TextWorkspace.paste)
            .background(
                AppTheme.TextWorkspace.paste.opacity(configuration.isPressed ? 0.20 : 0.12),
                in: .rect(cornerRadius: AppTheme.Radius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .stroke(AppTheme.TextWorkspace.paste.opacity(isEnabled ? 0.72 : 0.42), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.56)
            .contentShape(.rect)
    }
}
