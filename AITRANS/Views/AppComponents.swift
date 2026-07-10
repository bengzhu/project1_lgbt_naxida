import SwiftUI

struct AppCanvasBackground: View {
    var body: some View {
        Color.appCanvas
            .ignoresSafeArea()
    }
}

struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                .fill(Color.appAccentStrong)

            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.appTextPrimary)
                .accessibilityHidden(true)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

struct AppPageHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var status: String?
    var statusTone: AppStatusTone = .neutral

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.control) {
                headerIdentity
                Spacer(minLength: AppTheme.Spacing.control)
                if let status {
                    AppStatusLabel(text: status, tone: statusTone)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
                headerIdentity
                if let status {
                    AppStatusLabel(text: status, tone: statusTone)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headerIdentity: some View {
        HStack(spacing: AppTheme.Spacing.control) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.appAccent)
                .frame(width: 44, height: 44)
                .background(Color.appSurfaceRaised, in: .rect(cornerRadius: AppTheme.Radius.surface))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.appTextPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.appTextSecondary)
            }
        }
    }
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
                .foregroundStyle(.appTextPrimary)
        } else {
            Text(title)
                .font(.headline)
                .foregroundStyle(.appTextPrimary)
        }
    }

    @ViewBuilder private var subtitleLabel: some View {
        if let subtitle {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.appTextSecondary)
        }
    }
}

struct AppStatusLabel: View {
    let text: String
    let tone: AppStatusTone

    var body: some View {
        Label(text, systemImage: tone.symbol)
            .font(.subheadline.bold())
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
                    .foregroundStyle(.appTextPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.appTextSecondary)
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
        .foregroundStyle(.appTextSecondary)
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
                .foregroundStyle(.appTextSecondary)
            Text(value)
                .font(.body.bold())
                .foregroundStyle(.appTextPrimary)
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

    func appSurface(padded: Bool = true) -> some View {
        modifier(AppSurfaceModifier(padded: padded))
    }
}

private struct AppSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityContrast) private var contrast
    let padded: Bool

    func body(content: Content) -> some View {
        content
            .padding(padded ? AppTheme.Spacing.section : 0)
            .background(Color.appSurface, in: .rect(cornerRadius: AppTheme.Radius.surface))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.surface)
                    .stroke(contrast == .increased ? Color.appTextSecondary : Color.appBorder, lineWidth: 1)
            }
    }
}
