import SwiftUI

@main
struct iPodMusicApp: App {
    @State private var settings = AppSettings()
    @State private var player: PlayerModel
    @State private var nav: Navigator
    @State private var hub: SourceHub
    @Environment(\.scenePhase) private var phase

    init() {
        let s = AppSettings()
        let h = SourceHub()
        let p = PlayerModel(settings: s, hub: h)
        _hub = State(initialValue: h)
        _settings = State(initialValue: s)
        _player = State(initialValue: p)
        _nav = State(initialValue: Navigator(settings: s, player: p))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(player)
                .environment(nav)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
                .onOpenURL { url in _ = hub.handle(url: url) }
                .onChange(of: phase) { _, ph in
                    if ph == .active { hub.spotify.appBecameActive() }
                    else if ph == .background { hub.spotify.appWillResignActive(); hub.youtube.player.setVisible(false) }
                }
        }
    }
}
