import SwiftUI
import QuartzCore

/// The 1st-generation click wheel: a 350 px outer ring holding the four buttons,
/// a 276 px touch-sensitive scroll disc, and a separate 100 px select button.
struct ClickWheelView: View {
    let u: CGFloat
    @Environment(Navigator.self) private var nav
    @Environment(AppSettings.self) private var settings
    @State private var tracker = WheelTracker()

    var body: some View {
        let p = ThemePalette.of(settings.theme)
        let D = 350 * u, Dd = 276 * u, Dc = 100 * u
        ZStack {
            // .click-wheel: #f8f8f8 with layered inset shadows
            Circle().fill(p.wheel)
            // inset 8px -7px 34px -15px rgba(137,137,137,.8): soft grey inner edge, strongest bottom-left
            Circle().strokeBorder(Color(hex: 0x898989, alpha: 0.55), lineWidth: 10 * u)
                .blur(radius: 9 * u).offset(x: -4 * u, y: 4 * u).mask(Circle())
            // inset -16px 29px 11px 15px #f4f4f4: bright top
            Circle().fill(RadialGradient(colors: [Color.white.opacity(settings.theme == .white ? 0.7 : 0.05), .clear],
                                         center: UnitPoint(x: 0.45, y: 0.15), startRadius: 0, endRadius: D * 0.45))
            Circle().stroke(Color(hex: 0x878787, alpha: 0.38), lineWidth: 2 * u)
            Circle().stroke(Color(hex: 0xA8A8A8, alpha: 0.67), lineWidth: 1 * u).padding(-2 * u).blur(radius: 0.5 * u)
            // ::after conic highlight, blurred 12 px
            Circle()
                .strokeBorder(AngularGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .clear, location: 0.16),
                    .init(color: .white, location: 0.22), .init(color: .clear, location: 0.30),
                    .init(color: .clear, location: 0.67), .init(color: .white, location: 0.72),
                    .init(color: .clear, location: 0.80), .init(color: .clear, location: 1)],
                    center: .center, angle: .degrees(345 - 90)), lineWidth: 8 * u)
                .padding(16 * u)
                .blur(radius: 12 * u)
                .opacity(settings.theme == .white ? 1 : 0.3)
                .allowsHitTesting(false)

            // .wheel-dividers: two 2 px lines at 45° and 135°
            ZStack {
                ForEach([45.0, 135.0], id: \.self) { a in
                    Rectangle().fill(p.divider).frame(width: 2 * u, height: D).rotationEffect(.degrees(a))
                }
            }
            .frame(width: D, height: D)
            .mask(Circle())

            // Button labels
            WheelLabels(u: u, p: p, pressed: nav.pressed)

            // .scroll-wheel (276 px)
            Circle()
                .fill(RadialGradient(colors: [p.disc1, p.disc2], center: UnitPoint(x: 1.3, y: -1.0),
                                     startRadius: 0, endRadius: Dd * 1.9))
                .overlay(Circle().strokeBorder(Color(white: 0.98, opacity: 0.27), lineWidth: 2 * u).padding(2 * u))
                .overlay(Circle().strokeBorder(p.discRim, lineWidth: 2 * u))
                .shadow(color: Color(hex: 0x7A7A7A, alpha: 0.45), radius: 7 * u, x: 4 * u, y: -5 * u)
                .shadow(color: Color(hex: 0xA8A8A8, alpha: 0.67), radius: 2 * u, x: 0, y: -1 * u)
                .frame(width: Dd, height: Dd)

            // .select-button (100 px), pressed: scale(0.98) + 1 px shadow ring
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.09, opacity: 0.19), p.center.opacity(0.93)],
                                     center: UnitPoint(x: -0.09, y: 2.09), startRadius: 0, endRadius: Dc * 1.6))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.2), .white.opacity(0.2), .clear],
                                                      center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: Dc * 0.5)))
                .overlay(Circle().strokeBorder(p.centerRim, lineWidth: 2 * u))
                .shadow(color: nav.centerPressed ? Color(hex: 0x909090) : .clear, radius: 1 * u)
                .rotationEffect(.degrees(35))
                .scaleEffect(nav.centerPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.1), value: nav.centerPressed)
                .frame(width: Dc, height: Dc)
        }
        .frame(width: D, height: D)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in tracker.changed(v, diameter: D, u: u, nav: nav) }
                .onEnded { _ in tracker.ended(nav: nav) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Click wheel")
    }
}

private struct WheelLabels: View {
    let u: CGFloat
    let p: ThemePalette
    let pressed: WheelSegment?

    var body: some View {
        ZStack {
            VStack {
                Text("menu")
                    .font(.system(size: 19 * u, weight: .bold, design: .default))
                    .foregroundStyle(p.wheelLabel)
                    .scaleEffect(pressed == .menu ? 0.97 : 1)
                    .padding(.top, 9.5 * u)
                Spacer()
                WheelIcon(kind: .playPause).fill(p.wheelIcon)
                    .frame(width: 25 * u, height: 11 * u)
                    .scaleEffect(pressed == .playPause ? 0.97 : 1)
                    .padding(.bottom, 16 * u)
            }
            HStack {
                WheelIcon(kind: .back).fill(p.wheelIcon)
                    .frame(width: 25 * u, height: 11 * u)
                    .scaleEffect(pressed == .back ? 0.97 : 1)
                    .padding(.leading, 12 * u)
                Spacer()
                WheelIcon(kind: .forward).fill(p.wheelIcon)
                    .frame(width: 25 * u, height: 11 * u)
                    .scaleEffect(pressed == .forward ? 0.97 : 1)
                    .padding(.trailing, 12 * u)
            }
        }
        .allowsHitTesting(false)
    }
}

