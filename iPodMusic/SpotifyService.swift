import SwiftUI
import SpotifyiOS

/// Spotify source.
/// - Library: Spotify Web API, signed in with OAuth Authorization Code + PKCE (no client secret on the phone).
/// - Playback: the official Spotify iOS SDK (App Remote) drives the installed Spotify app;
///   the Web API player endpoints are used to start a playlist/album at a given track and as a fallback.
/// Requires Spotify Premium and the Spotify app on the phone.
@MainActor
final class SpotifyService: NSObject, MusicLibraryProvider, RemotePlayback {
    static let redirectURI = "ipodmusic://spotify-callback"
    let kind = MusicSourceKind.spotify
    private let api = URL(string: "https://api.spotify.com/v1")!

    /// Pasted in Settings ▸ Set Up Spotify, else Config/Sources.xcconfig.
    var clientID: String? { ClientIDStore.effective(.spotify) }
    private var builtFor: String?
    private var _oauth: OAuthPKCE?
    private var _remote: SPTAppRemote?
    private var oauth: OAuthPKCE? { rebuildIfNeeded(); return _oauth }
    private var appRemote: SPTAppRemote? { rebuildIfNeeded(); return _remote }

    /// (Re)creates the OAuth client and App Remote when the Client ID changes.
    private func rebuildIfNeeded() {
        let id = clientID
        guard id != builtFor || (id != nil && _oauth == nil) else { return }
        if builtFor != nil, builtFor != id { Keychain.delete("spotify.tokens"); cachedSongs = nil }
        if _remote?.isConnected == true { _remote?.disconnect() }
        builtFor = id
        _oauth = id.map(makeOAuth)
        _remote = id.map(makeRemote)
    }

    private func makeOAuth(_ id: String) -> OAuthPKCE {
        let x: String? = id
        return x.map {
        OAuthPKCE(.init(authorize: URL(string: "https://accounts.spotify.com/authorize")!,
                        token: URL(string: "https://accounts.spotify.com/api/token")!,
                        clientID: $0, redirectURI: Self.redirectURI, callbackScheme: "ipodmusic",
                        scopes: ["user-library-read", "playlist-read-private", "playlist-read-collaborative",
                                 "user-follow-read", "user-read-playback-state", "user-modify-playback-state",
                                 "user-read-currently-playing", "app-remote-control"]),
                  keychainKey: "spotify.tokens")
        }!
    }

    private func makeRemote(_ id: String) -> SPTAppRemote {
        let x: String? = id
        return x.map {
        let cfg = SPTConfiguration(clientID: $0, redirectURL: URL(string: Self.redirectURI)!)
        let r = SPTAppRemote(configuration: cfg, logLevel: .error)
        r.delegate = self
        return r
        }!
    }

    func testConnection() async throws -> String {
        let me = try await get("me")
        let pl = try await get("me/playlists", ["limit": "1"])
        let name = me["display_name"] as? String ?? "you"
        let total = pl["total"] as? Int ?? 0
        let first = ((pl["items"] as? [[String: Any]])?.first?["name"] as? String)
        return "Connected as \(name). \(total) playlist\(total == 1 ? "" : "s")" + (first.map { ". First: “\($0)”" } ?? ".")
    }

    // MARK: Library

    var setupProblem: [String]? {
        if clientID == nil { return ["Spotify Not Set Up", "Go to Settings ▸", "Set Up Spotify"] }
        return nil
    }
    var isSignedIn: Bool { oauth?.isSignedIn ?? false }

    func signIn() async throws {
        guard let oauth else { throw SourceError.notConfigured("Spotify") }
        try await oauth.signIn()
    }

    func signOut() {
        oauth?.signOut()
        if appRemote?.isConnected == true { appRemote?.disconnect() }
        cachedSongs = nil
    }

    private func token() async throws -> String {
        guard let oauth else { throw SourceError.notConfigured("Spotify") }
        return try await oauth.accessToken()
    }

