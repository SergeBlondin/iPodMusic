import SwiftUI
import WebKit

/// YouTube Music source, done the legitimate way:
/// - Library: YouTube Data API v3 with Google OAuth (Authorization Code + PKCE, iOS client, read-only scope):
///   your playlists, liked music, subscribed channels, search (music category).
/// - Playback: the official YouTube IFrame Player in a WKWebView, shown on the iPod screen while it plays
///   (YouTube's rules require a visible player of at least 200×200, so it pauses when you leave Now Playing).
/// - "Open in YT Music" hands a playlist over to the YouTube Music app (background play needs YouTube Premium there).
/// There is no official YouTube Music API; nothing here scrapes music.youtube.com or extracts audio streams.
@MainActor
final class YouTubeService: MusicLibraryProvider {
    let kind = MusicSourceKind.youtubeMusic
    let player = YouTubePlayer()
    private let api = URL(string: "https://www.googleapis.com/youtube/v3")!

    /// Pasted in Settings ▸ Set Up YouTube, else Config/Sources.xcconfig.
    var clientID: String? { ClientIDStore.effective(.youtubeMusic) }
    private var builtFor: String?
    private var _oauth: OAuthPKCE?
    private var oauth: OAuthPKCE? {
        let id = clientID
        if id != builtFor || (id != nil && _oauth == nil) {
            if builtFor != nil, builtFor != id { Keychain.delete("youtube.tokens"); cachedLiked = nil }
            builtFor = id
            _oauth = makeOAuth()
        }
        return _oauth
    }

    /// Google iOS clients redirect to the reversed client ID scheme
    /// (com.googleusercontent.apps.<id>:/oauth2redirect). ASWebAuthenticationSession catches that
    /// callback itself when the scheme is passed as callbackURLScheme, so it does not have to be
    /// registered in Info.plist — which is why a pasted ID works without a rebuild.
    private func makeOAuth() -> OAuthPKCE? {
        guard let id = clientID, id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        let scheme = "com.googleusercontent.apps." + id.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return OAuthPKCE(.init(authorize: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                               token: URL(string: "https://oauth2.googleapis.com/token")!,
                               clientID: id, redirectURI: scheme + ":/oauth2redirect", callbackScheme: scheme,
                               scopes: ["https://www.googleapis.com/auth/youtube.readonly"]),
                         keychainKey: "youtube.tokens")
    }

    func testConnection() async throws -> String {
        let j = try await get("playlists", ["part": "snippet", "mine": "true", "maxResults": "1"])
        let total = (j["pageInfo"] as? [String: Any])?["totalResults"] as? Int ?? 0
        let first = ((j["items"] as? [[String: Any]])?.first?["snippet"] as? [String: Any])?["title"] as? String
        return "Connected. \(total) playlist\(total == 1 ? "" : "s")" + (first.map { ". First: “\($0)”" } ?? ".")
    }

    var setupProblem: [String]? {
        if oauth == nil { return ["YouTube Not Set Up", "Go to Settings ▸", "Set Up YouTube"] }
        return nil
    }
    var isSignedIn: Bool { oauth?.isSignedIn ?? false }

    func signIn() async throws {
        guard let oauth else { throw SourceError.notConfigured("YouTube") }
        try await oauth.signIn()
    }

    func signOut() { oauth?.signOut(); cachedLiked = nil }

    private func get(_ path: String, _ q: [String: String]) async throws -> [String: Any] {
        guard let oauth else { throw SourceError.notConfigured("YouTube") }
        return try await WebJSON.get(api.appendingPathComponent(path).adding(q), token: try await oauth.accessToken())
    }

