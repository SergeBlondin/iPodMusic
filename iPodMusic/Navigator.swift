import SwiftUI
import MusicKit
import QuartzCore

enum WheelSegment { case menu, back, forward, playPause }
enum NowPlayingMode { case progress, volume, scrubbing }

/// Constants ported from Apple's web iPod (ipod.pretty.js). Names in comments
/// are the minified identifiers they came from.
enum WheelTuning {
    static let dragStepDegrees = 15.0            // os: degrees of wheel travel per list row / seek step
    static let reversalHysteresis = 8.0          // Vh: degrees needed before a direction change counts
    static let deadZoneRatio = 0.1               // qh: moves passing within 10% radius of centre are ignored
    static let listTiers = [1, 2, 3, 5, 8, 13, 21, 34]   // vl.tiers: rows per click
    static let seekTiers = [1, 2, 3, 5]          // yl.tiers: seconds per click
    static let minSpeed = 180.0                  // deg/s before acceleration starts
    static let maxSpeed = 400.0                  // us: speed cap
    static let speedSmoothing = 0.15             // ys: EMA factor
    static let tierSeconds = 0.5                 // tierMs 500
    static let gapReset = 0.25                   // zs: 250 ms pause resets acceleration
    static let seekSecondsPerStep = 1.0          // ds
    static let degreesPerVolumePercent = 1.25 * 360 / 100   // Ps = 4.5°
    static let degreesPerVolumeClick = 1.25 * 360 / 22      // Es ≈ 20.45°
    static let holdDelay = 1.0                   // Oe: long-press duration
    static let holdRepeat = 0.5                  // ul: repeat interval while held
    static let holdSeekSteps: [Double] = [5, 5, 5, 10, 10, 10, 20]   // Ol
    static let scrubCommitDelay = 1.0            // As
    static let scrubTimeout = 5.0                // fs
    static let volumeTimeout = 5.0               // ws
    static let idleToNowPlaying = 10.0           // ps
    static let pushDuration = 0.24               // Vl: 240 ms per screen width, cosine ease-in-out
    static let modeSlideDuration = 0.3           // .now-playing-progress transition 0.3s ease-out
    static let scrollWheelRatio = 276.0 / 350.0  // cs
    static let selectButtonRatio = 100.0 / 350.0 // rs
}

/// Ja(): speed-based acceleration with an exponential moving average.
struct WheelAccelerator {
    let tiers: [Int]
    private var ema = 0.0
    private var lastDir = 0
    private var lastT: CFTimeInterval?
    private var fastSince: CFTimeInterval?

    init(tiers: [Int]) { self.tiers = tiers }

    mutating func reset() { ema = 0; lastDir = 0; lastT = nil; fastSince = nil }

    mutating func next(speed: Double, dir: Int, active: Bool) -> Int {
        guard active else { reset(); return tiers[0] }
        let now = CACurrentMediaTime()
        let gap = lastT.map { now - $0 > WheelTuning.gapReset } ?? false
        lastT = now
        let s = min(speed, WheelTuning.maxSpeed)
        if dir != lastDir || gap { ema = s; lastDir = dir; fastSince = nil }
        else { ema += WheelTuning.speedSmoothing * (s - ema) }
        if ema <= WheelTuning.minSpeed { fastSince = nil; return tiers[0] }
        if fastSince == nil { fastSince = now }
        let i = min(tiers.count - 1, Int((now - fastSince!) / WheelTuning.tierSeconds))
        return tiers[i]
    }
}

@MainActor @Observable
final class Navigator {
    struct Screen: Identifiable {
        let id = UUID()
        let spec: ScreenSpec
        var rows: [Row] = []
        var loading = false
        var selected = 0
        var top = 0
    }

    var stack: [Screen] = []
    var forward = true
    var npMode: NowPlayingMode = .progress
    var scrubPreview: TimeInterval? = nil
    var showSearch = false
    /// Settings ▸ Set Up Spotify / Set Up YouTube opens a touch sheet (text entry + copy buttons need touch).
    var setupSheet: MusicSourceKind? = nil
    var pressed: WheelSegment? = nil
    var centerPressed = false
    var authorized = false
    var lit = true
    let visibleRows = 6

