import SwiftUI

struct TextWorkspaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Color.appCanvas

            LinearGradient(
                colors: baseColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawTranslationPath(context: &context, size: size)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var baseColors: [Color] {
        if colorScheme == .dark {
            [
                Color.appSurfaceRaised.opacity(0.72),
                Color.appCanvas.opacity(0.98),
                Color.appSurface.opacity(0.82)
            ]
        } else {
            [
                Color.appSurface.opacity(0.92),
                Color.appCanvas.opacity(0.98),
                Color.appSurfaceRaised.opacity(0.68)
            ]
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let step = AppTheme.TextWorkspace.gridStep
        let minorColor = Color.appBorder.opacity(contrast == .increased ? 0.46 : 0.24)
        let majorColor = Color.appTextSecondary.opacity(contrast == .increased ? 0.34 : 0.14)

        for (index, x) in stride(from: 0.0, through: size.width, by: step).enumerated() {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(
                path,
                with: .color(index.isMultiple(of: AppTheme.TextWorkspace.majorGridInterval) ? majorColor : minorColor),
                lineWidth: index.isMultiple(of: AppTheme.TextWorkspace.majorGridInterval) ? 0.8 : 0.5
            )
        }

        for (index, y) in stride(from: 0.0, through: size.height, by: step).enumerated() {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(index.isMultiple(of: AppTheme.TextWorkspace.majorGridInterval) ? majorColor : minorColor),
                lineWidth: index.isMultiple(of: AppTheme.TextWorkspace.majorGridInterval) ? 0.8 : 0.5
            )
        }
    }

    private func drawTranslationPath(context: inout GraphicsContext, size: CGSize) {
        let start = CGPoint(x: size.width * 0.08, y: size.height * 0.34)
        let end = CGPoint(x: size.width * 0.92, y: size.height * 0.58)
        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: size.width * 0.36, y: size.height * 0.18),
            control2: CGPoint(x: size.width * 0.64, y: size.height * 0.72)
        )
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [Color.appAccent.opacity(0.10), Color.appAccent.opacity(0.48), Color.appSuccess.opacity(0.14)]),
                startPoint: start,
                endPoint: end
            ),
            lineWidth: AppTheme.TextWorkspace.pathLineWidth
        )

        for point in [start, CGPoint(x: size.width * 0.5, y: size.height * 0.47), end] {
            let marker = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            context.fill(Path(marker), with: .color(Color.appAccent.opacity(0.72)))
        }
    }
}
