import Foundation
import MusicKit

/// Builds the rows for every iPod menu screen, from the user's Apple Music
/// library (MusicKit) or from demo content.
@MainActor
final class Library {
    var cachedSongs: [Song]? = nil

    func rows(for spec: ScreenSpec, demo: Bool) async throws -> [Row] {
        if demo { return demoRows(spec) }
        switch spec {
        case .playlists:
            var req = MusicLibraryRequest<Playlist>()
            req.sort(by: \.name, ascending: true)
            let items = try await all(req)
            return items.map { Row(title: $0.name, chevron: true, action: .push(.playlist($0))) }

        case .playlist(let p):
            let full = try await p.with([.tracks])
            let tracks = Array(full.tracks ?? [])
            return trackRows(tracks)

        case .artists:
            var req = MusicLibraryRequest<Artist>()
            req.sort(by: \.name, ascending: true)
            let items = try await all(req)
            return items.map { Row(title: $0.name, chevron: true, action: .push(.artist($0))) }

        case .artist(let a):
            let full = try await a.with([.albums])
            var rows = [Row(title: "All Songs", chevron: true, action: .push(.artistSongs(a)))]
            rows += (full.albums ?? []).sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
                .map { Row(title: $0.title, chevron: true, action: .push(.album($0))) }
            return rows

        case .artistSongs(let a):
            var req = MusicLibraryRequest<Song>()
            req.filter(matching: \.artistName, equalTo: a.name)
            req.sort(by: \.title, ascending: true)
            let songs = try await all(req)
            return songRows(songs)

        case .albums:
            var req = MusicLibraryRequest<Album>()
            req.sort(by: \.title, ascending: true)
            let items = try await all(req)
            return items.map { Row(title: $0.title, chevron: true, action: .push(.album($0))) }

        case .album(let al):
            let full = try await al.with([.tracks])
            return trackRows(Array(full.tracks ?? []))

        case .songs:
            let songs = try await librarySongs()
            return songRows(songs)

        case .genres:
            var req = MusicLibraryRequest<Genre>()
            req.sort(by: \.name, ascending: true)
            let items = try await all(req)
            return items.map { Row(title: $0.name, chevron: true, action: .push(.genre($0))) }

        case .genre(let g):
            var req = MusicLibraryRequest<Song>()
            req.filter(matching: \.genres, contains: g)
            req.sort(by: \.title, ascending: true)
            return songRows(try await all(req))

        case .recentlyAdded:
            var req = MusicLibraryRequest<Album>()
            req.sort(by: \.libraryAddedDate, ascending: false)
            req.limit = 100
            let resp = try await req.response()
            return resp.items.map { Row(title: $0.title, chevron: true, action: .push(.album($0))) }

        case .searchResults(let term):
            var req = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self, Playlist.self])
            req.limit = 25
            let r = try await req.response()
            var rows: [Row] = []
            if !r.songs.isEmpty {
                rows.append(Row(title: "Songs", value: "\(r.songs.count)", chevron: true,
                                action: .push(.preset(title: "Songs", rows: songRows(Array(r.songs))))))
            }
            if !r.albums.isEmpty {
                rows.append(Row(title: "Albums", value: "\(r.albums.count)", chevron: true,
                                action: .push(.preset(title: "Albums", rows: r.albums.map {
                                    Row(title: "\($0.title) – \($0.artistName)", chevron: true, action: .push(.album($0)))
                                }))))
            }
            if !r.artists.isEmpty {
                rows.append(Row(title: "Artists", value: "\(r.artists.count)", chevron: true,
                                action: .push(.preset(title: "Artists", rows: r.artists.map {
                                    Row(title: $0.name, chevron: true, action: .push(.artist($0)))
                                }))))
            }
            if !r.playlists.isEmpty {
                rows.append(Row(title: "Playlists", value: "\(r.playlists.count)", chevron: true,
                                action: .push(.preset(title: "Playlists", rows: r.playlists.map {
                                    Row(title: $0.name, chevron: true, action: .push(.playlist($0)))
                                }))))
            }
            if rows.isEmpty { rows = [Row(title: "No Results", centered: true)] }
            return rows

        case .preset(_, let rows):
            return rows

        default:
            return []
        }
    }

    func librarySongs() async throws -> [Song] {
        if let c = cachedSongs { return c }
        var req = MusicLibraryRequest<Song>()
        req.sort(by: \.title, ascending: true)
        let s = try await all(req)
        cachedSongs = s
        return s
    }

    private func all<T>(_ req: MusicLibraryRequest<T>) async throws -> [T] where T: MusicLibraryRequestable {
        var r = req
        if r.limit == nil || (r.limit ?? 0) < 1000 { r.limit = 10_000 }
        let resp = try await r.response()
        var items = Array(resp.items)
        var batch = resp.items
        var guardCount = 0
        while batch.hasNextBatch, guardCount < 20, let next = try await batch.nextBatch(limit: 10_000) {
            items += next; batch = next; guardCount += 1
        }
        return items
    }

    private func songRows(_ songs: [Song]) -> [Row] {
        songs.enumerated().map { i, s in Row(title: s.title, action: .play(.songs(songs), i)) }
    }

    private func trackRows(_ tracks: [Track]) -> [Row] {
        tracks.enumerated().map { i, t in Row(title: t.title, action: .play(.tracks(tracks), i)) }
    }

    // MARK: Demo

    private func demoRows(_ spec: ScreenSpec) -> [Row] {
        let songs = DemoData.songs
        switch spec {
        case .playlists:
            return DemoData.playlists.enumerated().map { i, n in
                Row(title: n, chevron: true, action: .push(.demoList(title: n, kind: .playlist(i)))) }
        case .artists:
            return DemoData.artists.map { a in
                let s = songs.filter { $0.artist == a }
                return Row(title: a, chevron: true, action: .push(.preset(title: a, rows: demoSongRows(s))))
            }
        case .albums, .recentlyAdded:
            return DemoData.albums.map { al in
                let s = songs.filter { $0.album == al }
                return Row(title: al, chevron: true, action: .push(.preset(title: al, rows: demoSongRows(s))))
            }
        case .songs:
            return demoSongRows(songs.sorted { $0.title < $1.title })
        case .genres:
            return DemoData.genres.enumerated().map { i, g in
                var gen = SeededGen(seed: UInt64(i + 1))
                let s = Array(songs.shuffled(using: &gen).prefix(6))
                return Row(title: g, chevron: true, action: .push(.preset(title: g, rows: demoSongRows(s))))
            }
        case .demoList(_, let kind):
            if case .playlist(let i) = kind {
                var gen = SeededGen(seed: UInt64(i + 11))
                let s = Array(songs.shuffled(using: &gen).prefix(8 + i))
                return demoSongRows(s)
            }
            return demoSongRows(songs)
        case .searchResults(let term):
            let s = songs.filter { $0.title.localizedCaseInsensitiveContains(term) || $0.artist.localizedCaseInsensitiveContains(term) }
            return s.isEmpty ? [Row(title: "No Results", centered: true)] : demoSongRows(s)
        case .preset(_, let rows):
            return rows
        default:
            return []
        }
    }

    private func demoSongRows(_ s: [DemoSong]) -> [Row] {
        s.enumerated().map { i, x in Row(title: x.title, action: .play(.demo(s), i)) }
    }
}

struct SeededGen: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
