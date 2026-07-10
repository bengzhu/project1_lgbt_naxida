import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "日间"
    case dark = "夜间"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppTheme {
    enum Spacing {
        static let compact: CGFloat = 6
        static let control: CGFloat = 10
        static let section: CGFloat = 16
        static let page: CGFloat = 24
        static let phoneMargin: CGFloat = 16
        static let tabletMargin: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 6
        static let surface: CGFloat = 8
    }

    enum Layout {
        static let pageMaxWidth: CGFloat = 1_040
        static let workspaceMaxWidth: CGFloat = 1_240
        static let workspaceSplitWidth: CGFloat = 820
        static let inspectorWidth: CGFloat = 360
        static let minimumTarget: CGFloat = 44
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.16)
        static let standard = Animation.easeInOut(duration: 0.22)
    }
}

extension Color {
    static let success = Color.appSuccess
    static let warning = Color.appWarning
    static let danger = Color.appDanger
    static let locked = Color.appLocked

    // Compatibility for feature views migrated in later phases.
    static let panel = Color.appSurface
}

enum AppStatusTone {
    case neutral
    case active
    case success
    case warning
    case danger
    case locked

    var color: Color {
        switch self {
        case .neutral: .appTextSecondary
        case .active: .appAccent
        case .success: .success
        case .warning: .warning
        case .danger: .danger
        case .locked: .locked
        }
    }

    var symbol: String {
        switch self {
        case .neutral: "circle"
        case .active: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .locked: "lock.fill"
        }
    }
}

private struct AppReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appReduceMotionOverride: Bool {
        get { self[AppReduceMotionOverrideKey.self] }
        set { self[AppReduceMotionOverrideKey.self] = newValue }
    }
}
