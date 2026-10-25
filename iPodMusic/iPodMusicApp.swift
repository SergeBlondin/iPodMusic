import SwiftUI

@main
struct iPodMusicApp: App {
    @State private var settings = AppSettings()
    @State private var player: PlayerModel
    @State private var nav: Navigator

    init() {
        let s = AppSettings()
        let p = PlayerModel(settings: s)
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
        }
    }
}
