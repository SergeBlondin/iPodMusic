import SwiftUI
import MusicKit

/// A floor-model jukebox in the Wurlitzer 1015 / Seeburg / Rock-Ola family:
/// arched crown, walnut and chrome, bubble tubes, a glass window onto the
/// record, title strips, a number keypad, and a cloth speaker grille.
///
/// Albums are selections. Tap a strip (or enter its number) to load that
/// record into the window. Tap the glass, or the same strip again, to flip
/// it and play songs — the same flip the Cover Flow cards use.
struct JukeboxCabinetView: View {
    let albums: [Row]
    @Binding var selectedAlbumID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var centeredAlbumID: UUID?

    var body: some View {
        GeometryReader { geo in
            let inner = CGSize(width: max(0, geo.size.width - 12), height: max(0, geo.size.height - 12))
            let plan = JukeboxPlan(size: inner)
            ZStack {
                JukeboxSilhouette().fill(JukeboxPaint.wood)
                JukeboxSilhouette().fill(JukeboxPaint.varnish)
                WoodGrain()
                JukeboxSilhouette().fill(JukeboxPaint.edgeShade)
                CabinetContents(
                    albums: albums,
                    plan: plan,
                    centeredAlbumID: $centeredAlbumID,
                    selectedAlbumID: $selectedAlbumID,
                    reduceMotion: reduceMotion
                )
            }
            .clipShape(JukeboxSilhouette())
            .overlay { JukeboxSilhouette().stroke(JukeboxPaint.chrome, lineWidth: 5).allowsHitTesting(false) }
            .overlay { JukeboxSilhouette(insetAmount: 7).stroke(JukeboxPaint.gold.opacity(0.75), lineWidth: 1.5).allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.55), radius: 16, y: 8)
            .padding(6)
        }
        .background(
            LinearGradient(colors: [Color(red: 0.08, green: 0.035, blue: 0.02), .black],
                           startPoint: .top, endPoint: .bottom)
        )
        .onAppear {
            // Same starting selection as Cover Flow: the first album, not the middle.
            if centeredAlbumID == nil { centeredAlbumID = albums.first?.id }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Layout

private struct JukeboxPlan {
    let landscape: Bool
    let crest: CGFloat
    let grille: CGFloat
    let controls: CGFloat
    let showKeypad: Bool
    /// Portrait: window height. Landscape: window width.
    let windowBreadth: CGFloat

    init(size: CGSize) {
        let h = max(size.height, 1)
        let w = max(size.width, 1)
        landscape = w > h * 1.05
        showKeypad = !landscape && h >= 500
        let rise = JukeboxMetrics.archRise(width: w, height: h)
        let idealCrest = min(max(rise * 0.62, 28), landscape ? 44 : 74)
        let idealGrille = min(86, max(36, h * (landscape ? 0.13 : 0.11)))
        controls = 44
        let minimumMiddle = min(landscape ? 96 : 140, h * 0.42)
        let budget = max(0, h - controls - minimumMiddle - 8)
        crest = min(idealCrest, max(24, budget * 0.58))
        grille = min(idealGrille, max(28, budget - crest))
        let middle = max(60, h - crest - grille - controls - 8)
        if landscape {
            windowBreadth = min(max(88, middle * 0.92), w * 0.38, 300)
        } else {
            let reserve: CGFloat = showKeypad ? 168 : 88
            windowBreadth = min(w * 0.74, 320, max(110, middle - reserve))
        }
    }
}

private struct CabinetContents: View {
    let albums: [Row]
    let plan: JukeboxPlan
    @Binding var centeredAlbumID: UUID?
    @Binding var selectedAlbumID: UUID?
    let reduceMotion: Bool
    @Environment(Navigator.self) private var nav

    private var currentAlbum: Row? {
        if let id = centeredAlbumID, let row = albums.first(where: { $0.id == id }) { return row }
        return albums.first
    }

    private var flipped: Bool {
        guard let album = currentAlbum else { return false }
        return selectedAlbumID == album.id
    }

    var body: some View {
        VStack(spacing: 4) {
            CrestPlate(compact: plan.landscape)
                .frame(height: plan.crest)
            if plan.landscape {
                HStack(spacing: 6) {
                    Pilaster(compact: true)
                    TitleDeck(albums: albums, centeredID: centeredAlbumID ?? albums.first?.id,
                              flippedID: selectedAlbumID, showKeypad: false,
                              reduceMotion: reduceMotion, load: { album in load(album) })
                    window
                        .frame(width: plan.windowBreadth)
                    Pilaster(compact: true)
                }
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    Pilaster(compact: false)
                    window
                    Pilaster(compact: false)
                }
                .frame(height: plan.windowBreadth)
                TitleDeck(albums: albums, centeredID: centeredAlbumID ?? albums.first?.id,
                          flippedID: selectedAlbumID, showKeypad: plan.showKeypad,
                          reduceMotion: reduceMotion, load: { album in load(album) })
                    .frame(maxHeight: .infinity)
            }
            JukeboxControls(loadedTitle: currentAlbum?.title, flipped: flipped)
                .frame(height: plan.controls)
            SpeakerGrille()
                .frame(height: plan.grille)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var window: some View {
        RecordWindow(album: currentAlbum, flipped: flipped, reduceMotion: reduceMotion, onFlip: {
            guard let album = currentAlbum else { return }
            load(album)
        })
    }

    private func load(_ album: Row) {
        nav.noteActivity()
        // Fall back to the first album so the opening record toggles instead of reloading.
        let active = centeredAlbumID ?? albums.first?.id
        let change = {
            if active == album.id {
                selectedAlbumID = selectedAlbumID == album.id ? nil : album.id
            } else {
                centeredAlbumID = album.id
                selectedAlbumID = nil
            }
        }
        if reduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.45)) { change() } }
    }
}