struct WheelIcon: Shape {
    enum Kind { case back, forward, playPause }
    let kind: Kind

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        func tri(_ x0: CGFloat, _ x1: CGFloat) {   // points toward x1
            p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x1, y: y + h / 2))
            p.addLine(to: CGPoint(x: x0, y: y + h)); p.closeSubpath()
        }
        switch kind {
        case .forward:
            tri(x, x + w * 0.42); tri(x + w * 0.42, x + w * 0.84)
            p.addRect(CGRect(x: x + w * 0.86, y: y, width: w * 0.14, height: h))
        case .back:
            p.addRect(CGRect(x: x, y: y, width: w * 0.14, height: h))
            tri(x + w * 0.58, x + w * 0.16); tri(x + w, x + w * 0.58)
        case .playPause:
            tri(x, x + w * 0.45)
            p.addRect(CGRect(x: x + w * 0.58, y: y, width: w * 0.14, height: h))
            p.addRect(CGRect(x: x + w * 0.84, y: y, width: w * 0.14, height: h))
        }
        return p
    }
}

/// Port of the web iPod's pointer handler (Yh): angle deltas between successive
/// pointer samples, a 10%-radius dead zone, 8° reversal hysteresis, and speed in °/s.
@MainActor
final class WheelTracker {
    private enum Mode { case idle, ignored, center, ring(WheelSegment, CGPoint), scroll }
    private var mode: Mode = .idle
    private var last: CGPoint?
    private var lastT: TimeInterval = 0
    private var dir: Int? = nil
    private var hysteresis = 0.0

    func changed(_ v: DragGesture.Value, diameter D: CGFloat, u: CGFloat, nav: Navigator) {
        let off = CGPoint(x: v.location.x - D / 2, y: v.location.y - D / 2)
        let t = v.time.timeIntervalSinceReferenceDate
        switch mode {
        case .idle:
            let r = hypot(off.x, off.y) / (D / 2)
            if r < WheelTuning.selectButtonRatio {
                mode = .center; nav.centerDown()
            } else if r <= WheelTuning.scrollWheelRatio {
                beginScroll(off, t, nav)
            } else if r <= 1.03 {
                let seg = segment(for: off)
                mode = .ring(seg, off); nav.segmentDown(seg)
            } else {
                mode = .ignored
            }
        case .ring(_, let start):
            // A button press that starts travelling around the wheel becomes a scroll.
            if hypot(off.x - start.x, off.y - start.y) > 12 * u {
                nav.segmentCancel()
                beginScroll(off, t, nav)
            }
        case .scroll:
            move(off, t, radius: D / 2 * WheelTuning.scrollWheelRatio, nav: nav)
        case .center, .ignored:
            break
        }
    }

    func ended(nav: Navigator) {
        switch mode {
        case .center: nav.centerUp()
        case .ring(let seg, _): nav.segmentUp(seg)
        case .scroll: nav.wheelEnded()
        default: break
        }
        mode = .idle; last = nil; dir = nil; hysteresis = 0
    }

    private func beginScroll(_ off: CGPoint, _ t: TimeInterval, _ nav: Navigator) {
        mode = .scroll; last = off; lastT = t; dir = nil; hysteresis = 0
        nav.wheelBegan()
    }

    private func segment(for off: CGPoint) -> WheelSegment {
        let a = atan2(off.y, off.x) * 180 / .pi   // screen coords: 0 = right, 90 = down
        if a > -135 && a <= -45 { return .menu }
        if a > -45 && a <= 45 { return .forward }
        if a > 45 && a <= 135 { return .playPause }
        return .back
    }

    private func move(_ f: CGPoint, _ t: TimeInterval, radius: CGFloat, nav: Navigator) {
        guard let y = last else { last = f; lastT = t; return }
        let dtMs = (t - lastT) * 1000
        last = f; lastT = t
        let M = radius * WheelTuning.deadZoneRatio
        if Self.segmentDistanceSquared(y, f) < M * M { return }   // Gh(): path crosses the centre
        let E = Self.angleDelta(Self.angle(y), Self.angle(f))     // Uh()
        if E == 0 { return }
        let I = E > 0 ? 1 : -1
        let x = abs(E)
        if dir == nil || I == dir {
            dir = I; hysteresis = 0
        } else {
            hysteresis += x
            if hysteresis < WheelTuning.reversalHysteresis { return }
            dir = I; hysteresis = 0
        }
        let speed = dtMs > 0 ? x / dtMs * 1000 : 0               // Za()
        nav.wheelScroll(step: dir!, degrees: x, speed: speed)
    }

    static func angle(_ p: CGPoint) -> Double { atan2(Double(p.y), Double(p.x)) * 180 / .pi }
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        ((((b - a).truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360)) - 180
    }
    static func segmentDistanceSquared(_ e: CGPoint, _ t: CGPoint) -> CGFloat {
        let i = t.x - e.x, l = t.y - e.y
        let a = i * i + l * l
        let n = a == 0 ? 0 : min(1, max(0, -(e.x * i + e.y * l) / a))
        let o = e.x + n * i, p = e.y + n * l
        return o * o + p * p
    }
}
