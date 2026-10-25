import SwiftUI
import MusicKit

struct DemoSong: Identifiable, Hashable {
    let id = UUID()
    let title: String, artist: String, album: String
    let duration: TimeInterval
    let hue: Double
}

enum QueueSource {
    case songs([Song])
    case tracks([Track])
    case demo([DemoSong])
    /// Spotify / YouTube tracks; `context` is a Spotify playlist/album/artist URI when there is one.
    case remote([RemoteTrack], context: String?)

    var count: Int {
        switch self {
        case .songs(let s): return s.count; case .tracks(let t): return t.count; case .demo(let d): return d.count
        case .remote(let r, _): return r.count
        }
    }
}

enum SettingKey { case shuffle, repeatMode, clicker, haptics, backlight, albumArt, theme, demo, autoNowPlaying, reset }

indirect enum ScreenSpec {
    case main
    case playlists, playlist(Playlist)
    case artists, artist(Artist), artistSongs(Artist)
    case albums, album(Album)
    case songs
    case genres, genre(Genre)
    case recentlyAdded
    case search, searchResults(String)
    case settings, about
    case nowPlaying
    case preset(title: String, rows: [Row])
    case demoList(title: String, kind: DemoKind)
    /// A Spotify/YouTube item (playlist, album, artist, channel…) the active source knows how to open.
    case node(title: String, ref: String)
    case source

    var title: String {
        switch self {
        case .main: return "iPod"
        case .playlists: return "Playlists"
        case .playlist(let p): return p.name
        case .artists: return "Artists"
        case .artist(let a): return a.name
        case .artistSongs(let a): return a.name
        case .albums: return "Albums"
        case .album(let a): return a.title
        case .songs: return "Songs"
        case .genres: return "Genres"
        case .genre(let g): return g.name
        case .recentlyAdded: return "Recently Added"
        case .search: return "Search"
        case .searchResults: return "Results"
        case .settings: return "Settings"
        case .about: return "About"
        case .nowPlaying: return "Now Playing"
        case .preset(let t, _): return t
        case .demoList(let t, _): return t
        case .node(let t, _): return t
        case .source: return "Source"
        }
    }

    var isNowPlaying: Bool { if case .nowPlaying = self { return true }; return false }
    var isSettings: Bool { if case .settings = self { return true }; return false }
    var isMain: Bool { if case .main = self { return true }; return false }
}

enum DemoKind { case playlists, artists, albums, songs, genres, recent, playlist(Int), album(Int) }

enum RowAction {
    case push(ScreenSpec)
    case play(QueueSource, Int)
    case shuffleAll
    case nowPlaying
    case toggle(SettingKey)
    case searchInput
    case openSystemSettings
    case setSource(MusicSourceKind)
    case signIn
    case signOut
    case openURL(URL)
    case openSetup(MusicSourceKind)
    case back
    case none
}

struct Row: Identifiable {
    let id = UUID()
    var title: String
    var value: String? = nil
    var chevron: Bool = false
    var action: RowAction = .none
    var centered: Bool = false
    /// Info rows (About screen) are never highlighted, like data-action=info on the web iPod.
    var info: Bool = false
}

enum DemoData {
    static let songs: [DemoSong] = [
        DemoSong(title: "Midnight Drive (Demo)", artist: "Demo Artist", album: "Night Roads (Demo)", duration: 214, hue: 0.58),
        DemoSong(title: "Paper Planes (Demo)", artist: "The Samples", album: "Sky Sketches (Demo)", duration: 187, hue: 0.08),
        DemoSong(title: "Glass Harbor (Demo)", artist: "Demo Artist", album: "Night Roads (Demo)", duration: 241, hue: 0.62),
        DemoSong(title: "Neon Rain (Demo)", artist: "Placeholder", album: "City Lights (Demo)", duration: 199, hue: 0.83),
        DemoSong(title: "Slow Bloom (Demo)", artist: "The Samples", album: "Sky Sketches (Demo)", duration: 263, hue: 0.33),
        DemoSong(title: "Static Hearts (Demo)", artist: "Placeholder", album: "City Lights (Demo)", duration: 176, hue: 0.95),
        DemoSong(title: "Northern Line (Demo)", artist: "Test Pattern", album: "Signals (Demo)", duration: 225, hue: 0.47),
        DemoSong(title: "Velvet Tape (Demo)", artist: "Test Pattern", album: "Signals (Demo)", duration: 208, hue: 0.12),
        DemoSong(title: "Afterglow (Demo)", artist: "Demo Artist", album: "Night Roads (Demo)", duration: 252, hue: 0.70),
        DemoSong(title: "Low Tide (Demo)", artist: "The Samples", album: "Sky Sketches (Demo)", duration: 194, hue: 0.52),
        DemoSong(title: "Copper Sun (Demo)", artist: "Placeholder", album: "City Lights (Demo)", duration: 230, hue: 0.05),
        DemoSong(title: "Wireframe (Demo)", artist: "Test Pattern", album: "Signals (Demo)", duration: 181, hue: 0.40),
    ]
    static let playlists = ["Road Trip (Demo)", "Chill Evenings (Demo)", "Workout (Demo)", "Favourites (Demo)", "Replay 2026 (Demo)"]
    static let artists = ["Demo Artist", "Placeholder", "Test Pattern", "The Samples"]
    static let albums = ["City Lights (Demo)", "Night Roads (Demo)", "Signals (Demo)", "Sky Sketches (Demo)"]
    static let genres = ["Alternative (Demo)", "Electronic (Demo)", "Pop (Demo)", "Rock (Demo)"]
}