// MARK: - Crest

private struct CrestPlate: View {
    let compact: Bool
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            Text("◆  MELODY  ◆")
                .font(.system(size: compact ? 16 : 28, weight: .bold, design: .serif))
                .italic()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(JukeboxPaint.goldBright)
                .shadow(color: JukeboxPaint.amber.opacity(0.85), radius: compact ? 3 : 6)
            Text(settings.demoMode ? "DEMO MODE" : "EST. 1946")
                .font(.system(size: compact ? 8 : 10, weight: .semibold, design: .serif))
                .tracking(compact ? 2 : 3)
                .foregroundStyle(settings.demoMode ? JukeboxPaint.amber : JukeboxPaint.gold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(settings.demoMode ? "Melody jukebox, demo mode" : "Melody jukebox")
    }
}

// MARK: - Bubble tubes

private struct Pilaster: View {
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: compact ? 2 : 3) {
                BubbleTube(tint: JukeboxPaint.amber, time: t, phase: 0.4,
                           glow: reduceMotion ? 0.65 : 0.45 + 0.5 * (0.5 + 0.5 * sin(t * 2.0)),
                           animated: !reduceMotion)
                BubbleTube(tint: JukeboxPaint.neonRed, time: t, phase: 1.7,
                           glow: reduceMotion ? 0.6 : 0.35 + 0.5 * (0.5 + 0.5 * sin(t * 2.0 + 1.3)),
                           animated: !reduceMotion)
            }
        }
        .frame(width: compact ? 20 : 28)
        .accessibilityHidden(true)
    }
}

private struct BubbleTube: View {
    let tint: Color
    let time: TimeInterval
    let phase: Double
    let glow: Double
    let animated: Bool

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(JukeboxPaint.chrome).frame(height: 4)
            ZStack {
                LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.95), Color.white.opacity(0.55), tint.opacity(0.8)],
                               startPoint: .leading, endPoint: .trailing)
                bubbles
            }
            .clipShape(Capsule())
            .padding(.vertical, 1)
            RoundedRectangle(cornerRadius: 1).fill(JukeboxPaint.chrome).frame(height: 4)
        }
        .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 0.75))
        .shadow(color: tint.opacity(glow), radius: 7)
    }

    private var bubbles: some View {
        Canvas { ctx, size in
            let count = 8
            for i in 0..<count {
                let seed = phase + Double(i) * 0.73
                let loop = 2.6 + Double(i % 3) * 0.55
                let progress: Double
                let wobble: CGFloat
                if animated {
                    progress = (time / loop + seed).truncatingRemainder(dividingBy: 1)
                    wobble = CGFloat(sin(time * 2.2 + seed)) * size.width * 0.14
                } else {
                    progress = 0.18 + 0.08 * Double(i)
                    wobble = 0
                }
                let radius = size.width * CGFloat(0.10 + 0.07 * Double(i % 3) / 2) * CGFloat(0.65 + 0.5 * progress)
                let x = size.width * 0.5 + wobble
                let y = size.height * CGFloat(1 - progress)
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.28 + 0.45 * (1 - progress))))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Glass window and record