    let settings: AppSettings
    let player: PlayerModel
    let library = Library()

    private var listAccel = WheelAccelerator(tiers: WheelTuning.listTiers)
    private var seekAccel = WheelAccelerator(tiers: WheelTuning.seekTiers)
    private var accDegrees = 0.0
    private var accVolumeClick = 0.0
    private var volumeMoved = false
    private var lastStepDir = 0
    private var lastWasVolume = false
    private var dragging = false
    private var holdIndex = 0
    private var holdBase: TimeInterval? = nil
    private var holdTask: Task<Void, Never>?
    private var holdFired = false
    private var modeTimeout: Task<Void, Never>?
    private var scrubCommit: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var backlightTask: Task<Void, Never>?

    init(settings: AppSettings, player: PlayerModel) {
        self.settings = settings
        self.player = player
        stack = [Screen(spec: .main, rows: [])]
        stack[0].rows = mainRows()
        Task { await bootstrap() }
    }

    var current: Screen { stack[stack.count - 1] }

    // MARK: Sources

    var hub: SourceHub { player.hub }
    /// The Spotify / YouTube library, or nil for Apple Music (and demo mode), which keep the original path.
    var remoteLibrary: MusicLibraryProvider? {
        settings.demoMode ? nil : hub.library(for: settings.source)
    }

    private func remoteGateRows(_ p: MusicLibraryProvider) -> [Row]? {
        if let problem = p.setupProblem { return problem.map { Row(title: $0, centered: true, info: true) } }
        if !p.isSignedIn { return [Row(title: "Sign In to \(p.kind.label)", chevron: true, action: .signIn)] }
        return nil
    }

    /// "✓" when the source has a Client ID and is signed in.
    func setupStatus(_ k: MusicSourceKind) -> String? {
        guard let p = hub.library(for: k), p.setupProblem == nil else { return nil }
        return p.isSignedIn ? "✓" : "Sign In"
    }

    /// Called when the setup sheet closes.
    func setupClosed() {
        stack[0].rows = mainRows()
        let i = stack.count - 1
        if current.spec.isSettings {
            let sel = stack[i].selected
            stack[i].rows = settingsRows(); stack[i].selected = sel
            clampSelection()
        } else if i > 0 {
            reloadAfterSignIn()
        }
        noteActivity()
    }

    func sourceRows() -> [Row] {
        MusicSourceKind.allCases.map { k in
            Row(title: k.label, value: k == settings.source ? "✓" : nil, action: .setSource(k))
        }
    }

    // MARK: Startup

    private func bootstrap() async {
        if settings.demoMode {
            authorized = true
        } else {
            var status = MusicAuthorization.currentStatus
            if status == .notDetermined { status = await MusicAuthorization.request() }
            authorized = status == .authorized
        }
        stack[0].rows = mainRows()
        if settings.startScreen == "nowPlaying" {
            await player.play(.demo(DemoData.songs), at: 2)
            try? await Task.sleep(for: .milliseconds(300))
            player.seek(to: 83)
            push(.nowPlaying, animated: false)
        } else if settings.startScreen == "songs" {
            push(.songs, animated: false)
            try? await Task.sleep(for: .milliseconds(200))
            if stack.count > 1 { stack[1].selected = 3 }
        } else if settings.startScreen == "settings" {
            push(.settings, animated: false)
        } else if settings.startScreen == "setupSpotify" || settings.startScreen == "setupYouTube" {
            push(.settings, animated: false)
            setupSheet = settings.startScreen == "setupSpotify" ? .spotify : .youtubeMusic
        } else if settings.startScreen == "source" {
            push(.settings, animated: false)
            push(.source, animated: false)
        }
        noteActivity()
    }

    func mainRows() -> [Row] {
        if let p = remoteLibrary { return remoteMainRows(p) }
        // Same top level as Apple's web iPod (Playlists, Artists, Songs, Settings, Now Playing),
        // plus Search for the Apple Music catalog.
        var rows: [Row] = [
            Row(title: "Playlists", chevron: true, action: .push(.playlists)),
            Row(title: "Artists", chevron: true, action: .push(.artists)),
            Row(title: "Songs", chevron: true, action: .push(.songs)),
            Row(title: "Search", chevron: true, action: .push(.search)),
            Row(title: "Settings", chevron: true, action: .push(.settings)),
        ]
        if player.hasItem { rows.append(Row(title: "Now Playing", chevron: true, action: .nowPlaying)) }
        if !settings.demoMode && !authorized {
            rows.insert(Row(title: "Allow Apple Music", chevron: true, action: .openSystemSettings), at: 0)
        }
        return rows
    }