    private func pages(_ path: String, _ q: [String: String], max: Int = 4) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var token: String? = nil
        for _ in 0..<max {
            var qq = q; qq["maxResults"] = "50"
            if let token { qq["pageToken"] = token }
            let j = try await get(path, qq)
            out += (j["items"] as? [[String: Any]]) ?? []
            token = j["nextPageToken"] as? String
            if token == nil { break }
        }
        return out
    }

    private var cachedLiked: [RemoteTrack]?

    /// Liked videos in the Music category — the closest thing to "Liked Music" the Data API exposes.
    func allSongs() async throws -> [RemoteTrack] {
        if let c = cachedLiked { return c }
        let items = try await pages("videos", ["part": "snippet,contentDetails", "myRating": "like"], max: 6)
        let t = items.filter { ($0["snippet"] as? [String: Any])?["categoryId"] as? String == "10" }
            .compactMap { Self.track(id: $0["id"] as? String, snippet: $0["snippet"] as? [String: Any],
                                     iso: ($0["contentDetails"] as? [String: Any])?["duration"] as? String) }
        cachedLiked = t
        return t
    }

    func rows(for spec: ScreenSpec) async throws -> [Row] {
        switch spec {
        case .playlists:
            var rows = [Row(title: "Liked Music", chevron: true, action: .push(.node(title: "Liked Music", ref: "liked")))]
            let items = try await pages("playlists", ["part": "snippet", "mine": "true"])
            rows += items.compactMap { p in
                guard let id = p["id"] as? String, let t = (p["snippet"] as? [String: Any])?["title"] as? String else { return nil }
                return Row(title: t, chevron: true, action: .push(.node(title: t, ref: "playlist:\(id)")))
            }
            return rows
        case .songs:
            return songRows(try await allSongs())
        case .artists:
            let items = try await pages("subscriptions", ["part": "snippet", "mine": "true", "order": "alphabetical"], max: 6)
            return items.compactMap { s in
                guard let sn = s["snippet"] as? [String: Any], let t = sn["title"] as? String,
                      let cid = (sn["resourceId"] as? [String: Any])?["channelId"] as? String else { return nil }
                let name = Self.clean(t)
                return Row(title: name, chevron: true, action: .push(.node(title: name, ref: "channel:\(cid)")))
            }
        case .albums, .recentlyAdded:
            return [Row(title: "Albums aren't", centered: true, info: true),
                    Row(title: "available from the", centered: true, info: true),
                    Row(title: "YouTube API.", centered: true, info: true),
                    Row(title: "Use Playlists.", centered: true, info: true)]
        case .node(_, let ref):
            return try await nodeRows(ref)
        case .searchResults(let term):
            let items = try await get("search", ["part": "snippet", "type": "video", "videoCategoryId": "10",
                                                 "maxResults": "25", "q": term])["items"] as? [[String: Any]] ?? []
            let t = items.compactMap { Self.track(id: ($0["id"] as? [String: Any])?["videoId"] as? String,
                                                  snippet: $0["snippet"] as? [String: Any], iso: nil) }
            return t.isEmpty ? [Row(title: "No Results", centered: true)] : songRows(t)
        case .preset(_, let rows):
            return rows
        default:
            return []
        }
    }

    private func nodeRows(_ ref: String) async throws -> [Row] {
        if ref == "liked" {
            var rows = [Row(title: "Open in YT Music", chevron: true,
                            action: .openURL(URL(string: "https://music.youtube.com/playlist?list=LM")!))]
            rows += songRows(try await allSongs())
            return rows
        }
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        switch parts[0] {
        case "playlist":
            var rows = [Row(title: "Open in YT Music", chevron: true,
                            action: .openURL(URL(string: "https://music.youtube.com/playlist?list=\(parts[1])")!))]
            rows += songRows(try await playlistTracks(parts[1]))
            return rows
        case "channel":
            let j = try await get("channels", ["part": "contentDetails", "id": parts[1]])
            guard let ch = (j["items"] as? [[String: Any]])?.first,
                  let up = ((ch["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: Any])?["uploads"] as? String
            else { return [] }
            return songRows(try await playlistTracks(up, max: 2))
        default:
            return []
        }
    }

    private func playlistTracks(_ id: String, max: Int = 4) async throws -> [RemoteTrack] {
        let items = try await pages("playlistItems", ["part": "snippet", "playlistId": id], max: max)
        return items.compactMap { it in
            let sn = it["snippet"] as? [String: Any]
            let vid = (sn?["resourceId"] as? [String: Any])?["videoId"] as? String
            let t = sn?["title"] as? String ?? ""
            if t == "Deleted video" || t == "Private video" { return nil }
            return Self.track(id: vid, snippet: sn, iso: nil)
        }
    }

    private func songRows(_ t: [RemoteTrack]) -> [Row] {
        t.enumerated().map { i, x in Row(title: x.title, action: .play(.remote(t, context: nil), i)) }
    }

    static func clean(_ s: String) -> String {
        s.hasSuffix(" - Topic") ? String(s.dropLast(8)) : s
    }

    static func track(id: String?, snippet sn: [String: Any]?, iso: String?) -> RemoteTrack? {
        guard let id, let sn, let title = sn["title"] as? String else { return nil }
        let owner = (sn["videoOwnerChannelTitle"] as? String) ?? (sn["channelTitle"] as? String) ?? ""
        let thumbs = sn["thumbnails"] as? [String: Any]
        let th = (thumbs?["medium"] ?? thumbs?["default"]) as? [String: Any]
        return RemoteTrack(id: id, uri: id, title: title.htmlUnescaped, artist: clean(owner), album: "",
                           duration: iso.map(parseISODuration) ?? 0,
                           artworkURL: (th?["url"] as? String).flatMap(URL.init(string:)))
    }

    static func parseISODuration(_ s: String) -> TimeInterval {
        var total = 0.0, num = ""
        for ch in s {
            if ch.isNumber { num.append(ch); continue }
            let v = Double(num) ?? 0; num = ""
            switch ch { case "H": total += v * 3600; case "M": total += v * 60; case "S": total += v; default: break }
        }
        return total
    }
}

extension String {
    var htmlUnescaped: String {
        replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

// MARK: - Official YouTube IFrame player

@MainActor @Observable
final class YouTubePlayer: NSObject, RemotePlayback, WKScriptMessageHandler {
    private(set) var state = RemotePlaybackState()
    private(set) var isVisible = false
    private var queue: [RemoteTrack] = []
    private var ready = false
    private var pendingJS: [String] = []
    private var resumeWhenShown = false
    private var polling = false
    private var active = false

    @ObservationIgnored lazy var webView: WKWebView = {
        let c = WKWebViewConfiguration()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        c.userContentController.add(WeakHandler(self), name: "yt")
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 260, height: 220), configuration: c)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.isScrollEnabled = false
        // YouTube requires the embedding app to identify itself via the Referer: https://<bundle id>.
        let origin = "https://" + (Bundle.main.bundleIdentifier ?? "com.sergebl.ipodmusic").lowercased()
        w.loadHTMLString(Self.html(origin: origin), baseURL: URL(string: origin))
        return w
    }()

    private static func html(origin: String) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function post(m){window.webkit.messageHandlers.yt.postMessage(m);}
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('p',{width:'100%',height:'100%',
            playerVars:{playsinline:1,controls:1,rel:0,modestbranding:1,origin:'\(origin)'},
            events:{
              onReady:function(){post({e:'ready'});},
              onStateChange:function(ev){post({e:'state',s:ev.data});},
              onError:function(ev){post({e:'error',c:ev.data});}
            }});
        }
        function snap(){
          if(!player||!player.getPlayerState) return null;
          var d=player.getVideoData?player.getVideoData():{};
          return JSON.stringify({t:player.getCurrentTime()||0,d:player.getDuration()||0,s:player.getPlayerState(),
            i:player.getPlaylistIndex(),id:d.video_id||'',title:d.title||'',author:d.author||''});
        }
        </script></body></html>
        """
    }

    private func js(_ s: String) {
        _ = webView
        if ready { webView.evaluateJavaScript(s, completionHandler: nil) } else { pendingJS.append(s) }
    }

    func play(_ tracks: [RemoteTrack], at index: Int, context: String?) async throws {
        active = true
        let lo = max(0, index - 100), hi = min(tracks.count, lo + 200)
        queue = Array(tracks[lo..<hi])
        let ids = queue.map { "'\($0.id)'" }.joined(separator: ",")
        state = RemotePlaybackState(title: tracks[safe: index]?.title ?? "", artist: tracks[safe: index]?.artist ?? "",
                                    isPlaying: true, index: index - lo, count: queue.count,
                                    artworkURL: tracks[safe: index]?.artworkURL, hasItem: true)
        js("player.loadPlaylist([\(ids)], \(index - lo), 0);")
        startPolling()
    }

    func togglePlay() {
        guard active else { return }
        js(state.isPlaying ? "player.pauseVideo();" : "player.playVideo();")
        state.isPlaying.toggle()
        resumeWhenShown = false
    }

    func next() { js("player.nextVideo();") }
    func previous() { if state.time > 3 { seek(to: 0) } else { js("player.previousVideo();") } }
    func seek(to t: TimeInterval) { js("player.seekTo(\(Int(t)), true);"); state.time = t }

    func setModes(shuffle: Bool, repeatMode: RepeatSetting) {
        js("player.setShuffle(\(shuffle)); player.setLoop(\(repeatMode == .all));")
    }

    func tick() {}

    /// The player view tells us when it is on screen; YouTube must not play in a hidden player.
    func setVisible(_ v: Bool) {
        isVisible = v
        if !v, state.isPlaying { js("player.pauseVideo();"); state.isPlaying = false; resumeWhenShown = true }
        if v, resumeWhenShown { resumeWhenShown = false; js("player.playVideo();"); state.isPlaying = true }
    }

    private func startPolling() {
        guard !polling else { return }
        polling = true
        Task {
            while polling {
                try? await Task.sleep(for: .milliseconds(400))
                await poll()
            }
        }
    }

    private func poll() async {
        guard ready, let s = try? await webView.evaluateJavaScript("snap()") as? String,
              let j = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return }
        let i = j["i"] as? Int ?? 0
        let tr = queue[safe: i]
        state.hasItem = true
        state.time = j["t"] as? Double ?? 0
        state.duration = j["d"] as? Double ?? 0
        let ps = j["s"] as? Int ?? -1
        if ps == 1 { state.isPlaying = true } else if ps == 2 || ps == 0 { state.isPlaying = false }
        state.index = max(0, i); state.count = queue.count
        let title = j["title"] as? String ?? ""
        state.title = title.isEmpty ? (tr?.title ?? "") : title
        let author = j["author"] as? String ?? ""
        state.artist = author.isEmpty ? (tr?.artist ?? "") : YouTubeService.clean(author)
        state.artworkURL = tr?.artworkURL
    }

    nonisolated func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = m.body as? [String: Any], let e = body["e"] as? String else { return }
            switch e {
            case "ready":
                ready = true
                let q = pendingJS; pendingJS = []
                for s in q { webView.evaluateJavaScript(s, completionHandler: nil) }
            case "error":
                // 101/150: the owner doesn't allow embedding — skip it like a missing song.
                js("player.nextVideo();")
            default: break
            }
        }
    }
}

/// Avoids a retain cycle between WKUserContentController and the player.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

/// Shows the shared player WKWebView. Placed over the iPod screen during YouTube Now Playing.
struct YouTubePlayerView: UIViewRepresentable {
    let player: YouTubePlayer
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        let w = player.webView
        w.removeFromSuperview()
        w.frame = host.bounds
        w.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(w)
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