private struct RecordWindow: View {
    let album: Row?
    let flipped: Bool
    let reduceMotion: Bool
    let onFlip: () -> Void
    @Environment(PlayerModel.self) private var player

    var body: some View {
        ZStack {
            GlassArch().fill(
                LinearGradient(colors: [Color(red: 0.16, green: 0.07, blue: 0.04), Color(red: 0.04, green: 0.015, blue: 0.01)],
                               startPoint: .top, endPoint: .bottom)
            )
            MechanismRails()
            if let album {
                ZStack {
                    front(album)
                        .modifier(AlbumFlipFace(angle: flipped ? 180 : 0, isBack: false))
                        .allowsHitTesting(!flipped)
                        .accessibilityHidden(flipped)
                    CoverFlowSongsView(album: album, isActive: flipped, flipBack: onFlip)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.94, green: 0.92, blue: 0.86), in: RoundedRectangle(cornerRadius: 8))
                        .padding(6)
                        .modifier(AlbumFlipFace(angle: flipped ? 180 : 0, isBack: true))
                        .allowsHitTesting(flipped)
                        .accessibilityHidden(!flipped)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: flipped)
            }
            GlassArch()
                .fill(LinearGradient(colors: [.white.opacity(flipped ? 0.05 : 0.22), .clear, .white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(GlassArch())
        .overlay { GlassArch().stroke(JukeboxPaint.chrome, lineWidth: 3).allowsHitTesting(false) }
        .overlay { GlassArch(insetAmount: 4).stroke(JukeboxPaint.gold.opacity(0.8), lineWidth: 1).allowsHitTesting(false) }
        .padding(.vertical, 2)
    }

    private func front(_ album: Row) -> some View {
        GeometryReader { geo in
            let record = min(geo.size.width, geo.size.height) * 0.62
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [JukeboxPaint.amber.opacity(player.isPlaying ? 0.55 : 0.25), .clear],
                                             center: .center, startRadius: 4, endRadius: record * 0.7))
                        .frame(width: record * 1.15, height: record * 1.15)
                    SpinningRecord(album: album, diameter: record,
                                   spinning: player.isPlaying && !flipped && !reduceMotion)
                    Tonearm(engaged: player.isPlaying)
                        .frame(width: record * 1.25, height: record * 1.25)
                }
                .frame(height: record * 1.05)
                Text(album.title)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundStyle(JukeboxPaint.goldBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                Text("TAP THE GLASS FOR SONGS")
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .tracking(0.6)
                    .foregroundStyle(JukeboxPaint.amber.opacity(0.9))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .contentShape(GlassArch())
        .onTapGesture(perform: onFlip)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onFlip)
        .accessibilityLabel("\(album.title), record")
        .accessibilityHint("Shows the songs on this album")
    }
}

private struct SpinningRecord: View {
    let album: Row
    let diameter: CGFloat
    let spinning: Bool

    var body: some View {
        Group {
            if spinning {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
                    // 33⅓ RPM, so the platter turns like a real record.
                    disc(angle: ctx.date.timeIntervalSinceReferenceDate * 198)
                }
            } else {
                disc(angle: 0)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func disc(angle: Double) -> some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [
                    Color(white: 0.02), Color(white: 0.18), Color(white: 0.03),
                    Color(white: 0.12), Color(white: 0.02), Color(white: 0.2), Color(white: 0.02)
                ], center: .center))
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
                    .padding(diameter * (0.07 + CGFloat(i) * 0.045))
            }
            RecordLabel(album: album, diameter: diameter * 0.42)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.75), Color(white: 0.25)], center: .center, startRadius: 0, endRadius: diameter * 0.03))
                .frame(width: max(4, diameter * 0.045), height: max(4, diameter * 0.045))
        }
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
    }
}

