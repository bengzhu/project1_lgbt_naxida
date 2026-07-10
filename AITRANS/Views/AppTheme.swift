import SwiftUI

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
    static let appCanvas = Color(red: 0.035, green: 0.043, blue: 0.047)
    static let appSurface = Color(red: 0.070, green: 0.082, blue: 0.087)
    static let appSurfaceRaised = Color(red: 0.100, green: 0.116, blue: 0.122)
    static let appBorder = Color(red: 0.20, green: 0.24, blue: 0.25)
    static let appTextPrimary = Color(red: 0.95, green: 0.97, blue: 0.97)
    static let appTextSecondary = Color(red: 0.66, green: 0.70, blue: 0.71)
    static let appAccent = Color(red: 0.08, green: 0.78, blue: 0.82)
    static let appAccentStrong = Color(red: 0.02, green: 0.58, blue: 0.64)
    static let success = Color(red: 0.24, green: 0.78, blue: 0.47)
    static let warning = Color(red: 0.96, green: 0.68, blue: 0.22)
    static let danger = Color(red: 0.94, green: 0.28, blue: 0.32)
    static let locked = Color(red: 0.56, green: 0.58, blue: 0.61)

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