    private func remoteMainRows(_ p: MusicLibraryProvider) -> [Row] {
        var rows: [Row] = [
            Row(title: "Playlists", chevron: true, action: .push(.playlists)),
            Row(title: "Artists", chevron: true, action: .push(.artists)),
            Row(title: "Albums", chevron: true, action: .push(.albums)),
            Row(title: "Songs", chevron: true, action: .push(.songs)),
            Row(title: "Search", chevron: true, action: .push(.search)),
            Row(title: "Settings", chevron: true, action: .push(.settings)),
        ]
        if player.hasItem { rows.append(Row(title: "Now Playing", chevron: true, action: .nowPlaying)) }
        if p.setupProblem != nil {
            rows.insert(Row(title: "Set Up \(p.kind.label)", chevron: true,
                            action: .push(.preset(title: p.kind.label, rows: remoteGateRows(p) ?? []))), at: 0)
        } else if !p.isSignedIn {
            rows.insert(Row(title: "Sign In to \(p.kind.short)", chevron: true, action: .signIn), at: 0)
        }
        return rows
    }

    func settingsRows() -> [Row] {
        var rows = [
            Row(title: "Source", value: settings.source.short, chevron: true, action: .push(.source)),
            Row(title: "Set Up Spotify", value: setupStatus(.spotify), chevron: true, action: .openSetup(.spotify)),
            Row(title: "Set Up YouTube", value: setupStatus(.youtubeMusic), chevron: true, action: .openSetup(.youtubeMusic)),
            Row(title: "Shuffle", value: settings.shuffle.label, action: .toggle(.shuffle)),
            Row(title: "Repeat", value: settings.repeatMode.label, action: .toggle(.repeatMode)),
            Row(title: "Backlight Timer", value: settings.backlightTimer.label, action: .toggle(.backlight)),
            Row(title: "Clicker", value: settings.clicker ? "On" : "Off", action: .toggle(.clicker)),
            Row(title: "Haptics", value: settings.haptics ? "On" : "Off", action: .toggle(.haptics)),
            Row(title: "Album Art", value: settings.albumArt ? "On" : "Off", action: .toggle(.albumArt)),
            Row(title: "Theme", value: settings.theme.label, action: .toggle(.theme)),
            Row(title: "Auto Now Playing", value: settings.autoNowPlaying ? "On" : "Off", action: .toggle(.autoNowPlaying)),
        ]
        if !settings.forcedDemo {
            rows.append(Row(title: "Demo Mode", value: settings.demoMode ? "On" : "Off", action: .toggle(.demo)))
        }
        rows.append(Row(title: "Reset All Settings", chevron: true, action: .push(.preset(title: "Reset All", rows: [
            Row(title: "Cancel", action: .back),
            Row(title: "Reset", action: .toggle(.reset)),
        ]))))
        if let p = remoteLibrary, p.isSignedIn {
            rows.append(Row(title: "Sign Out of \(p.kind.short)", action: .signOut))
        }
        rows.append(Row(title: "About", chevron: true, action: .push(.about)))
        return rows
    }

    func aboutRows() -> [Row] {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let songs = settings.demoMode ? "\(DemoData.songs.count)" : (library.cachedSongs.map { "\($0.count)" } ?? "–")
        return [
            Row(title: "iPod", centered: true, info: true),
            Row(title: "Songs", value: songs, info: true),
            Row(title: "Version", value: v, info: true),
            Row(title: "Music", value: settings.demoMode ? "Demo" : (remoteLibrary.map { $0.isSignedIn ? $0.kind.short : "Signed out" }
                                                                    ?? (authorized ? "Apple Music" : "Not allowed")), info: true),
        ]
    }

    // MARK: Navigation