private struct RecordLabel: View {
    let album: Row
    let diameter: CGFloat

    var body: some View {
        let colors = JukeboxPaint.label(for: album.title)
        return ZStack {
            if case .push(.album(let musicAlbum)) = album.action, let artwork = musicAlbum.artwork {
                ArtworkImage(artwork, width: diameter, height: diameter)
            } else {
                ZStack {
                    Circle().fill(colors.0)
                    VStack(spacing: 1) {
                        Text("MELODY")
                            .font(.system(size: max(6, diameter * 0.09), weight: .bold, design: .serif))
                            .tracking(1)
                        Text(album.title)
                            .font(.system(size: max(8, diameter * 0.13), weight: .bold, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 4)
                    }
                    .foregroundStyle(colors.2)
                    .padding(diameter * 0.08)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(JukeboxPaint.gold, lineWidth: max(1.5, diameter * 0.035)))
        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1).padding(max(2, diameter * 0.06)))
    }
}

private struct MechanismRails: View {
    var body: some View {
        VStack(spacing: 9) {
            ForEach(0..<5, id: \.self) { _ in
                Capsule()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.18), Color.white.opacity(0.04)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct Tonearm: View {
    let engaged: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pivot = CGPoint(x: w * 0.84, y: h * 0.70)
            let tip = engaged
                ? CGPoint(x: w * 0.58, y: h * 0.46)
                : CGPoint(x: w * 0.78, y: h * 0.28)
            ZStack {
                Path { path in
                    path.move(to: pivot)
                    path.addLine(to: tip)
                }
                .stroke(JukeboxPaint.chrome, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                Circle()
                    .fill(JukeboxPaint.chrome)
                    .frame(width: 10, height: 10)
                    .position(pivot)
                Circle()
                    .fill(Color(white: 0.15))
                    .frame(width: 5, height: 5)
                    .position(tip)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Title strips and keypad

private struct TitleDeck: View {
    let albums: [Row]
    let centeredID: UUID?
    let flippedID: UUID?
    let showKeypad: Bool
    let reduceMotion: Bool
    let load: (Row) -> Void

    var body: some View {
        VStack(spacing: 5) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                            TitleStrip(code: JukeboxMetrics.code(index, count: albums.count),
                                       title: album.title,
                                       loaded: centeredID == album.id,
                                       open: flippedID == album.id) {
                                load(album)
                            }
                            .id(album.id)
                        }
                    }
                    .padding(5)
                }
                .scrollIndicators(.hidden)
                .background(Color(red: 0.05, green: 0.025, blue: 0.015), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(JukeboxPaint.chrome, lineWidth: 2).allowsHitTesting(false) }
                .onAppear { scroll(proxy, to: centeredID) }
                .onChange(of: centeredID) { _, id in scroll(proxy, to: id) }
            }
            if showKeypad {
                SelectionKeypad(count: albums.count, currentNumber: currentNumber) { index in
                    guard albums.indices.contains(index) else { return }
                    load(albums[index])
                }
            }
        }
    }

    private var currentNumber: Int {
        guard let id = centeredID, let index = albums.firstIndex(where: { $0.id == id }) else { return 1 }
        return index + 1
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: UUID?) {
        guard let id else { return }
        if reduceMotion {
            proxy.scrollTo(id, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

private struct TitleStrip: View {
    let code: String
    let title: String
    let loaded: Bool
    let open: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(code)
                    .font(.system(size: 11, weight: .black, design: .serif))
                    .foregroundStyle(JukeboxPaint.cream)
                    .frame(width: 32, height: 26)
                    .background(loaded ? JukeboxPaint.neonRed : Color(red: 0.42, green: 0.08, blue: 0.08), in: RoundedRectangle(cornerRadius: 2))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.48, green: 0.07, blue: 0.08))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().fill(JukeboxPaint.chrome).frame(width: 16, height: 16)
                    Circle()
                        .fill(loaded ? (open ? JukeboxPaint.amber : JukeboxPaint.neonRed) : Color(white: 0.35))
                        .frame(width: 8, height: 8)
                }
                .shadow(color: loaded ? JukeboxPaint.amber.opacity(0.8) : .clear, radius: 3)
            }
            .padding(.horizontal, 5)
            .frame(minHeight: 44)
            .background(loaded ? Color(red: 1, green: 0.96, blue: 0.82) : JukeboxPaint.cream, in: RoundedRectangle(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(loaded ? JukeboxPaint.gold : JukeboxPaint.goldDeep.opacity(0.7), lineWidth: loaded ? 1.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(code), \(title)")
        .accessibilityHint(loaded ? (open ? "Hides the songs" : "Shows the songs") : "Loads this album into the window")
        .accessibilityAddTraits(loaded ? .isSelected : AccessibilityTraits())
    }
}

private struct SelectionKeypad: View {
    let count: Int
    let currentNumber: Int
    let onSelect: (Int) -> Void
    @State private var entry = ""
    @State private var note: String?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.isEmpty ? restingNumber : entry)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.isEmpty ? JukeboxPaint.amber.opacity(0.55) : JukeboxPaint.amber)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(JukeboxPaint.goldDeep, lineWidth: 1) }
                    .accessibilityLabel("Selection \(entry.isEmpty ? restingNumber : entry)")
                ChromeKey(title: "C", accessibility: "Clear", width: 36) {
                    entry = ""
                    note = nil
                }
                ChromeKey(title: "GO", accessibility: "Select title", width: 44, prominent: true) { commit() }
            }
            .frame(height: 38)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                ForEach(1...9, id: \.self) { digit in
                    ChromeKey(title: "\(digit)", accessibility: "Number \(digit)") { press(digit) }
                }
                ChromeKey(title: "0", accessibility: "Number 0") { press(0) }
            }
            Text(note ?? "NUMBER, THEN GO")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .tracking(1)
                .foregroundStyle(note == nil ? JukeboxPaint.gold.opacity(0.85) : JukeboxPaint.amber)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }

    private var restingNumber: String {
        guard currentNumber > 0 else { return "--" }
        if count >= 100 { return String(format: "%03d", currentNumber) }
        return String(format: "%02d", currentNumber)
    }

    private func press(_ digit: Int) {
        if entry.isEmpty && digit == 0 { return }
        var next = entry + "\(digit)"
        if next.count > 4 { next = "\(digit)" }
        guard let value = Int(next) else { return }
        if value > count {
            note = "No title \(next)"
            entry = ""
            return
        }
        entry = next
        note = nil
        // Commit when another digit could not name a real selection (3 on a 4-album machine).
        if value >= 1, value * 10 > count {
            entry = ""
            onSelect(value - 1)
        }
    }

    private func commit() {
        guard let value = Int(entry), (1...count).contains(value) else {
            note = entry.isEmpty ? "Enter a number" : "No title \(entry)"
            entry = ""
            return
        }
        entry = ""
        note = nil
        onSelect(value - 1)
    }
}

