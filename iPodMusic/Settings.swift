import SwiftUI

enum IPodTheme: String, CaseIterable {
    case white, black, u2
    var label: String {
        switch self { case .white: return "White"; case .black: return "Black"; case .u2: return "U2 Red" }
    }
}

enum ShuffleSetting: String, CaseIterable { case off, songs
    var label: String { self == .off ? "Off" : "Songs" } }
enum RepeatSetting: String, CaseIterable { case off, one, all
    var label: String { switch self { case .off: return "Off"; case .one: return "One"; case .all: return "All" } } }

/// Same choices as the web iPod's "Backlight Timer" setting.
enum BacklightTimer: String, CaseIterable {
    case off, s1, s2, s3, s5, always
    var label: String {
        switch self {
        case .off: return "Off"; case .s1: return "1 second"; case .s2: return "2 seconds"
        case .s3: return "3 seconds"; case .s5: return "5 seconds"; case .always: return "Always On"
        }
    }
    var seconds: Double? {
        switch self { case .s1: return 1; case .s2: return 2; case .s3: return 3; case .s5: return 5; default: return nil }
    }
}

@MainActor @Observable
final class AppSettings {
    private let d = UserDefaults.standard

    var theme: IPodTheme { didSet { d.set(theme.rawValue, forKey: "theme") } }
    var clicker: Bool { didSet { d.set(clicker, forKey: "clicker") } }
    var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    var backlightTimer: BacklightTimer { didSet { d.set(backlightTimer.rawValue, forKey: "backlightTimer") } }
    var jukeboxStyle: Bool { didSet { d.set(jukeboxStyle, forKey: "jukeboxStyle") } }
    var albumArt: Bool { didSet { d.set(albumArt, forKey: "albumArt") } }
    var demoMode: Bool { didSet { d.set(demoMode, forKey: "demoMode") } }
    var shuffle: ShuffleSetting { didSet { d.set(shuffle.rawValue, forKey: "shuffle") } }
    var repeatMode: RepeatSetting { didSet { d.set(repeatMode.rawValue, forKey: "repeat") } }
    var autoNowPlaying: Bool { didSet { d.set(autoNowPlaying, forKey: "autoNowPlaying") } }
    var source: MusicSourceKind { didSet { d.set(source.rawValue, forKey: "source") } }

    /// Launch-argument only (e.g. `-startScreen nowPlaying`), used for screenshots.
    let startScreen: String?
    let forcedDemo: Bool

    init() {
        d.register(defaults: ["clicker": true, "haptics": true, "backlightTimer": "always",
                              "albumArt": true, "demoMode": false, "theme": "white", "shuffle": "off",
                              "repeat": "off", "autoNowPlaying": true])
        theme = IPodTheme(rawValue: d.string(forKey: "theme") ?? "white") ?? .white
        clicker = d.bool(forKey: "clicker")
        haptics = d.bool(forKey: "haptics")
        backlightTimer = BacklightTimer(rawValue: d.string(forKey: "backlightTimer") ?? "always") ?? .always
        albumArt = d.bool(forKey: "albumArt")
        jukeboxStyle = d.bool(forKey: "jukeboxStyle")
        demoMode = d.bool(forKey: "demoMode")
        shuffle = ShuffleSetting(rawValue: d.string(forKey: "shuffle") ?? "off") ?? .off
        repeatMode = RepeatSetting(rawValue: d.string(forKey: "repeat") ?? "off") ?? .off
        autoNowPlaying = d.bool(forKey: "autoNowPlaying")
        source = MusicSourceKind(rawValue: d.string(forKey: "source") ?? "") ?? .appleMusic
        startScreen = d.string(forKey: "startScreen")
        #if targetEnvironment(simulator)
        // The simulator has no Apple Music library; always use labelled demo content there.
        forcedDemo = true
        demoMode = true
        #else
        forcedDemo = false
        #endif
    }

    func reset() {
        theme = .white; clicker = true; haptics = true; backlightTimer = .always; albumArt = true
        shuffle = .off; repeatMode = .off; autoNowPlaying = true
        jukeboxStyle = false
    }
}

struct ThemePalette {
    let bodyTop: Color, bodyBottom: Color, bodyRim: Color
    let wheel: Color, wheelInner: Color, wheelLabel: Color, wheelIcon: Color, divider: Color
    let disc1: Color, disc2: Color, discRim: Color
    let center: Color, centerRim: Color
    let background: Color

    static func of(_ t: IPodTheme) -> ThemePalette {
        switch t {
        case .white:
            // Colours from the web iPod's CSS (.ipod-container, .click-wheel, .scroll-wheel, .select-button).
            return ThemePalette(bodyTop: Color(white: 1.0), bodyBottom: Color(red: 0.91, green: 0.91, blue: 0.91),
                                bodyRim: Color(white: 0.57),
                                wheel: Color(hex: 0xF8F8F8), wheelInner: Color(hex: 0xF4F4F4),
                                wheelLabel: Color(hex: 0x898989), wheelIcon: Color(hex: 0xA3A3A3),
                                divider: Color(hex: 0x888888),
                                disc1: Color(hex: 0xEAEAEA), disc2: Color(hex: 0xF6F6F6), discRim: Color(hex: 0x7E7E7E),
                                center: Color(hex: 0xFAFAFA), centerRim: Color(hex: 0x9F9F9F),
                                background: Color(red: 0.11, green: 0.11, blue: 0.12))
        case .black:
            return ThemePalette(bodyTop: Color(white: 0.20), bodyBottom: Color(white: 0.07),
                                bodyRim: Color(white: 0.30),
                                wheel: Color(white: 0.16), wheelInner: Color(white: 0.13),
                                wheelLabel: Color(white: 0.62), wheelIcon: Color(white: 0.55), divider: Color(white: 0.30),
                                disc1: Color(white: 0.14), disc2: Color(white: 0.19), discRim: Color(white: 0.05),
                                center: Color(white: 0.12), centerRim: Color(white: 0.32),
                                background: Color(white: 0.03))
        case .u2:
            return ThemePalette(bodyTop: Color(white: 0.17), bodyBottom: Color(white: 0.06),
                                bodyRim: Color(white: 0.28),
                                wheel: Color(red: 0.80, green: 0.07, blue: 0.14), wheelInner: Color(red: 0.72, green: 0.05, blue: 0.11),
                                wheelLabel: Color(white: 0.12), wheelIcon: Color(white: 0.15),
                                divider: Color(red: 0.45, green: 0.02, blue: 0.06),
                                disc1: Color(red: 0.70, green: 0.05, blue: 0.11), disc2: Color(red: 0.82, green: 0.08, blue: 0.15),
                                discRim: Color(red: 0.40, green: 0.02, blue: 0.05),
                                center: Color(white: 0.10), centerRim: Color(white: 0.05),
                                background: Color(white: 0.03))
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}
