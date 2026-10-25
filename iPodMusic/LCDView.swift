import SwiftUI
import MusicKit

let lcdInk = Color(hex: 0x484647)

extension Font {
    static func chicago(_ size: CGFloat) -> Font { .custom("PixelifySans-Regular", size: size) }
}

/// The LCD: 273 × 223 content box with an 8 px bezel, title bar (37 px) and a
/// 181.7 px body that holds the sliding screens.
struct LCDView: View {
    let u: CGFloat
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let lit = nav.lit
        ZStack {
            LCDBackground(lit: lit)
            VStack(spacing: 0) {
                TitleBar(u: u, title: nav.current.spec.title, playing: player.isPlaying, hasItem: player.hasItem)
                    .frame(height: 37 * u)
                ZStack(alignment: .top) {
                    ScreenContent(u: u, screen: nav.current)
                        .id(nav.current.id)
                        .transition(.asymmetric(insertion: .move(edge: nav.forward ? .trailing : .leading),
                                                removal: .move(edge: nav.forward ? .leading : .trailing)))
                }
                .frame(width: 273 * u, height: 181.7 * u, alignment: .top)
                .clipped()
                .padding(.top, 1.7 * u)
                Spacer(minLength: 0)
            }
            .environment(\.lcdLit, lit)
        }
        .frame(width: 273 * u, height: 223 * u)
        .clipShape(RoundedRectangle(cornerRadius: 3 * u))
        // backlit: inset 0 0 0 5px rgba(71,71,71,.85); otherwise inset 0 0 10px 2px #4d4d4d
        .overlay(
            RoundedRectangle(cornerRadius: 3 * u)
                .strokeBorder(Color(hex: 0x474747).opacity(lit ? 0.85 : 0.6), lineWidth: (lit ? 5 : 4) * u)
                .blur(radius: (lit ? 0.6 : 4) * u)
                .clipShape(RoundedRectangle(cornerRadius: 3 * u))
        )
        .padding(8 * u)
        .background(
            RoundedRectangle(cornerRadius: 10 * u, style: .continuous)
                .fill(Color.black.opacity(lit ? 0.72 : 0.5))
        )
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}

private struct LCDLitKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var lcdLit: Bool { get { self[LCDLitKey.self] } set { self[LCDLitKey.self] = newValue } }
}

struct LCDBackground: View {
    let lit: Bool
    var body: some View {
        ZStack {
            // linear-gradient(135deg, #a5a59b, #d6d5d0)
            LinearGradient(colors: [Color(hex: 0xA5A59B), Color(hex: 0xD6D5D0)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if lit {
                // --ipod-bg-scrim #0f69ff blended plus-lighter → pale blue backlight
                LinearGradient(colors: [Color(hex: 0xA9BCD3), Color(hex: 0xC9D7EA), Color(hex: 0xDCE7F7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // three warm bulbs along the left edge + fainter ones on the right (backlit ::after)
                GeometryReader { g in
                    ZStack {
                        ForEach([0.19, 0.53, 0.83], id: \.self) { y in
                            RadialGradient(colors: [Color(red: 254/255, green: 249/255, blue: 220/255).opacity(0.55), .clear],
                                           center: UnitPoint(x: 0, y: y), startRadius: 0, endRadius: g.size.width * 0.42)
                            RadialGradient(colors: [Color(red: 254/255, green: 249/255, blue: 220/255).opacity(0.25), .clear],
                                           center: UnitPoint(x: 1, y: y), startRadius: 0, endRadius: g.size.width * 0.18)
                        }
                    }
                    .blendMode(.plusLighter)
                    .opacity(0.5)
                }
            } else {
                Color(hex: 0x484647).opacity(0.10)
            }
        }
    }
}

struct TitleBar: View {
    let u: CGFloat
    let title: String
    let playing: Bool
    let hasItem: Bool

    var body: some View {
        ZStack {
            Text(title)
                .font(.chicago(23 * u))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: (273 - 10 - 86) * u)
                .offset(y: 3 * u)
            HStack(spacing: 0) {
                if hasItem {
                    PlayStateIcon(playing: playing).frame(width: 14 * u, height: 16 * u).padding(.leading, 10 * u).offset(y: 1.2 * u)
                }
                Spacer()
                BatteryIcon(u: u).padding(.trailing, 5 * u).offset(y: -1 * u)
            }
        }
        .foregroundStyle(lcdInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(lcdInk).frame(height: 2 * u) }
        .padding(.horizontal, 5 * u)
    }
}

struct PlayStateIcon: View {
    let playing: Bool
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            if playing {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: w, y: h / 2)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                ctx.fill(p, with: .color(lcdInk))
            } else {
                ctx.fill(Path(CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.3, height: h * 0.8)), with: .color(lcdInk))
                ctx.fill(Path(CGRect(x: w * 0.6, y: h * 0.1, width: w * 0.3, height: h * 0.8)), with: .color(lcdInk))
            }
        }
    }
}