private struct ChromeKey: View {
    let title: String
    var accessibility: String
    var width: CGFloat = 36
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(prominent ? JukeboxPaint.goKey : JukeboxPaint.chrome)
                    .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                Circle().stroke(Color.white.opacity(0.65), lineWidth: 1).padding(1)
                Text(title)
                    .font(.system(size: title.count > 1 ? 11 : 15, weight: .black, design: .serif))
                    .foregroundStyle(prominent ? Color.white : Color(red: 0.22, green: 0.11, blue: 0.05))
            }
            .frame(width: width, height: 36)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

// MARK: - Controls and grille

private struct JukeboxControls: View {
    let loadedTitle: String?
    let flipped: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button {
                nav.noteActivity()
                if reduceMotion {
                    settings.jukeboxStyle = false
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { settings.jukeboxStyle = false }
                }
            } label: {
                Text("iPod")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.22, green: 0.1, blue: 0.04))
                    .frame(minWidth: 48, minHeight: 36)
                    .background(JukeboxPaint.chrome, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the iPod")

            HStack(spacing: 6) {
                Circle()
                    .fill(player.isPlaying ? JukeboxPaint.neonRed : Color(white: 0.28))
                    .frame(width: 8, height: 8)
                    .shadow(color: player.isPlaying ? JukeboxPaint.neonRed : .clear, radius: 4)
                Text(plaque)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.42, green: 0.06, blue: 0.07))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(JukeboxPaint.cream, in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(JukeboxPaint.goldDeep, lineWidth: 1) }

            Button {
                player.togglePlay()
            } label: {
                ZStack {
                    Circle().fill(JukeboxPaint.chrome)
                    Circle().fill(player.isPlaying ? Color(red: 0.42, green: 0.05, blue: 0.06) : JukeboxPaint.neonRed)
                        .padding(3)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!player.hasItem)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
    }

    private var plaque: String {
        if player.hasItem {
            return (player.isPlaying ? "NOW PLAYING  " : "PAUSED  ") + player.title
        }
        if flipped { return "CHOOSE A SONG" }
        if let loadedTitle { return "LOADED  " + loadedTitle }
        return "MAKE A SELECTION"
    }
}