    func push(_ spec: ScreenSpec, animated: Bool = true) {
        var s = Screen(spec: spec)
        switch spec {
        case .settings: s.rows = settingsRows()
        case .about: s.rows = aboutRows(); s.selected = -1
        case .search: s.rows = [Row(title: "Search \(settings.demoMode ? "Apple Music" : settings.source.label)…", chevron: true, action: .searchInput)]
        case .source: s.rows = sourceRows(); s.selected = MusicSourceKind.allCases.firstIndex(of: settings.source) ?? 0
        case .nowPlaying: npMode = .progress; scrubPreview = nil
        case .preset(_, let rows): s.rows = rows
        default: s.loading = true
        }
        let id = s.id
        mutateStack(forward: true, animated: animated) { $0.append(s) }
        if s.loading { Task { await load(id: id, spec: spec) } }
    }

    func pop() {
        guard stack.count > 1 else { return }
        if current.spec.isNowPlaying { leaveSeeking(commit: true) }
        mutateStack(forward: false, animated: true) { stack in
            stack.removeLast()
            if stack.count == 1 { stack[0].rows = self.mainRows() }
            if stack[stack.count - 1].spec.isSettings { stack[stack.count - 1].rows = self.settingsRows() }
        }
    }

    private func mutateStack(forward f: Bool, animated: Bool, _ change: @escaping (inout [Screen]) -> Void) {
        if !animated { change(&stack); clampSelection(); return }
        // Set the direction first so both the incoming and outgoing screens pick it up.
        forward = f
        let anim = Animation.timingCurve(0.37, 0, 0.63, 1, duration: WheelTuning.pushDuration)  // ≈ -0.5(cos πt - 1)
        DispatchQueue.main.async {
            withAnimation(anim) { change(&self.stack) }
            self.clampSelection()
        }
    }

    private func load(id: UUID, spec: ScreenSpec) async {
        var rows: [Row]
        if let p = remoteLibrary {
            if let gate = remoteGateRows(p) {
                rows = gate
            } else {
                do {
                    rows = try await p.rows(for: spec)
                    if case .songs = spec, !rows.isEmpty {
                        rows.insert(Row(title: "Shuffle Songs", action: .shuffleAll), at: 0)
                    }
                    if rows.isEmpty { rows = [Row(title: "No Music", centered: true, info: true)] }
                } catch SourceError.notSignedIn {
                    rows = [Row(title: "Sign In to \(p.kind.label)", chevron: true, action: .signIn)]
                } catch {
                    rows = [Row(title: "Couldn't Load", centered: true, info: true),
                            Row(title: error.localizedDescription, centered: true, info: true)]
                }
            }
        } else if !settings.demoMode && !authorized {
            rows = [Row(title: "Allow Apple Music", chevron: true, action: .openSystemSettings)]
        } else {
            do {
                rows = try await library.rows(for: spec, demo: settings.demoMode)
                if case .songs = spec, !rows.isEmpty {
                    rows.insert(Row(title: "Shuffle Songs", action: .shuffleAll), at: 0)
                }
                if rows.isEmpty { rows = [Row(title: "No Music", centered: true, info: true)] }
            } catch {
                rows = [Row(title: "Couldn't Load", centered: true, info: true),
                        Row(title: error.localizedDescription, centered: true, info: true)]
            }
        }
        if let i = stack.firstIndex(where: { $0.id == id }) {
            stack[i].rows = rows
            stack[i].loading = false
        }
    }

    // MARK: Selection

    @discardableResult
    func moveSelection(by delta: Int) -> Bool {
        let i = stack.count - 1
        let n = stack[i].rows.count
        guard n > 0, !stack[i].rows.allSatisfy(\.info) else { return false }
        let old = stack[i].selected
        let new = max(0, min(n - 1, old + delta))   // clamps at the ends, no wrap (like we())
        guard new != old else { return false }
        stack[i].selected = new
        // scrollIntoView({block: "nearest"}): the list only scrolls once the highlight hits an edge.
        if new < stack[i].top { stack[i].top = new }
        if new >= stack[i].top + visibleRows { stack[i].top = new - visibleRows + 1 }
        return true
    }

    func clampSelection() {
        let i = stack.count - 1
        let n = stack[i].rows.count
        if stack[i].selected >= 0 { stack[i].selected = max(0, min(max(0, n - 1), stack[i].selected)) }
        stack[i].top = max(0, min(stack[i].top, max(0, n - visibleRows)))
    }