/// .battery-indicator: 98×44 box with a 6 px border scaled to 0.3, four segments.
struct BatteryIcon: View {
    let u: CGFloat
    @State private var level: Float = 1

    var body: some View {
        let s = 0.3 * u
        let bars = max(1, min(4, Int(ceil((level < 0 ? 1 : level) * 4))))
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Rectangle().strokeBorder(lcdInk, lineWidth: 6 * s)
                HStack(spacing: 6 * s) {
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(i < bars ? lcdInk : .clear).frame(width: 16 * s)
                    }
                }
                .padding(.leading, 11 * s).padding(.vertical, 11 * s)
            }
            .frame(width: 104 * s, height: 56 * s)
            Rectangle().fill(lcdInk).frame(width: 6 * s, height: 22 * s)
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            level = UIDevice.current.batteryLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            level = UIDevice.current.batteryLevel
        }
    }
}

struct ScreenContent: View {
    let u: CGFloat
    let screen: Navigator.Screen
    var body: some View {
        if screen.spec.isNowPlaying {
            NowPlayingView(u: u)
        } else {
            MenuListView(u: u, screen: screen)
        }
    }
}

// MARK: Menu list

struct MenuListView: View {
    let u: CGFloat
    let screen: Navigator.Screen
    @Environment(Navigator.self) private var nav
    @Environment(\.lcdLit) private var lit

    var body: some View {
        let n = screen.rows.count
        let showBar = n > nav.visibleRows
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if screen.loading {
                    Text("Loading…").font(.chicago(23 * u)).foregroundStyle(lcdInk)
                        .frame(maxWidth: .infinity).padding(.top, 60 * u)
                } else {
                    let end = min(n, screen.top + nav.visibleRows)
                    ForEach(Array(screen.top..<max(screen.top, end)), id: \.self) { i in
                        MenuRowView(u: u, row: screen.rows[i], selected: i == screen.selected && !screen.rows[i].info, lit: lit)
                            .frame(height: 30 * u)
                            .contentShape(Rectangle())
                            .onTapGesture { nav.tapRow(i) }
                    }
                }
                Spacer(minLength: 0)
            }
            if showBar {
                ScrollIndicator(u: u, total: n, top: screen.top, visible: nav.visibleRows)
                    .frame(width: 12 * u)
                    .padding(.bottom, 1 * u)
            }
        }
        .padding(.horizontal, 5 * u)
    }
}

struct MenuRowView: View {
    let u: CGFloat
    let row: Row
    let selected: Bool
    let lit: Bool