private struct SpeakerGrille: View {
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.52, green: 0.15, blue: 0.11),
                            Color(red: 0.30, green: 0.07, blue: 0.06),
                            Color(red: 0.46, green: 0.13, blue: 0.09)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                let step: CGFloat = 8
                var row = 0
                var y: CGFloat = 4
                while y < size.height - 4 {
                    var x: CGFloat = row.isMultiple(of: 2) ? 4 : 4 + step / 2
                    while x < size.width - 4 {
                        let hole = CGRect(x: x, y: y, width: 4.2, height: 4.2)
                        ctx.fill(Path(ellipseIn: hole), with: .color(.black.opacity(0.55)))
                        let glint = CGRect(x: x + 0.4, y: y + 0.3, width: 1.6, height: 1.6)
                        ctx.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.14)))
                        x += step
                    }
                    y += step * 0.86
                    row += 1
                }
            }
            Diamond()
                .stroke(JukeboxPaint.gold, lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .shadow(color: JukeboxPaint.gold.opacity(0.9), radius: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(JukeboxPaint.chrome, lineWidth: 2) }
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes and paint

private struct JukeboxSilhouette: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 4, r.height > 4 else { return Path() }
        let rise = JukeboxMetrics.archRise(width: r.width, height: r.height)
        let shoulderY = r.minY + rise
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 12, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - 12, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 1, y: r.maxY - 16),
                       control: CGPoint(x: r.maxX - 1, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - 1, y: shoulderY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.maxX - 1, y: r.minY + rise * 0.08),
                   control2: CGPoint(x: r.midX + r.width * 0.30, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + 1, y: shoulderY),
                   control1: CGPoint(x: r.midX - r.width * 0.30, y: r.minY),
                   control2: CGPoint(x: r.minX + 1, y: r.minY + rise * 0.08))
        p.addLine(to: CGPoint(x: r.minX + 1, y: r.maxY - 16))
        p.addQuadCurve(to: CGPoint(x: r.minX + 12, y: r.maxY),
                       control: CGPoint(x: r.minX + 1, y: r.maxY))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> JukeboxSilhouette {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct GlassArch: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 2, r.height > 2 else { return Path() }
        let rise = min(r.width * 0.52, r.height * 0.46)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + rise))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + rise), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> GlassArch {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct WoodGrain: View {
    var body: some View {
        Canvas { ctx, size in
            let bands: [CGFloat] = [0.07, 0.16, 0.24, 0.38, 0.51, 0.63, 0.74, 0.86, 0.93]
            for (i, band) in bands.enumerated() {
                var path = Path()
                let x = size.width * band
                path.move(to: CGPoint(x: x, y: 0))
                path.addCurve(to: CGPoint(x: x + size.width * 0.018, y: size.height),
                              control1: CGPoint(x: x - 6, y: size.height * 0.35),
                              control2: CGPoint(x: x + 8, y: size.height * 0.68))
                ctx.stroke(path, with: .color(.black.opacity(i.isMultiple(of: 2) ? 0.14 : 0.07)),
                           lineWidth: i.isMultiple(of: 3) ? 2.5 : 1.2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum JukeboxMetrics {
    static func archRise(width: CGFloat, height: CGFloat) -> CGFloat {
        let cap = max(20, height * 0.42)
        let tall = height > width * 0.9
        let raw = tall
            ? min(width * 0.46, height * 0.20)
            : min(max(26, height * 0.18), width * 0.16, 60)
        return min(raw, cap)
    }

    static func code(_ index: Int, count: Int) -> String {
        let number = index + 1
        if count >= 100 { return String(format: "%03d", number) }
        if count >= 10 { return String(format: "%02d", number) }
        return "\(number)"
    }
}

private enum JukeboxPaint {
    static let gold = Color(red: 0.83, green: 0.64, blue: 0.28)
    static let goldBright = LinearGradient(
        colors: [Color(red: 1, green: 0.95, blue: 0.72), Color(red: 0.86, green: 0.66, blue: 0.28), Color(red: 0.55, green: 0.36, blue: 0.10)],
        startPoint: .top, endPoint: .bottom)
    static let goldDeep = Color(red: 0.52, green: 0.36, blue: 0.12)
    static let amber = Color(red: 1, green: 0.64, blue: 0.16)
    static let neonRed = Color(red: 0.86, green: 0.07, blue: 0.10)
    static let cream = Color(red: 0.97, green: 0.92, blue: 0.78)
    static let wood = LinearGradient(
        colors: [
            Color(red: 0.55, green: 0.30, blue: 0.12),
            Color(red: 0.38, green: 0.18, blue: 0.07),
            Color(red: 0.50, green: 0.26, blue: 0.10),
            Color(red: 0.22, green: 0.10, blue: 0.04)
        ],
        startPoint: .top, endPoint: .bottom)
    static let varnish = LinearGradient(
        colors: [.white.opacity(0.16), .clear, .black.opacity(0.18)],
        startPoint: .top, endPoint: .center)
    static let edgeShade = LinearGradient(
        colors: [.black.opacity(0.38), .clear, .clear, .black.opacity(0.38)],
        startPoint: .leading, endPoint: .trailing)
    static let chrome = LinearGradient(
        colors: [Color(white: 0.28), Color(white: 0.92), Color(white: 1), Color(white: 0.55), Color(white: 0.88), Color(white: 0.32)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goKey = LinearGradient(
        colors: [Color(red: 0.95, green: 0.25, blue: 0.18), Color(red: 0.62, green: 0.05, blue: 0.07)],
        startPoint: .top, endPoint: .bottom)

    /// Background, unused ring, ink. Stable for a given album title.
    static func label(for title: String) -> (Color, Color, Color) {
        let palettes: [(Color, Color, Color)] = [
            (Color(red: 0.70, green: 0.10, blue: 0.12), .clear, Color(red: 0.98, green: 0.93, blue: 0.78)),
            (Color(red: 0.96, green: 0.90, blue: 0.70), .clear, Color(red: 0.40, green: 0.08, blue: 0.08)),
            (Color(red: 0.10, green: 0.20, blue: 0.36), .clear, Color(red: 0.96, green: 0.90, blue: 0.72)),
            (Color(red: 0.16, green: 0.32, blue: 0.20), .clear, Color(red: 0.97, green: 0.93, blue: 0.78)),
            (Color(red: 0.45, green: 0.22, blue: 0.08), .clear, Color(red: 1, green: 0.95, blue: 0.84))
        ]
        var hash = 0
        for scalar in title.unicodeScalars { hash = hash &* 31 &+ Int(scalar.value) }
        let count = palettes.count
        let index = hash % count
        return palettes[index < 0 ? index + count : index]
    }
}