    func tapRow(_ index: Int) {
        noteActivity()
        let i = stack.count - 1
        guard stack[i].rows.indices.contains(index), !stack[i].rows[index].info else { return }
        stack[i].selected = index
        Feedback.shared.press(clicker: settings.clicker, haptics: settings.haptics)
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            activate()
        }
    }

    func activate() {
        guard !current.spec.isNowPlaying, let row = current.rows[safe: current.selected], !row.info else { return }
        switch row.action {
        case .push(let spec): push(spec)
        case .play(let src, let idx):
            Task { await player.play(src, at: idx); refreshMainRows() }
            push(.nowPlaying)
        case .shuffleAll:
            Task {
                if settings.demoMode { await player.shuffle(.demo(DemoData.songs)) }
                else if let p = remoteLibrary, let t = try? await p.allSongs() { await player.shuffle(.remote(t, context: nil)) }
                else if authorized, let songs = try? await library.librarySongs() { await player.shuffle(.songs(songs)) }
                refreshMainRows()
            }
            push(.nowPlaying)
        case .nowPlaying: push(.nowPlaying)
        case .toggle(let key): toggle(key)
        case .searchInput: showSearch = true
        case .back: pop()
        case .openSystemSettings:
            Task {
                let st = await MusicAuthorization.request()
                authorized = st == .authorized
                if !authorized, let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
                stack[0].rows = mainRows()
            }
        case .setSource(let k):
            guard k != settings.source else { pop(); return }
            settings.source = k
            library.cachedSongs = nil
            stack[0].rows = mainRows()
            pop()
        case .signIn:
            guard let p = remoteLibrary else { return }
            Task {
                do {
                    try await p.signIn()
                    hub.revision += 1
                } catch {
                    let i = stack.count - 1
                    stack[i].rows.append(Row(title: error.localizedDescription, centered: true, info: true))
                }
                reloadAfterSignIn()
            }
        case .signOut:
            remoteLibrary?.signOut()
            hub.revision += 1
            let i = stack.count - 1
            if current.spec.isSettings { stack[i].rows = settingsRows(); clampSelection() }
            stack[0].rows = mainRows()
        case .openURL(let url):
            UIApplication.shared.open(url)
        case .openSetup(let k):
            setupSheet = k
        case .none: break
        }
    }

    /// After signing in, rebuild the main menu and reload whatever list is on screen.
    func reloadAfterSignIn() {
        stack[0].rows = mainRows()
        let i = stack.count - 1
        guard i > 0 else { clampSelection(); return }
        let spec = stack[i].spec
        switch spec {
        case .settings, .about, .search, .nowPlaying, .source, .preset: return
        default:
            stack[i].loading = true
            let id = stack[i].id
            Task { await load(id: id, spec: spec) }
        }
    }

    func submitSearch(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        push(.searchResults(t))
    }

    private func toggle(_ key: SettingKey) {
        func cycle<T: CaseIterable & Equatable>(_ v: T) -> T where T.AllCases: RandomAccessCollection, T.AllCases.Index == Int {
            let all = Array(T.allCases); return all[(all.firstIndex(of: v)! + 1) % all.count]
        }
        switch key {
        case .shuffle: settings.shuffle = cycle(settings.shuffle); player.applyModes()
        case .repeatMode: settings.repeatMode = cycle(settings.repeatMode); player.applyModes()
        case .clicker: settings.clicker.toggle()
        case .haptics: settings.haptics.toggle()
        case .backlight: settings.backlightTimer = cycle(settings.backlightTimer); noteActivity()
        case .albumArt: settings.albumArt.toggle()
        case .theme: settings.theme = cycle(settings.theme)
        case .autoNowPlaying: settings.autoNowPlaying.toggle()
        case .demo:
            settings.demoMode.toggle()
            library.cachedSongs = nil
            Task { await bootstrap() }
        case .reset:
            settings.reset(); player.applyModes(); noteActivity()
            pop(); return
        }
        let i = stack.count - 1
        if current.spec.isSettings {
            let sel = stack[i].selected
            stack[i].rows = settingsRows(); stack[i].selected = sel
        }
    }

    private func refreshMainRows() {
        stack[0].rows = mainRows()
        if stack.count == 1 { clampSelection() }
    }

    // MARK: Click wheel input (port of Xr / he / qt)

    private enum Target { case list, volume, seek }

    private var target: Target {
        guard current.spec.isNowPlaying else { return .list }
        return npMode == .scrubbing ? .seek : .volume
    }

    func wheelBegan() {
        // Wt(): st.reset()
        accDegrees = 0; accVolumeClick = 0; volumeMoved = false; lastStepDir = 0
        dragging = true
        noteActivity()
    }

    /// One filtered pointer move from the wheel. `step` is +1 (clockwise) or -1.
    func wheelScroll(step: Int, degrees: Double, speed: Double) {
        noteActivity()
        let t = target
        let isVolume = t == .volume
        if step != lastStepDir || isVolume != lastWasVolume {
            lastStepDir = step; lastWasVolume = isVolume
            accDegrees = 0; accVolumeClick = 0; volumeMoved = false
        }
        // accelerate() runs on every event so its speed average stays warm.
        let seekMult = seekAccel.next(speed: speed, dir: step, active: t == .seek)
        let listMult = listAccel.next(speed: speed, dir: step, active: t == .list)
        accDegrees += degrees

        switch t {
        case .list:
            let count = Int(accDegrees / WheelTuning.dragStepDegrees)
            guard count >= 1 else { return }
            accDegrees -= Double(count) * WheelTuning.dragStepDegrees
            if moveSelection(by: step * count * listMult) {
                Feedback.shared.tick(clicker: settings.clicker, haptics: settings.haptics, count: count)
            }
        case .volume:
            enterVolume()
            let c = Int(accDegrees / WheelTuning.degreesPerVolumePercent)
            if c >= 1 {
                accDegrees -= Double(c) * WheelTuning.degreesPerVolumePercent
                let before = Int((player.volume * 100).rounded())
                let after = max(0, min(100, before + step * c))
                if after != before { player.setVolume(Float(after) / 100); volumeMoved = true }
            }
            accVolumeClick += degrees
            let k = Int(accVolumeClick / WheelTuning.degreesPerVolumeClick)
            if k >= 1 {
                accVolumeClick -= Double(k) * WheelTuning.degreesPerVolumeClick
                if volumeMoved { Feedback.shared.tick(clicker: settings.clicker, haptics: settings.haptics, count: k) }
                volumeMoved = false
            }
        case .seek:
            let count = Int(accDegrees / WheelTuning.dragStepDegrees)
            guard count >= 1, player.duration > 0 else { return }
            accDegrees -= Double(count) * WheelTuning.dragStepDegrees
            restartModeTimeout()
            let base = scrubPreview ?? floor(player.time)
            let newT = max(0, min(player.duration, (base + Double(step * count * seekMult) * WheelTuning.seekSecondsPerStep).rounded()))
            if newT != base {
                scrubPreview = newT
                Feedback.shared.silentTick(haptics: settings.haptics)   // clicker is silent while seeking
                if !dragging { scheduleScrubCommit() }
            }
        }
    }

    func wheelEnded() {
        dragging = false
        accDegrees = 0
        // The web iPod commits a drag-seek when the finger lifts.
        if npMode == .scrubbing, scrubPreview != nil { commitScrub() }
    }

    private func enterVolume() {
        if npMode != .volume {
            withAnimation(.easeOut(duration: WheelTuning.modeSlideDuration)) { npMode = .volume }
        }
        restartModeTimeout()
    }

    private func enterSeeking() {
        withAnimation(.easeOut(duration: WheelTuning.modeSlideDuration)) { npMode = .scrubbing }
        scrubPreview = nil
        restartModeTimeout()
    }

    private func leaveSeeking(commit: Bool) {
        if commit, scrubPreview != nil { commitScrub() }
        scrubPreview = nil
        modeTimeout?.cancel()
        if npMode != .progress {
            withAnimation(.easeOut(duration: WheelTuning.modeSlideDuration)) { npMode = .progress }
        }
    }

    private func restartModeTimeout() {
        modeTimeout?.cancel()
        let delay = npMode == .scrubbing ? WheelTuning.scrubTimeout : WheelTuning.volumeTimeout
        modeTimeout = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            leaveSeeking(commit: true)
        }
    }

    private func scheduleScrubCommit() {
        scrubCommit?.cancel()
        scrubCommit = Task {
            try? await Task.sleep(for: .seconds(WheelTuning.scrubCommitDelay))
            guard !Task.isCancelled else { return }
            commitScrub()
        }
    }

    private func commitScrub() {
        scrubCommit?.cancel()
        guard let t = scrubPreview else { return }
        player.seek(to: t)
        // Keep showing the preview until the player reports the new time.
        Task { try? await Task.sleep(for: .milliseconds(350)); if npMode != .scrubbing || scrubPreview == t { scrubPreview = nil } }
    }

    // MARK: Buttons

    func segmentDown(_ seg: WheelSegment) {
        noteActivity()
        pressed = seg
        holdFired = false
        holdIndex = 0
        holdBase = nil
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(for: .seconds(WheelTuning.holdDelay))
            guard !Task.isCancelled else { return }
            holdFired = true
            holdAction(seg, repeat: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(WheelTuning.holdRepeat))
                guard !Task.isCancelled else { return }
                holdAction(seg, repeat: true)
            }
        }
    }

    /// A touch that started on a button turned into a wheel drag.
    func segmentCancel() {
        holdTask?.cancel(); holdTask = nil
        pressed = nil
    }

    func segmentUp(_ seg: WheelSegment) {
        holdTask?.cancel(); holdTask = nil
        pressed = nil
        guard !holdFired else { return }
        Feedback.shared.press(clicker: settings.clicker, haptics: settings.haptics)
        switch seg {
        case .menu:
            if current.spec.isNowPlaying && npMode != .progress { leaveSeeking(commit: true) }
            else { pop() }
        case .back: player.previous()
        case .forward: player.next()
        case .playPause: player.togglePlay()
        }
        Task { try? await Task.sleep(for: .milliseconds(300)); refreshMainRows() }
    }

    private func holdAction(_ seg: WheelSegment, repeat: Bool) {
        switch seg {
        case .back, .forward:
            // Zr(): hold-to-seek from the time when the hold began, 5,5,5,10,10,10,20 s.
            guard player.hasItem, player.duration > 0, npMode != .scrubbing else { return }
            if holdBase == nil { holdBase = player.time }
            let step = WheelTuning.holdSeekSteps[min(holdIndex, WheelTuning.holdSeekSteps.count - 1)]
            holdIndex += 1
            let dir: Double = seg == .forward ? 1 : -1
            let t = max(0, min(player.duration, holdBase! + dir * step))
            holdBase = t
            player.seek(to: t)
            Feedback.shared.silentTick(haptics: settings.haptics)
        case .menu:
            // Like the original iPod: hold Menu to toggle the backlight.
            if !`repeat` {
                backlightTask?.cancel()
                lit.toggle()
                Feedback.shared.press(clicker: false, haptics: settings.haptics)
            }
        case .playPause:
            break
        }
    }

    func centerDown() { centerPressed = true; noteActivity() }

    func centerUp() {
        centerPressed = false
        Feedback.shared.press(clicker: settings.clicker, haptics: settings.haptics)
        if current.spec.isNowPlaying {
            // y(): select toggles seeking (from progress or volume) on and off.
            guard player.hasItem else { return }
            if npMode == .scrubbing { leaveSeeking(commit: true) } else { enterSeeking() }
            return
        }
        activate()
    }

    // MARK: Activity: backlight timer + idle → Now Playing

    func noteActivity() {
        switch settings.backlightTimer {
        case .always: backlightTask?.cancel(); lit = true
        case .off: backlightTask?.cancel(); lit = false
        default:
            lit = true
            backlightTask?.cancel()
            let secs = settings.backlightTimer.seconds ?? 5
            backlightTask = Task {
                try? await Task.sleep(for: .seconds(secs))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { lit = false }
            }
        }
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: .seconds(WheelTuning.idleToNowPlaying))
            guard !Task.isCancelled else { return }
            if settings.autoNowPlaying, player.isPlaying, !current.spec.isNowPlaying, !showSearch {
                push(.nowPlaying)
            }
        }
    }
}
