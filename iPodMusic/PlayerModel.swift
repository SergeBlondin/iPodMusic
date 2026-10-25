import SwiftUI
import MusicKit
import MediaPlayer
import AVFoundation

/// Wraps ApplicationMusicPlayer (or a simulated demo player) and publishes
/// the Now Playing state that the LCD renders.
@MainActor @Observable
final class PlayerModel {
    var title = ""
    var artist = ""
    var album = ""
    var artwork: Artwork? = nil
    var demoHue: Double? = nil
    var time: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var hasItem = false
    var index = 0
    var count = 0
    var volume: Float = 0.5
    var lastError: String? = nil
    /// Cover art URL for Spotify/YouTube tracks (Apple Music uses `artwork`).
    var artworkURL: URL? = nil
    /// Which non-Apple source is driving playback; nil = Apple Music (or demo) as before.
    var remoteKind: MusicSourceKind? = nil

    private let settings: AppSettings
    let hub: SourceHub
    private var remote: RemotePlayback? { remoteKind.flatMap { hub.player(for: $0) } }
    private var timer: Timer?
    private var demoQueue: [DemoSong] = []
    private var demoIndex = 0
    private var demoTime: TimeInterval = 0
    private var demoPlaying = false
    private var demoLastTick = Date()

    private var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }
    var isDemo: Bool { settings.demoMode }

    init(settings: AppSettings, hub: SourceHub) {
        self.settings = settings
        self.hub = hub
        volume = AVAudioSession.sharedInstance().outputVolume
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        if isDemo {
            if demoPlaying {
                let now = Date()
                demoTime += now.timeIntervalSince(demoLastTick)
                demoLastTick = now
                if demoTime >= (demoQueue[safe: demoIndex]?.duration ?? 0) {
                    advanceDemo(1)
                }
            }
            applyDemo()
            return
        }
        if let r = remote {
            r.tick()
            let s = r.state
            hasItem = s.hasItem
            title = s.title; artist = s.artist; album = s.album
            time = s.time; duration = s.duration
            isPlaying = s.isPlaying
            index = s.index; count = s.count
            artwork = nil; demoHue = nil; artworkURL = s.artworkURL
            let v = AVAudioSession.sharedInstance().outputVolume
            if !VolumeControl.shared.isAdjusting { volume = v }
            return
        }
        artworkURL = nil
        let q = player.queue
        if let e = q.currentEntry {
            hasItem = true
            title = e.title
            artist = e.subtitle ?? ""
            artwork = e.artwork
            demoHue = nil
            if let item = e.item {
                switch item {
                case .song(let s):
                    duration = s.duration ?? 0
                    album = s.albumTitle ?? ""
                    if artist.isEmpty { artist = s.artistName }
                case .musicVideo(let v):
                    duration = v.duration ?? 0
                    album = ""
                @unknown default:
                    break
                }
            }
            let entries = q.entries
            index = entries.firstIndex(where: { $0.id == e.id }) ?? 0
            count = entries.count
        } else {
            hasItem = false
        }
        time = player.playbackTime
        isPlaying = player.state.playbackStatus == .playing
        let v = AVAudioSession.sharedInstance().outputVolume
        if !VolumeControl.shared.isAdjusting { volume = v }
    }

    // MARK: Commands

    func play(_ source: QueueSource, at i: Int) async {
        if case .remote = source {} else if case .demo = source {} else { remoteKind = nil }
        switch source {
        case .remote(let tracks, let context):
            let kind = settings.source
            guard let r = hub.player(for: kind) else { return }
            if remoteKind == nil, ApplicationMusicPlayer.shared.state.playbackStatus == .playing {
                ApplicationMusicPlayer.shared.pause()
            }
            remoteKind = kind
            lastError = nil
            do {
                try await r.play(tracks, at: i, context: context)
                r.setModes(shuffle: settings.shuffle == .songs, repeatMode: settings.repeatMode)
            } catch {
                lastError = error.localizedDescription
            }
            refresh()
        case .demo(let songs):
            demoQueue = songs; demoIndex = i; demoTime = 0; demoPlaying = true; demoLastTick = Date()
            applyDemo()
        case .songs(let songs):
            guard songs.indices.contains(i) else { return }
            player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: songs[i])
            await startPlayback()
        case .tracks(let tracks):
            guard tracks.indices.contains(i) else { return }
            player.queue = ApplicationMusicPlayer.Queue(for: tracks, startingAt: tracks[i])
            await startPlayback()
        }
    }

    func shuffle(_ source: QueueSource) async {
        switch source {
        case .remote(let t, _):
            guard !t.isEmpty else { return }
            await play(.remote(t.shuffled(), context: nil), at: 0)
        case .demo(let s):
            await play(.demo(s.shuffled()), at: 0)
        case .songs(let s):
            guard !s.isEmpty else { return }
            let shuffled = s.shuffled()
            player.queue = ApplicationMusicPlayer.Queue(for: shuffled)
            player.state.shuffleMode = .songs
            await startPlayback()
        case .tracks(let t):
            guard !t.isEmpty else { return }
            player.queue = ApplicationMusicPlayer.Queue(for: t.shuffled())
            await startPlayback()
        }
    }

    private func startPlayback() async {
        applyModes()
        do {
            try await player.prepareToPlay()
            try await player.play()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func applyModes() {
        guard !isDemo else { return }
        if let r = remote { r.setModes(shuffle: settings.shuffle == .songs, repeatMode: settings.repeatMode); return }
        player.state.shuffleMode = settings.shuffle == .songs ? .songs : .off
        switch settings.repeatMode {
        case .off: player.state.repeatMode = MusicPlayer.RepeatMode.none
        case .one: player.state.repeatMode = .one
        case .all: player.state.repeatMode = .all
        }
    }

    func togglePlay() {
        if isDemo {
            guard !demoQueue.isEmpty else { return }
            demoPlaying.toggle(); demoLastTick = Date(); applyDemo(); return
        }
        if let r = remote { r.togglePlay(); isPlaying.toggle(); return }
        guard hasItem else { return }
        if player.state.playbackStatus == .playing { player.pause() }
        else { Task { try? await player.play(); refresh() } }
        isPlaying.toggle()
    }

    func next() {
        if isDemo { advanceDemo(1); return }
        if let r = remote { r.next(); return }
        Task { try? await player.skipToNextEntry(); refresh() }
    }

    func previous() {
        if isDemo {
            if demoTime > 3 { demoTime = 0; applyDemo() } else { advanceDemo(-1) }
            return
        }
        if let r = remote { r.previous(); return }
        if player.playbackTime > 3 { player.playbackTime = 0; refresh(); return }
        Task { try? await player.skipToPreviousEntry(); refresh() }
    }

    func seek(to t: TimeInterval) {
        let clamped = max(0, min(duration, t))
        if isDemo { demoTime = clamped; applyDemo(); return }
        if let r = remote { r.seek(to: clamped); time = clamped; return }
        player.playbackTime = clamped
        time = clamped
    }

    func setVolume(_ v: Float) {
        volume = max(0, min(1, v))
        VolumeControl.shared.set(volume)
    }

    // MARK: Demo

    private func advanceDemo(_ d: Int) {
        guard !demoQueue.isEmpty else { return }
        demoIndex = (demoIndex + d + demoQueue.count) % demoQueue.count
        demoTime = 0; demoLastTick = Date()
        applyDemo()
    }

    private func applyDemo() {
        guard let s = demoQueue[safe: demoIndex] else { hasItem = false; isPlaying = false; return }
        hasItem = true
        title = s.title; artist = s.artist; album = s.album
        duration = s.duration; time = demoTime
        isPlaying = demoPlaying
        index = demoIndex; count = demoQueue.count
        artwork = nil; demoHue = s.hue
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// The click wheel adjusts the system volume, as on the iPod, via a hidden MPVolumeView.
@MainActor
final class VolumeControl {
    static let shared = VolumeControl()
    let view: MPVolumeView = {
        let v = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
        v.alpha = 0.01
        v.isUserInteractionEnabled = false
        return v
    }()
    var isAdjusting = false
    private var endTask: Task<Void, Never>?

    func set(_ value: Float) {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        isAdjusting = true
        slider.setValue(value, animated: false)
        slider.sendActions(for: .valueChanged)
        endTask?.cancel()
        endTask = Task { try? await Task.sleep(for: .milliseconds(600)); isAdjusting = false }
    }
}

struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: .zero)
        host.addSubview(VolumeControl.shared.view)
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
