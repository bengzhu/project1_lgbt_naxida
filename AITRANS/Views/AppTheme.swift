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
        static let control: CGFloat = 12
        static let surface: CGFloat = 20
        static let hero: CGFloat = 28
        static let pill: CGFloat = 999
    }

    enum Layout {
        static let pageMaxWidth: CGFloat = 1_040
        static let workspaceMaxWidth: CGFloat = 1_240
        static let workspaceSplitWidth: CGFloat = 820
        static let inspectorWidth: CGFloat = 360
        static let minimumTarget: CGFloat = 44
        static let pageHeaderHeight: CGFloat = 92
        static let floatingTabBarClearance: CGFloat = 48
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.16)
        static let standard = Animation.easeInOut(duration: 0.22)
        static let reveal = Animation.spring(response: 0.48, dampingFraction: 0.84)
    }

    enum TextWorkspace {
        static let gridStep: CGFloat = 32
        static let majorGridInterval = 4
        static let pathLineWidth: CGFloat = 1.5
        static let paste = Color.appSuccess
        static let prompt = Color.appWarning
        static let swap = Color(red: 0.78, green: 0.24, blue: 0.58)
    }
}

enum AppFeature: String, CaseIterable {
    case text
    case image
    case ocr
    case audio
    case library
    case settings
    case system

    var eyebrow: String {
        switch self {
        case .text: "WRITE / TRANSLATE"
        case .image: "SEE / TRANSLATE"
        case .ocr: "SCAN / INSPECT"
        case .audio: "LISTEN / TRANSLATE"
        case .library: "RECALL / ORGANIZE"
        case .settings: "TUNE / CONTROL"
        case .system: "PRIVATE AI WORKSPACE"
        }
    }

    var index: String {
        switch self {
        case .text: "01"
        case .image: "02"
        case .ocr: "03"
        case .audio: "04"
        case .library: "05"
        case .settings: "06"
        case .system: "AI"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.bubble.fill"
        case .image: "photo.on.rectangle.angled"
        case .ocr: "text.viewfinder"
        case .audio: "waveform.and.mic"
        case .library: "square.grid.2x2.fill"
        case .settings: "slider.horizontal.3"
        case .system: "bolt.horizontal.circle.fill"
        }
    }

    func accent(for colorScheme: ColorScheme) -> Color {
        switch (self, colorScheme) {
        case (.text, .dark): Color(red: 0.55, green: 0.78, blue: 1.00)
        case (.text, _): Color(red: 0.00, green: 0.34, blue: 0.78)
        case (.image, .dark): Color(red: 1.00, green: 0.57, blue: 0.75)
        case (.image, _): Color(red: 0.72, green: 0.08, blue: 0.42)
        case (.ocr, .dark): Color(red: 1.00, green: 0.71, blue: 0.30)
        case (.ocr, _): Color(red: 0.67, green: 0.31, blue: 0.00)
        case (.audio, .dark): Color(red: 0.35, green: 0.88, blue: 0.67)
        case (.audio, _): Color(red: 0.00, green: 0.48, blue: 0.31)
        case (.library, .dark): Color(red: 0.77, green: 0.67, blue: 1.00)
        case (.library, _): Color(red: 0.40, green: 0.20, blue: 0.72)
        case (.settings, .dark): Color(red: 0.53, green: 0.81, blue: 0.88)
        case (.settings, _): Color(red: 0.04, green: 0.42, blue: 0.53)
        case (.system, _): Color.appAccent
        }
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
