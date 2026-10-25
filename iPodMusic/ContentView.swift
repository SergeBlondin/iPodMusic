import SwiftUI

/// The whole device, laid out in the web iPod's CSS pixel units (415 × 692 body)
/// and scaled by `u` to fit the phone.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var nav
    @State private var searchText = ""

    var body: some View {
        @Bindable var nav = nav
        let p = ThemePalette.of(settings.theme)
        GeometryReader { g in
            let u = max(0.5, min((g.size.width - 24) / 415, (g.size.height - 56) / 700, 1.2))
            ZStack {
                p.background.ignoresSafeArea()
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