    private func get(_ path: String, _ q: [String: String] = [:]) async throws -> [String: Any] {
        try await WebJSON.get(api.appendingPathComponent(path).adding(q), token: try await token())
    }

    /// Follows `next` links of a paging object found at `key` (or the root).
    private func pages(_ path: String, _ q: [String: String], key: String? = nil, max: Int = 20) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var page = try await get(path, q)
        for _ in 0..<max {
            let obj = key.flatMap { page[$0] as? [String: Any] } ?? page
            out += (obj["items"] as? [[String: Any]]) ?? []
            guard let n = obj["next"] as? String, let u = URL(string: n) else { break }
            page = try await WebJSON.get(u, token: try await token())
        }
        return out
    }

    private var cachedSongs: [RemoteTrack]?

    func allSongs() async throws -> [RemoteTrack] {
        if let c = cachedSongs { return c }
        let items = try await pages("me/tracks", ["limit": "50"], max: 40)
        let t = items.compactMap { Self.track($0["track"] as? [String: Any]) }
        cachedSongs = t
        return t
    }

    func rows(for spec: ScreenSpec) async throws -> [Row] {
        switch spec {
        case .playlists:
            let items = try await pages("me/playlists", ["limit": "50"])
            return items.compactMap { p in
                guard let id = p["id"] as? String, let name = p["name"] as? String else { return nil }
                return Row(title: name, chevron: true, action: .push(.node(title: name, ref: "playlist:\(id)")))
            }
        case .artists:
            let items = try await pages("me/following", ["type": "artist", "limit": "50"], key: "artists")
            return items.compactMap { a in
                guard let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
                return Row(title: name, chevron: true, action: .push(.node(title: name, ref: "artist:\(id)")))
            }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .albums, .recentlyAdded:
            let items = try await pages("me/albums", ["limit": "50"])
            return items.compactMap { albumRow($0["album"] as? [String: Any]) }
        case .songs:
            return songRows(try await allSongs(), context: nil)
        case .node(_, let ref):
            return try await nodeRows(ref)
        case .searchResults(let term):
            return try await search(term)
        case .preset(_, let rows):
            return rows
        default:
            return []
        }
    }

    private func nodeRows(_ ref: String) async throws -> [Row] {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        let (type, id) = (parts[0], parts[1])
        switch type {
        case "playlist":
            let ctx = "spotify:playlist:\(id)"
            do {
                let items = try await pages("playlists/\(id)/items", ["limit": "50"])
                let tracks = items.compactMap { Self.track(($0["item"] ?? $0["track"]) as? [String: Any]) }
                return songRows(tracks, context: ctx)
            } catch SourceError.http(403, _) {
                // Spotify only lists tracks of playlists you own or collaborate on (Feb 2026 rules).
                return [Row(title: "Play Playlist", action: .play(.remote([], context: ctx), 0)),
                        Row(title: "Spotify hides the", centered: true, info: true),
                        Row(title: "songs of playlists", centered: true, info: true),
                        Row(title: "you don't own", centered: true, info: true)]
            }
        case "artist":
            let items = try await pages("artists/\(id)/albums", ["include_groups": "album,single", "limit": "50"], max: 4)
            var rows = [Row(title: "Play Artist", action: .play(.remote([], context: "spotify:artist:\(id)"), 0))]
            rows += items.compactMap(albumRow)
            return rows
        case "album":
            let album = try await get("albums/\(id)")
            var items = ((album["tracks"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            var next = (album["tracks"] as? [String: Any])?["next"] as? String
            while let n = next, let u = URL(string: n), items.count < 500 {
                let p = try await WebJSON.get(u, token: try await token())
                items += (p["items"] as? [[String: Any]]) ?? []
                next = p["next"] as? String
            }
            let tracks = items.compactMap { Self.track($0, album: album) }
            return songRows(tracks, context: "spotify:album:\(id)")
        default:
            return []
        }
    }

    private func search(_ term: String) async throws -> [Row] {
        let r = try await get("search", ["q": term, "type": "track,album,artist,playlist", "limit": "10"])
        func items(_ k: String) -> [[String: Any]] { ((r[k] as? [String: Any])?["items"] as? [[String: Any]]) ?? [] }
        var rows: [Row] = []
        let tracks = items("tracks").compactMap { Self.track($0) }
        if !tracks.isEmpty {
            rows.append(Row(title: "Songs", value: "\(tracks.count)", chevron: true,
                            action: .push(.preset(title: "Songs", rows: songRows(tracks, context: nil)))))
        }
        let albums = items("albums").compactMap(albumRow)
        if !albums.isEmpty {
            rows.append(Row(title: "Albums", value: "\(albums.count)", chevron: true, action: .push(.preset(title: "Albums", rows: albums))))
        }
        let artists = items("artists").compactMap { a -> Row? in
            guard let id = a["id"] as? String, let n = a["name"] as? String else { return nil }
            return Row(title: n, chevron: true, action: .push(.node(title: n, ref: "artist:\(id)")))
        }
        if !artists.isEmpty {
            rows.append(Row(title: "Artists", value: "\(artists.count)", chevron: true, action: .push(.preset(title: "Artists", rows: artists))))
        }
        let pls = items("playlists").compactMap { p -> Row? in
            guard let id = p["id"] as? String, let n = p["name"] as? String else { return nil }
            return Row(title: n, chevron: true, action: .push(.node(title: n, ref: "playlist:\(id)")))
        }
        if !pls.isEmpty {
            rows.append(Row(title: "Playlists", value: "\(pls.count)", chevron: true, action: .push(.preset(title: "Playlists", rows: pls))))
        }
        if rows.isEmpty { rows = [Row(title: "No Results", centered: true)] }
        return rows
    }

    private func albumRow(_ a: [String: Any]?) -> Row? {
        guard let a, let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
        return Row(title: name, chevron: true, action: .push(.node(title: name, ref: "album:\(id)")))
    }

    private func songRows(_ tracks: [RemoteTrack], context: String?) -> [Row] {
        tracks.enumerated().map { i, t in Row(title: t.title, action: .play(.remote(tracks, context: context), i)) }
    }

    static func track(_ t: [String: Any]?, album: [String: Any]? = nil) -> RemoteTrack? {
        guard let t, (t["type"] as? String ?? "track") == "track",
              let id = t["id"] as? String, let uri = t["uri"] as? String, let name = t["name"] as? String else { return nil }
        let artists = (t["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        let al = (t["album"] as? [String: Any]) ?? album
        let images = (al?["images"] as? [[String: Any]]) ?? []
        // Smallest image that is still ≥ 200 px (they're sorted widest first).
        let img = images.last(where: { ($0["width"] as? Int ?? 0) >= 200 }) ?? images.first
        return RemoteTrack(id: id, uri: uri, title: name, artist: artists, album: al?["name"] as? String ?? "",
                           duration: Double(t["duration_ms"] as? Int ?? 0) / 1000,
                           artworkURL: (img?["url"] as? String).flatMap(URL.init(string:)))
    }

    // MARK: Playback (App Remote + Web API player)

    private(set) var state = RemotePlaybackState()
    private var queue: [RemoteTrack] = []
    private var lastPlayer: (pos: TimeInterval, at: Date, paused: Bool, uri: String, dur: TimeInterval,
                             title: String, artist: String, album: String)?
    private var pending: (tracks: [RemoteTrack], index: Int, context: String?)?
    private var pollCounter = 0
    private var active = false

    private var spotifyInstalled: Bool { UIApplication.shared.canOpenURL(URL(string: "spotify:")!) }

    func play(_ tracks: [RemoteTrack], at index: Int, context: String?) async throws {
        guard let appRemote else { throw SourceError.notConfigured("Spotify") }
        guard spotifyInstalled else { throw SourceError.spotifyMissing }
        active = true
        queue = tracks
        let target = tracks[safe: index]?.uri ?? context ?? ""
        if !appRemote.isConnected {
            appRemote.connectionParameters.accessToken = try? await token()
            appRemote.connect()
            try? await Task.sleep(for: .milliseconds(1500))
        }
        if !appRemote.isConnected {
            // Spotify isn't running: wake it with the official authorize-and-play hand-off.
            // It comes back to ipodmusic://spotify-callback and we finish starting the queue there.
            pending = (tracks, index, context)
            appRemote.authorizeAndPlayURI(target, asRadio: false,
                                          additionalScopes: nil) { _ in }
            return
        }
        try await startQueue(tracks, index: index, context: context)
    }

    private func startQueue(_ tracks: [RemoteTrack], index: Int, context: String?) async throws {
        var body: [String: Any] = [:]
        if let context {
            body["context_uri"] = context
            if !tracks.isEmpty, context.hasPrefix("spotify:playlist:") || context.hasPrefix("spotify:album:") {
                body["offset"] = ["position": index]
            }
        } else {
            let lo = max(0, index - 50), hi = min(tracks.count, lo + 100)
            body["uris"] = tracks[lo..<hi].map(\.uri)
            body["offset"] = ["position": index - lo]
        }
        do {
            var url = api.appendingPathComponent("me/player/play")
            if let dev = try await phoneDevice() { url = url.adding(["device_id": dev]) }
            try await WebJSON.send("PUT", url, token: try await token(), body: body)
        } catch {
            // Fall back to the SDK: plays the track (or the whole context) in the Spotify app.
            guard let appRemote, appRemote.isConnected else { throw error }
            let uri = tracks[safe: index]?.uri ?? context ?? ""
            appRemote.playerAPI?.play(uri, callback: nil)
        }
    }

    private func phoneDevice() async throws -> String? {
        let j = try await get("me/player/devices")
        let devs = (j["devices"] as? [[String: Any]]) ?? []
        let d = devs.first(where: { $0["is_active"] as? Bool == true })
            ?? devs.first(where: { ($0["type"] as? String)?.lowercased() == "smartphone" })
        return d?["id"] as? String
    }

    func handle(url: URL) -> Bool {
        guard url.scheme == "ipodmusic", url.host == "spotify-callback", let appRemote else { return false }
        let params = appRemote.authorizationParameters(from: url)
        if let t = params?[SPTAppRemoteAccessTokenKey] { appRemote.connectionParameters.accessToken = t }
        appRemote.connect()
        return true
    }

    func appBecameActive() {
        guard active, let appRemote, !appRemote.isConnected, isSignedIn else { return }
        Task {
            if appRemote.connectionParameters.accessToken == nil { appRemote.connectionParameters.accessToken = try? await token() }
            appRemote.connect()
        }
    }

    func appWillResignActive() {
        if appRemote?.isConnected == true { appRemote?.disconnect() }
    }

    private func web(_ method: String, _ path: String, _ q: [String: String] = [:]) {
        Task { try? await WebJSON.send(method, api.appendingPathComponent(path).adding(q), token: try await token(), body: nil) }
    }

    private var remote: SPTAppRemotePlayerAPI? { appRemote?.isConnected == true ? appRemote?.playerAPI : nil }

    func togglePlay() {
        let playing = state.isPlaying
        if let r = remote { playing ? r.pause(nil) : r.resume(nil) }
        else { web("PUT", playing ? "me/player/pause" : "me/player/play") }
        state.isPlaying.toggle()
        if var lp = lastPlayer { lp.pos = currentPos(); lp.at = Date(); lp.paused = !state.isPlaying; lastPlayer = lp }
    }

    func next() { if let r = remote { r.skip(toNext: nil) } else { web("POST", "me/player/next") } }

    func previous() {
        if currentPos() > 3 { seek(to: 0); return }
        if let r = remote { r.skip(toPrevious: nil) } else { web("POST", "me/player/previous") }
    }

    func seek(to t: TimeInterval) {
        let ms = Int(max(0, t) * 1000)
        if let r = remote { r.seek(toPosition: ms, callback: nil) } else { web("PUT", "me/player/seek", ["position_ms": "\(ms)"]) }
        if var lp = lastPlayer { lp.pos = t; lp.at = Date(); lastPlayer = lp }
        state.time = t
    }

    func setModes(shuffle: Bool, repeatMode: RepeatSetting) {
        guard active else { return }
        let rm: SPTAppRemotePlaybackOptionsRepeatMode = repeatMode == .one ? .track : (repeatMode == .all ? .context : .off)
        if let r = remote {
            r.setShuffle(shuffle, callback: nil)
            r.setRepeatMode(rm, callback: nil)
        } else {
            web("PUT", "me/player/shuffle", ["state": shuffle ? "true" : "false"])
            web("PUT", "me/player/repeat", ["state": repeatMode == .one ? "track" : (repeatMode == .all ? "context" : "off")])
        }
    }

    private func currentPos() -> TimeInterval {
        guard let lp = lastPlayer else { return 0 }
        return lp.paused ? lp.pos : min(lp.dur, lp.pos + Date().timeIntervalSince(lp.at))
    }

    func tick() {
        guard active else { return }
        pollCounter += 1
        if remote == nil, isSignedIn, pollCounter % 12 == 0 { Task { await pollWeb() } }
        guard let lp = lastPlayer else { return }
        state.hasItem = true
        state.title = lp.title; state.artist = lp.artist; state.album = lp.album
        state.duration = lp.dur
        state.time = currentPos()
        state.isPlaying = !lp.paused
        if let i = queue.firstIndex(where: { $0.uri == lp.uri }) {
            state.index = i; state.count = queue.count; state.artworkURL = queue[i].artworkURL
        } else {
            state.index = 0; state.count = max(1, queue.count)
            state.artworkURL = artworkCache[lp.uri]
            if artworkCache[lp.uri] == nil { fetchArtwork(lp.uri) }
        }
    }

    private var artworkCache: [String: URL] = [:]
    private var artworkLoading: Set<String> = []
    private func fetchArtwork(_ uri: String) {
        guard uri.hasPrefix("spotify:track:"), !artworkLoading.contains(uri) else { return }
        artworkLoading.insert(uri)
        Task {
            let id = String(uri.dropFirst("spotify:track:".count))
            if let j = try? await get("tracks/\(id)"), let t = Self.track(j), let u = t.artworkURL { artworkCache[uri] = u }
        }
    }

    private func pollWeb() async {
        guard let j = try? await get("me/player"), let item = j["item"] as? [String: Any], let t = Self.track(item) else { return }
        let pos = Double(j["progress_ms"] as? Int ?? 0) / 1000
        lastPlayer = (pos, Date(), !(j["is_playing"] as? Bool ?? false), t.uri, t.duration, t.title, t.artist, t.album)
        if artworkCache[t.uri] == nil, let u = t.artworkURL { artworkCache[t.uri] = u }
    }

    fileprivate func apply(_ s: SPTAppRemotePlayerState) {
        let tr = s.track
        lastPlayer = (Double(s.playbackPosition) / 1000, Date(), s.isPaused, tr.uri, Double(tr.duration) / 1000,
                      tr.name, tr.artist.name, tr.album.name)
    }

    fileprivate func didConnect() {
        guard let appRemote else { return }
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
        appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
            guard let s = result as? SPTAppRemotePlayerState else { return }
            MainActor.assumeIsolated { self?.apply(s) }
        }
        if let p = pending {
            pending = nil
            Task { try? await startQueue(p.tracks, index: p.index, context: p.context) }
        }
    }
}

extension SpotifyService: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        MainActor.assumeIsolated { didConnect() }
    }
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {}
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {}
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        MainActor.assumeIsolated { apply(playerState) }
    }
}
