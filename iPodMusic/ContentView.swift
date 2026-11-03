import SwiftUI
import MusicKit

/// The whole device, laid out in the web iPod's CSS pixel units (415 × 692 body)
/// and scaled by `u` to fit the phone.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player
    @State private var searchText = ""

    var body: some View {
        @Bindable var nav = nav
        let p = ThemePalette.of(settings.theme)
        GeometryReader { g in
            let u = max(0.5, min((g.size.width - 24) / 415, (g.size.height - 56) / 700, 1.2))
            ZStack {
                p.background.ignoresSafeArea()
                if g.size.width > g.size.height {
                    HStack(spacing: 0) {
                        LandscapeCoverFlowView()
                        if player.remoteKind == .youtubeMusic {
                            YouTubePlayerView(player: player.hub.youtube.player)
                                .frame(width: 200, height: 200)
                                .onAppear { player.hub.youtube.player.setVisible(true) }
                                .onDisappear { player.hub.youtube.player.setVisible(false) }
                        }
                    }
                    .background(Color.black.ignoresSafeArea())
                } else {
                    VStack(spacing: 10 * u) {
                        if settings.demoMode {
                            Text("DEMO MODE · sample songs, not your Apple Music")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                        }
                        IPodBody(u: u)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(HiddenVolumeView().frame(width: 1, height: 1))
        .sheet(item: $nav.setupSheet, onDismiss: { nav.setupClosed() }) { kind in
            SourceSetupView(kind: kind)
                .environment(settings)
                .environment(nav)
        }
        .alert("Search \(settings.demoMode ? "Apple Music" : settings.source.label)", isPresented: $nav.showSearch) {
            TextField("Artists, songs, albums", text: $searchText)
            Button("Search") { nav.submitSearch(searchText) }
            Button("Cancel", role: .cancel) {}
        }
    }
}


private struct LandscapeCoverFlowView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player
    @State private var albums: [Row] = []
    @State private var loading = true
    @State private var message: String?
    @State private var selectedAlbumID: UUID?
    @State private var centeredAlbumID: UUID?

    var body: some View {
        GeometryReader { geometry in
            let side = max(80, min(280, (geometry.size.height - 140) / 1.24))
            VStack(spacing: 12) {
                HStack {
                    Text(settings.jukeboxStyle ? (settings.demoMode ? "Jukebox · Demo" : "Jukebox") : (settings.demoMode ? "Cover Flow · Demo" : "Cover Flow"))
                        .font(.headline)
                    Spacer()
                    Button {
                        player.togglePlay()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    .disabled(!player.hasItem)
                }
                .padding(.horizontal, 24)
                if loading {
                    ProgressView("Loading albums…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if albums.isEmpty {
                    Text(message ?? "No albums. Add music to your library, or enable Demo Mode in Settings.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else if settings.jukeboxStyle {
                    JukeboxCabinetView(albums: albums, selectedAlbumID: $selectedAlbumID)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 20) {
                            ForEach(albums) { album in
                                FlippingAlbumCard(
                                    album: album,
                                    side: side,
                                    isFlipped: selectedAlbumID == album.id,
                                    flip: {
                                        nav.noteActivity()
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            centeredAlbumID = album.id
                                            selectedAlbumID = selectedAlbumID == album.id ? nil : album.id
                                        }
                                    }
                                )
                                .id(album.id)
                                .visualEffect { content, proxy in
                                    let distance = (proxy.frame(in: .named("coverFlowViewport")).midX - geometry.size.width / 2) / (side + 20)
                                    return content
                                        .scaleEffect(1 - min(abs(distance), 1) * 0.2)
                                        .rotation3DEffect(.degrees(max(-1, min(1, distance)) * -50),
                                                          axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .safeAreaPadding(.horizontal, max(0, (geometry.size.width - side) / 2))
                    .coordinateSpace(name: "coverFlowViewport")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: $centeredAlbumID, anchor: .center)
                    Text(message ?? "Swipe to browse · Tap an album to see songs")
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
        .task {
            do {
                if let provider = nav.remoteLibrary {
                    let rows = try await provider.rows(for: .albums)
                    albums = rows.filter {
                        if case .push = $0.action { return true }
                        return false
                    }
                    if albums.isEmpty, !rows.isEmpty {
                        message = rows.map(\.title).joined(separator: " ")
                    }
                } else if settings.demoMode || MusicAuthorization.currentStatus == .authorized {
                    albums = try await nav.library.rows(for: .albums, demo: settings.demoMode)
                } else {
                    message = "Allow Apple Music access in portrait mode to browse your albums."
                }
            } catch {
                message = error.localizedDescription
            }
            centeredAlbumID = albums.first?.id
            loading = false
        }
    }


}




private struct JukeboxCabinetView: View {
    let albums: [Row]
    @Binding var selectedAlbumID: UUID?
    @Environment(Navigator.self) private var nav
    @State private var centeredAlbumID: UUID?

    private let chrome = LinearGradient(
        colors: [.black, Color(white: 0.7), .white, Color(white: 0.25), .black],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        GeometryReader { geometry in
            let side = max(64, min(250, geometry.size.height - 196))
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Image(systemName: "music.note")
                    Text("JUKEBOX")
                        .font(.system(.title3, design: .serif, weight: .black))
                        .tracking(6)
                    Image(systemName: "music.note")
                }
                .foregroundStyle(Color(red: 1, green: 0.92, blue: 0.56))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(LinearGradient(colors: [.black, .indigo.opacity(0.7), .black],
                                           startPoint: .leading, endPoint: .trailing))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(chrome).frame(height: 3)
                }

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                            VStack(spacing: 4) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 10)
                                    .background(Color(red: 0.91, green: 0.88, blue: 0.66))
                                FlippingAlbumCard(
                                    album: album, side: side,
                                    isFlipped: selectedAlbumID == album.id,
                                    flip: {
                                        nav.noteActivity()
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            centeredAlbumID = album.id
                                            selectedAlbumID = selectedAlbumID == album.id ? nil : album.id
                                        }
                                    },
                                    showsReflection: false
                                )
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.055))
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(chrome, lineWidth: 4)
                                    .allowsHitTesting(false)
                            }
                            .id(album.id)
                            .visualEffect { content, proxy in
                                // Each step away from the rack's center turns the
                                // sleeve farther inward, like a curved magazine.
                                let center = (geometry.size.width - 64) / 2
                                let position = (proxy.frame(in: .named("jukeboxRack")).midX - center) / (side + 24)
                                let depth = min(abs(position), 3)
                                return content
                                    .rotation3DEffect(.degrees(max(-78, min(78, -position * 28))),
                                                      axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                                    .scaleEffect(1 - depth * 0.07)
                                    .offset(y: depth * depth * 3)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 6)
                }
                .safeAreaPadding(.horizontal, max(12, (geometry.size.width - 64 - side - 14) / 2))
                .coordinateSpace(name: "jukeboxRack")
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centeredAlbumID, anchor: .center)
                .scrollIndicators(.hidden)
                .background(Color(red: 0.12, green: 0.12, blue: 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(chrome, lineWidth: 5)
                        .allowsHitTesting(false)
                }

                HStack(spacing: 14) {
                    Image(systemName: "hifispeaker.fill")
                    Text("SELECT AN ALBUM · TAP TO TURN")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(1)
                    Image(systemName: "hifispeaker.fill")
                }
                .foregroundStyle(Color(red: 0.9, green: 0.79, blue: 0.42))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 30)
                    .fill(LinearGradient(colors: [Color(white: 0.2), .black, Color(white: 0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30).strokeBorder(chrome, lineWidth: 6)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .strokeBorder(Color.yellow.opacity(0.75), lineWidth: 5)
                    .blur(radius: 5)
                    .padding(9)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .strokeBorder(
                        LinearGradient(colors: [Color(red: 0.96, green: 1, blue: 0.2),
                                                Color(red: 0.64, green: 0.68, blue: 0.1),
                                                Color(red: 1, green: 0.94, blue: 0.3)],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: 5)
                    .padding(9)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .onAppear {
            if !albums.isEmpty { centeredAlbumID = albums[albums.count / 2].id }
        }
    }
}

// The visibility is derived from the interpolated angle, so the faces swap
// precisely when edge-on and the song titles never appear mirrored.
private struct AlbumFlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity((angle >= 90) == isBack ? 1 : 0)
            .rotation3DEffect(.degrees(angle + (isBack ? 180 : 0)),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.65)
    }
}

private struct FlippingAlbumCard: View {
    let album: Row
    let side: CGFloat
    let isFlipped: Bool
    let flip: () -> Void
    var showsReflection = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Button(action: flip) {
                    CoverFlowAlbumCard(row: album, side: side)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(AlbumFlipFace(angle: isFlipped ? 180 : 0, isBack: false))
                .allowsHitTesting(!isFlipped)
                .accessibilityHidden(isFlipped)

                CoverFlowSongsView(album: album, isActive: isFlipped, flipBack: flip)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .modifier(AlbumFlipFace(angle: isFlipped ? 180 : 0, isBack: true))
                    .allowsHitTesting(isFlipped)
                    .accessibilityHidden(!isFlipped)
            }
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.6), radius: 10, x: 4, y: 6)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: isFlipped)
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }

            if showsReflection {
            CoverFlowAlbumCard(row: album, side: side)
                .scaleEffect(x: 1, y: -1)
                .frame(height: side * 0.24, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [.white.opacity(0.4), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(isFlipped ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            Text(album.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 44, alignment: .top)
        }
        .frame(width: side)
    }
}

private struct CoverFlowSongsView: View {
    let album: Row
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player
    let isActive: Bool
    let flipBack: () -> Void
    @State private var songs: [Row] = []
    @State private var loading = true
    @State private var startingPlayback = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(album.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(action: flipBack) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Show album artwork")
            }
            .padding(.horizontal, 10)
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if loading {
                        ProgressView("Loading songs…")
                    } else if songs.isEmpty {
                        Text(message ?? "No playable songs in this album.")
                    } else {
                        Button("Play Album", systemImage: "play.fill") {
                            if let first = songs.first { play(first) }
                        }
                        .frame(minHeight: 44)
                        .disabled(startingPlayback)
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                play(song)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(index + 1)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    Text(song.title)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .disabled(startingPlayback)
                            Divider()
                        }
                        if startingPlayback {
                            ProgressView("Starting playback…")
                        }
                        if let message {
                            Text(message).foregroundStyle(.secondary)
                        }
                        if player.hasItem {
                            Text("\(player.isPlaying ? "Playing" : "Paused"): \(player.title)")
                        }
                    }
                }
                .font(.caption)
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(white: 0.12))
        .background(Color(red: 0.94, green: 0.92, blue: 0.86))
        .task(id: isActive) {
            guard isActive, loading else { return }
            defer {
                if !Task.isCancelled { loading = false }
            }
            guard case .push(let spec) = album.action else {
                message = "This album cannot be opened."
                return
            }
            do {
                let rows: [Row]
                if let provider = nav.remoteLibrary {
                    rows = try await provider.rows(for: spec)
                } else if !settings.demoMode, case .album(let musicAlbum) = spec {
                    // These covers come from the library, so load its tracks
                    // instead of resolving a different catalog version.
                    let full = try await musicAlbum.with([.tracks], preferredSource: .library)
                    var tracks = Array(full.tracks ?? [])
                    var batch = full.tracks
                    while let current = batch, current.hasNextBatch {
                        try Task.checkCancellation()
                        batch = try await current.nextBatch()
                        if let batch { tracks.append(contentsOf: batch) }
                    }
                    rows = tracks.enumerated().map { index, track in
                        Row(title: track.title, action: .play(.tracks(tracks), index))
                    }
                } else {
                    rows = try await nav.library.rows(for: spec, demo: settings.demoMode)
                }
                try Task.checkCancellation()
                songs = rows.filter {
                    if case .play = $0.action { return true }
                    return false
                }
                if songs.isEmpty, !rows.isEmpty {
                    message = rows.map(\.title).joined(separator: " ")
                }
            } catch is CancellationError {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func play(_ song: Row) {
        guard !startingPlayback, case .play(let source, let index) = song.action else { return }
        startingPlayback = true
        message = nil
        nav.noteActivity()
        Task {
            defer { startingPlayback = false }
            await player.play(source, at: index)
            message = player.lastError
            if settings.demoMode {
                message = "Demo Mode simulates playback without audio."
            }
        }
    }
}

private struct CoverFlowAlbumCard: View {
    let row: Row
    let side: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if case .push(.album(let album)) = row.action, let artwork = album.artwork {
                    ArtworkImage(artwork, width: side, height: side)
                } else {
                    ZStack {
                        LinearGradient(colors: [.indigo, .purple, .black],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note")
                            .font(.system(size: side * 0.35))
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(width: side)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.title)
        .accessibilityHint("Flips the album over to show songs")
    }
}

struct IPodBody: View {
    let u: CGFloat
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let p = ThemePalette.of(settings.theme)
        let shape = RoundedRectangle(cornerRadius: 38 * u, style: .continuous)
        VStack(spacing: 0) {
            LCDView(u: u)
                .overlay { YouTubeScreen(u: u) }
                .padding(.top, 30 * u)
            ClickWheelView(u: u).padding(.top, 30 * u)
            Spacer(minLength: 0)
        }
        .frame(width: 415 * u, height: 692 * u)
        .background(
            ZStack {
                // linear-gradient(42deg, rgba(232,232,232,.96) 0, #fff 149%)
                shape.fill(LinearGradient(colors: [p.bodyBottom, p.bodyTop],
                                          startPoint: UnitPoint(x: 0.1, y: 1.0), endPoint: UnitPoint(x: 1.1, y: -0.4)))
                // conic sheen on the polycarbonate edge
                shape.strokeBorder(
                    AngularGradient(colors: [.white.opacity(0.0), .white.opacity(0.55), .white.opacity(0.0),
                                             .black.opacity(0.12), .white.opacity(0.0), .white.opacity(0.4), .white.opacity(0.0)],
                                    center: .center, angle: .degrees(-23)),
                    lineWidth: 6 * u)
                // inset 0 -1px 3px 2px rgba(168,168,168,.67) / inset -1px 0 2px 5px white
                shape.strokeBorder(p.bodyRim.opacity(0.55), lineWidth: 1.5 * u).blur(radius: 1.5 * u)
                shape.inset(by: 4 * u).strokeBorder(Color.white.opacity(settings.theme == .white ? 0.9 : 0.08), lineWidth: 3 * u).blur(radius: 2 * u)
            }
        )
        .overlay(shape.stroke(p.bodyRim.opacity(0.6), lineWidth: 1.5 * u))
        .shadow(color: .black.opacity(0.45), radius: 18 * u, x: 0, y: 10 * u)
    }
}

/// YouTube's embedded player must stay visible (≥ 200×200 pt, nothing drawn over it) while it plays,
/// so during YouTube Now Playing it takes over the iPod's screen, like video on an iPod.
struct YouTubeScreen: View {
    let u: CGFloat
    @Environment(Navigator.self) private var nav
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if player.remoteKind == .youtubeMusic, nav.current.spec.isNowPlaying {
            let yt = player.hub.youtube.player
            YouTubePlayerView(player: yt)
                .frame(width: max(200, 289 * u), height: max(200, 239 * u))
                .clipShape(RoundedRectangle(cornerRadius: 10 * u, style: .continuous))
                .onAppear { yt.setVisible(true) }
                .onDisappear { yt.setVisible(false) }
                .transition(.opacity)
        }
    }
}