    var body: some View {
        // .menu-item.selected: background #484647, text --ipod-faux-backlit #b5c3d8 (or #afaea7 unlit)
        let fg = selected ? (lit ? Color(hex: 0xB5C3D8) : Color(hex: 0xAFAEA7)) : lcdInk
        HStack(spacing: 6 * u) {
            if row.centered {
                Spacer(minLength: 0)
                Text(row.title).font(.chicago(23 * u)).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                MarqueeText(text: row.title, size: 23 * u, active: selected, u: u)
                if let v = row.value {
                    Text(v).font(.chicago(23 * u)).lineLimit(1).layoutPriority(1)
                }
                if row.chevron {
                    Chevron().stroke(fg, style: StrokeStyle(lineWidth: 2.6 * u, lineCap: .square, lineJoin: .miter))
                        .frame(width: 7 * u, height: 13 * u)
                        .padding(.leading, 2 * u)
                }
            }
        }
        .foregroundStyle(fg)
        .padding(.leading, 12 * u).padding(.trailing, 10 * u)
        .padding(.top, 3 * u).padding(.bottom, 1 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selected ? lcdInk : Color.clear)
    }
}

struct Chevron: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

/// The classic scrollbar: 12 px track, 1 px ink border, ink thumb inset 2 px.
struct ScrollIndicator: View {
    let u: CGFloat
    let total: Int, top: Int, visible: Int
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let thumbH = max(8 * u, (h - 4 * u) * CGFloat(visible) / CGFloat(total))
            let maxTop = max(1, total - visible)
            let y = 2 * u + (h - 4 * u - thumbH) * CGFloat(top) / CGFloat(maxTop)
            ZStack(alignment: .top) {
                Rectangle().fill(lcdInk.opacity(0.1))
                Rectangle().strokeBorder(lcdInk, lineWidth: 1 * u)
                Rectangle().fill(lcdInk).frame(width: g.size.width - 4 * u, height: thumbH).offset(y: y)
            }
        }
    }
}

/// .marquee: a selected title that doesn't fit scrolls after 2 s at 0.05 s/px, with a 30 px gap.
struct MarqueeText: View {
    let text: String
    let size: CGFloat
    let active: Bool
    let u: CGFloat
    var centered = false
    @State private var textW: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        GeometryReader { g in
            let overflow = active && textW > g.size.width + 0.5
            ZStack(alignment: centered && !overflow ? .center : .leading) {
                if overflow {
                    TimelineView(.animation) { tl in
                        let dist = textW + 30 * u
                        let t = tl.date.timeIntervalSince(start) - 2
                        let off = t <= 0 ? 0 : (CGFloat(t) / 0.05 * u).truncatingRemainder(dividingBy: dist)
                        HStack(spacing: 30 * u) { label; label }
                            .fixedSize()
                            .offset(x: -off)
                    }
                } else {
                    label.lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: centered && !overflow ? .center : .leading)
            .clipped()
        }
        .frame(height: size * 1.15)
        .background(label.fixedSize().hidden().background(GeometryReader { gg in
            Color.clear.onAppear { textW = gg.size.width }.onChange(of: text) { textW = gg.size.width }
        }))
        .onChange(of: active) { start = Date() }
        .onChange(of: text) { start = Date() }
    }

    private var label: some View { Text(text).font(.chicago(size)) }
}

// MARK: Now Playing

struct NowPlayingView: View {
    let u: CGFloat
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let showArt = settings.albumArt && (player.artwork != nil || player.demoHue != nil)
        VStack(spacing: 0) {
            // .now-playing-index: "1 of 12" + shuffle/repeat modifiers
            HStack {
                Text(player.hasItem ? "\(player.index + 1) of \(max(player.count, 1))" : "")
                    .font(.chicago(18 * u))
                Spacer()
                HStack(spacing: 6 * u) {
                    if settings.shuffle == .songs { Image(systemName: "shuffle").font(.system(size: 12 * u, weight: .heavy)) }
                    if settings.repeatMode != .off {
                        Image(systemName: settings.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 12 * u, weight: .heavy))
                    }
                }
            }
            .padding(.bottom, 6 * u)

