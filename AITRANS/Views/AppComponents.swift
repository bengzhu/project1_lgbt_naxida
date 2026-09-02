import SwiftUI

struct AppCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.appCanvas
            LinearGradient(
                colors: [
                    AppFeature.text.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.07),
                    Color.clear,
                    AppFeature.image.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.08 : 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [AppFeature.ocr.accent(for: colorScheme).opacity(0.07), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                .fill(Color.appAccentStrong)

            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(Color.appTextPrimary)
                .accessibilityHidden(true)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

struct AppPageHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    let title: String
    let subtitle: String
    let systemImage: String
    var status: String?
    var statusTone: AppStatusTone = .neutral
    var feature: AppFeature = .system
    @State private var isRevealed = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(feature.index)
                .font(.system(size: 68, weight: .black, design: .rounded))
                .foregroundStyle(accent.opacity(colorScheme == .dark ? 0.10 : 0.07))
                .padding(.trailing, AppTheme.Spacing.control)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: AppTheme.Spacing.control) {
                headerIdentity
                Spacer(minLength: AppTheme.Spacing.compact)
                statusLabel
            }
        }
        .padding(.horizontal, AppTheme.Spacing.section)
        .padding(.vertical, AppTheme.Spacing.control)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.pageHeaderHeight, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent.opacity(colorScheme == .dark ? 0.20 : 0.11), Color.appSurface.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: AppTheme.Radius.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                .stroke(contrast == .increased ? accent : accent.opacity(0.38), lineWidth: contrast == .increased ? 2 : 1)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent)
                .frame(width: 4, height: 46)
                .padding(.leading, 1)
                .accessibilityHidden(true)
        }
        .shadow(color: accent.opacity(colorScheme == .dark ? 0.10 : 0.08), radius: 14, y: 7)
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : 8)
        .onAppear {
            if shouldReduceMotion {
                isRevealed = true
            } else {
                withAnimation(AppTheme.Motion.reveal) { isRevealed = true }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headerIdentity: some View {
        HStack(spacing: AppTheme.Spacing.control) {
            Image(systemName: systemImage)
                .font(.headline.bold())
                .foregroundStyle(accent)
                .frame(width: 48, height: 48)
                .background(accent.opacity(0.14), in: .rect(cornerRadius: AppTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                        .stroke(accent.opacity(0.45), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(feature.eyebrow)
                    .font(.caption2.monospaced().bold())
                    .tracking(0.9)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Text(title)
                    .font(.title2.weight(.black))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(minWidth: 0, alignment: .leading)
    }

    @ViewBuilder private var statusLabel: some View {
        if let status {
            AppStatusLabel(text: status, tone: statusTone, textStyle: .caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(statusTone.color.opacity(0.12), in: .capsule)
                .overlay { Capsule().stroke(statusTone.color.opacity(0.40), lineWidth: 1) }
                .layoutPriority(1)
        }
    }

    private var accent: Color { feature.accent(for: colorScheme) }
    private var shouldReduceMotion: Bool { reduceMotion || reduceMotionOverride }
}

struct AppSectionHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.control) {
                titleLabel
                Spacer(minLength: AppTheme.Spacing.control)
                subtitleLabel
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                titleLabel
                subtitleLabel
            }
        }
    }

    @ViewBuilder private var titleLabel: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
        } else {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
        }
    }

    @ViewBuilder private var subtitleLabel: some View {
        if let subtitle {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
        }
    }
}

struct AppStatusLabel: View {
    let text: String
    let tone: AppStatusTone
    var textStyle: Font = .subheadline.bold()

    var body: some View {
        Label(text, systemImage: tone.symbol)
            .font(textStyle)
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("状态：\(text)")
    }
}

struct AppStatusRow: View {
    let title: String
    let detail: String
    let tone: AppStatusTone

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.control) {
            Image(systemName: tone.symbol)
                .font(.body.bold())
                .foregroundStyle(tone.color)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.appTextPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.Spacing.control)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.appBorder)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isWorking ? "hourglass" : systemImage)
                .font(.body.bold())
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
                .padding(.horizontal, AppTheme.Spacing.control)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appCanvas)
        .background(Color.appAccent, in: .rect(cornerRadius: AppTheme.Radius.control))
        .shadow(color: Color.appAccent.opacity(colorScheme == .dark ? 0.12 : 0.20), radius: 10, y: 5)
    }
}

struct AppSecondaryButton: View {
    let title: String
    let systemImage: String
    var tone: AppStatusTone = .neutral
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)
                .padding(.horizontal, AppTheme.Spacing.control)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tone == .neutral ? Color.appTextPrimary : tone.color)
        .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

struct AppIconButton: View {
    let title: String
    let systemImage: String
    var tone: AppStatusTone = .neutral
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.body.bold())
            .foregroundStyle(tone == .neutral ? Color.appTextPrimary : tone.color)
            .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
            .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
    }
}

struct AppEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        }
        .foregroundStyle(Color.appTextSecondary)
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct AppMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(Color.appTextSecondary)
            Text(value)
                .font(.body.bold())
                .foregroundStyle(Color.appTextPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.control)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.appBorder)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EnterprisePageFrame: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalSizeClass == .regular ? AppTheme.Spacing.tabletMargin : AppTheme.Spacing.phoneMargin)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func enterprisePageFrame(maxWidth: CGFloat = AppTheme.Layout.pageMaxWidth) -> some View {
        modifier(EnterprisePageFrame(maxWidth: maxWidth))
    }

    func appSurface(padded: Bool = true, accent: Color? = nil) -> some View {
        modifier(AppSurfaceModifier(padded: padded, accent: accent))
    }
}

private struct AppSurfaceModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let padded: Bool
    let accent: Color?

    func body(content: Content) -> some View {
        content
            .padding(padded ? AppTheme.Spacing.section : 0)
            .background(Color.appSurface, in: .rect(cornerRadius: AppTheme.Radius.surface))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                    .stroke(contrast == .increased ? Color.appTextSecondary : Color.appBorder, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if let accent {
                    Capsule()
                        .fill(accent)
                        .frame(width: 4)
                        .padding(.vertical, AppTheme.Spacing.section)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 7)
    }
}
