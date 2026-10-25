import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Source selection

/// Where the iPod gets its music from. Picked in Settings ▸ Source.
enum MusicSourceKind: String, CaseIterable, Identifiable {
    case appleMusic, spotify, youtubeMusic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .youtubeMusic: return "YouTube Music"
        }
    }
    /// Short form for the narrow LCD value column.
    var short: String {
        switch self {
        case .appleMusic: return "Apple"
        case .spotify: return "Spotify"
        case .youtubeMusic: return "YouTube"
        }
    }
}

/// A track from a non-Apple source (Spotify track or YouTube video).
struct RemoteTrack: Hashable, Identifiable {
    let id: String              // Spotify track id / YouTube video id
    let uri: String             // spotify:track:… / YouTube video id
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval  // 0 when unknown (YouTube lists)
    let artworkURL: URL?
}

/// What the LCD needs to show for a remote player.
struct RemotePlaybackState {
    var title = "", artist = "", album = ""
    var time: TimeInterval = 0, duration: TimeInterval = 0
    var isPlaying = false
    var index = 0, count = 0
    var artworkURL: URL? = nil
    var hasItem = false
}

/// The library half of a source: builds the rows of every iPod menu screen.
@MainActor
protocol MusicLibraryProvider: AnyObject {
    var kind: MusicSourceKind { get }
    /// nil when the source can be used; otherwise a short reason shown on the LCD.
    var setupProblem: [String]? { get }
    var isSignedIn: Bool { get }
    func signIn() async throws
    func signOut()
    func rows(for spec: ScreenSpec) async throws -> [Row]
    /// Every song, for "Shuffle Songs".
    func allSongs() async throws -> [RemoteTrack]
    /// Setup "Test" step: fetches one playlist and describes the result.
    func testConnection() async throws -> String
}

/// The playback half of a source.
@MainActor
protocol RemotePlayback: AnyObject {
    var state: RemotePlaybackState { get }
    func play(_ tracks: [RemoteTrack], at index: Int, context: String?) async throws
    func togglePlay()
    func next()
    func previous()
    func seek(to t: TimeInterval)
    func setModes(shuffle: Bool, repeatMode: RepeatSetting)
    /// Called ~4×/s by PlayerModel.
    func tick()
}

enum SourceError: LocalizedError {
    case notConfigured(String), notSignedIn, http(Int, String), noDevice, spotifyMissing, message(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured(let s): return "\(s) not set up"
        case .notSignedIn: return "Not signed in"
        case .http(let c, let m): return "Error \(c) \(m)"
        case .noDevice: return "Open Spotify first"
        case .spotifyMissing: return "Install Spotify"
        case .message(let m): return m
        }
    }
}

/// Owns one library + player per source and hands out the active one.
@MainActor @Observable
final class SourceHub {
    let spotify = SpotifyService()
    let youtube = YouTubeService()
    var revision = 0   // bumped when a sign-in state changes so menus rebuild

    func library(for k: MusicSourceKind) -> MusicLibraryProvider? {
        switch k {
        case .appleMusic: return nil   // Apple Music keeps its original MusicKit path (Library.swift)
        case .spotify: return spotify
        case .youtubeMusic: return youtube
        }
    }

    func player(for k: MusicSourceKind) -> RemotePlayback? {
        switch k {
        case .appleMusic: return nil
        case .spotify: return spotify
        case .youtubeMusic: return youtube.player
        }
    }

    func handle(url: URL) -> Bool {
        if spotify.handle(url: url) { revision += 1; return true }
        return false
    }
}

// MARK: - Client IDs entered on the phone

/// Client IDs pasted in the in-app setup. They override Config/Sources.xcconfig at runtime,
/// so setup needs no Xcode and no rebuild. (Client IDs are public identifiers, not secrets;
/// both sources use PKCE, so there is no client secret anywhere.)
enum ClientIDStore {
    private static func key(_ k: MusicSourceKind) -> String { "clientID.\(k.rawValue)" }
    private static func plistKey(_ k: MusicSourceKind) -> String? {
        switch k { case .spotify: return "SpotifyClientID"; case .youtubeMusic: return "GoogleClientID"; case .appleMusic: return nil }
    }
    static func saved(_ k: MusicSourceKind) -> String? {
        let v = UserDefaults.standard.string(forKey: key(k))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty ?? true) ? nil : v
    }
    static func save(_ v: String?, for k: MusicSourceKind) {
        if let v, !v.isEmpty { UserDefaults.standard.set(v, forKey: key(k)) }
        else { UserDefaults.standard.removeObject(forKey: key(k)) }
    }
    static func effective(_ k: MusicSourceKind) -> String? {
        saved(k) ?? plistKey(k).flatMap(AppConfig.string)
    }
    /// Returns the cleaned ID, or nil when it doesn't look right.
    static func validate(_ raw: String, for k: MusicSourceKind) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch k {
        case .spotify:
            let l = s.lowercased()
            return l.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil ? l : nil
        case .youtubeMusic:
            return s.range(of: "^[0-9]+-[A-Za-z0-9_]+\\.apps\\.googleusercontent\\.com$", options: .regularExpression) != nil ? s : nil
        case .appleMusic:
            return nil
        }
    }
}