            if !player.hasItem {
                Text("No Music").font(.chicago(23 * u)).padding(.top, 30 * u)
            } else if showArt {
                HStack(alignment: .top, spacing: 9 * u) {
                    ArtView(u: u, side: 64 * u)
                    VStack(alignment: .leading, spacing: 2 * u) {
                        MarqueeText(text: player.title, size: 20 * u, active: true, u: u)
                        Text(player.artist).font(.chicago(17 * u)).lineLimit(1)
                        Text(player.album).font(.chicago(17 * u)).lineLimit(1)
                    }
                }
            } else {
                VStack(spacing: 2 * u) {
                    MarqueeText(text: player.title, size: 23 * u, active: true, u: u, centered: true)
                    Text(player.artist).font(.chicago(23 * u)).lineLimit(1)
                    Text(player.album).font(.chicago(23 * u)).lineLimit(1)
                }
                .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            ModePanels(u: u)
        }
        .foregroundStyle(lcdInk)
        .padding(.top, 4 * u).padding(.horizontal, 15 * u).padding(.bottom, 7 * u)
        .frame(height: 180 * u)
    }
}

struct ArtView: View {
    let u: CGFloat
    let side: CGFloat
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Group {
            if let a = player.artwork {
                ArtworkImage(a, width: side, height: side)
            } else if let hue = player.demoHue {
                ZStack {
                    LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.85),
                                            Color(hue: hue + 0.08, saturation: 0.7, brightness: 0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("DEMO").font(.chicago(12 * u)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: side, height: side)
        .overlay(Rectangle().stroke(lcdInk, lineWidth: 1.5 * u))
    }
}

/// .now-playing-progress: a 200%-wide strip; volume/scrubbing slide it left by 50% + 15 px.
struct ModePanels: View {
    let u: CGFloat
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            HStack(alignment: .top, spacing: 30 * u) {
                ProgressPanel(u: u, time: player.time, duration: player.duration, marker: false)
                    .frame(width: w)
                Group {
                    if nav.npMode == .volume {
                        VolumePanel(u: u, volume: Double(player.volume)).padding(.top, 10 * u)
                    } else {
                        ProgressPanel(u: u, time: nav.scrubPreview ?? player.time, duration: player.duration, marker: true)
                    }
                }
                .frame(width: w)
            }
            .offset(x: nav.npMode == .progress ? 0 : -(w + 30 * u))
        }
        .frame(height: 58 * u)
    }
}

struct ProgressPanel: View {
    let u: CGFloat
    let time: TimeInterval
    let duration: TimeInterval
    let marker: Bool

    var body: some View {
        let frac = duration > 0 ? max(0, min(1, time / duration)) : 0
        VStack(spacing: 6 * u) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    if marker {
                        // .progress-marker: 10 px diamond on the bar
                        Rectangle().fill(lcdInk).frame(width: 10 * u, height: 10 * u)
                            .rotationEffect(.degrees(45))
                            .offset(x: g.size.width * frac - 5 * u)
                    } else {
                        Rectangle().fill(lcdInk).frame(width: g.size.width * frac)
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: marker ? 0 : 7 * u))
                .overlay(RoundedRectangle(cornerRadius: 7 * u).stroke(lcdInk, lineWidth: 1.5 * u))
            }
            .frame(height: 15 * u)
            HStack {
                Text(fmt(time)); Spacer(); Text("-" + fmt(max(0, duration - time)))
            }
            .font(.chicago(22 * u))
            .monospacedDigit()
        }
        .padding(.top, 10 * u)
    }

    private func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct VolumePanel: View {
    let u: CGFloat
    let volume: Double
    var body: some View {
        HStack(spacing: 7 * u) {
            Image(systemName: "speaker.fill").font(.system(size: 13 * u, weight: .bold))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(lcdInk).frame(width: g.size.width * max(0, min(1, volume)))
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 7 * u))
                .overlay(RoundedRectangle(cornerRadius: 7 * u).stroke(lcdInk, lineWidth: 1.5 * u))
            }
            .frame(height: 15 * u)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 13 * u, weight: .bold))
        }
    }
}