// MARK: - Config

enum AppConfig {
    /// Reads a non-empty value from Info.plist (filled from Config/Sources.xcconfig).
    static func string(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.hasPrefix("$(") { return nil }
        return t
    }
}

// MARK: - OAuth 2 (Authorization Code + PKCE)

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiry: Date
    var isFresh: Bool { expiry.timeIntervalSinceNow > 60 }
}

@MainActor
final class OAuthPKCE: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Endpoints {
        let authorize: URL
        let token: URL
        let clientID: String
        let redirectURI: String
        let callbackScheme: String
        let scopes: [String]
        var extraAuthParams: [String: String] = [:]
    }

    let ep: Endpoints
    let keychainKey: String
    private(set) var tokens: OAuthTokens?
    private var session: ASWebAuthenticationSession?

    init(_ ep: Endpoints, keychainKey: String) {
        self.ep = ep
        self.keychainKey = keychainKey
        super.init()
        if let d = Keychain.get(keychainKey) { tokens = try? JSONDecoder().decode(OAuthTokens.self, from: d) }
    }

    var isSignedIn: Bool { tokens != nil }

    func signOut() { tokens = nil; Keychain.delete(keychainKey) }

    func signIn() async throws {
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let stateParam = Self.randomString(16)
        var c = URLComponents(url: ep.authorize, resolvingAgainstBaseURL: false)!
        var q = [
            URLQueryItem(name: "client_id", value: ep.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: ep.redirectURI),
            URLQueryItem(name: "scope", value: ep.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: stateParam),
        ]
        q += ep.extraAuthParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        c.queryItems = q
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: ep.callbackScheme) { url, err in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: err ?? SourceError.message("Sign-in cancelled")) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            if !s.start() { cont.resume(throwing: SourceError.message("Couldn't open sign-in")) }
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let e = items.first(where: { $0.name == "error" })?.value { throw SourceError.message(e) }
        guard items.first(where: { $0.name == "state" })?.value == stateParam,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SourceError.message("Sign-in failed")
        }
        try await exchange(["grant_type": "authorization_code", "code": code,
                            "redirect_uri": ep.redirectURI, "client_id": ep.clientID, "code_verifier": verifier])
    }

    /// A valid access token, refreshing it if needed.
    func accessToken() async throws -> String {
        guard let t = tokens else { throw SourceError.notSignedIn }
        if t.isFresh { return t.accessToken }
        guard let r = t.refreshToken else { signOut(); throw SourceError.notSignedIn }
        do {
            try await exchange(["grant_type": "refresh_token", "refresh_token": r, "client_id": ep.clientID])
        } catch {
            signOut(); throw SourceError.notSignedIn
        }
        return tokens!.accessToken
    }

    private func exchange(_ form: [String: String]) async throws {
        var req = URLRequest(url: ep.token)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String else {
            throw SourceError.http(code, "token")
        }
        let expiresIn = (j["expires_in"] as? Double) ?? 3600
        let refresh = (j["refresh_token"] as? String) ?? tokens?.refreshToken ?? form["refresh_token"]
        let t = OAuthTokens(accessToken: access, refreshToken: refresh, expiry: Date().addingTimeInterval(expiresIn))
        tokens = t
        if let d = try? JSONEncoder().encode(t) { Keychain.set(d, for: keychainKey) }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var g = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in chars[Int(g.next() % UInt64(chars.count))] })
    }
}

/// Small JSON-over-HTTPS helper with bearer auth.
@MainActor
enum WebJSON {
    static func get(_ url: URL, token: String) async throws -> [String: Any] {
        try await send("GET", url, token: token, body: nil) ?? [:]
    }

    @discardableResult
    static func send(_ method: String, _ url: URL, token: String, body: [String: Any]?) async throws -> [String: Any]? {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method != "GET" {
            req.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            var msg = ""
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let e = j["error"] as? [String: Any], let m = e["message"] as? String { msg = m }
            throw SourceError.http(code, msg)
        }
        if data.isEmpty { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

extension URL {
    func adding(_ q: [String: String]) -> URL {
        var c = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
}

// MARK: - Keychain

enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.sergebl.iPodMusic",
         kSecAttrAccount as String: key]
    }
    static func get(_ key: String) -> Data? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func set(_ data: Data, for key: String) {
        delete(key)
        var q = base(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ key: String) { SecItemDelete(base(key) as CFDictionary) }
}
