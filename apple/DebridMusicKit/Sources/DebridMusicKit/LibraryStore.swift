import Foundation

/// The catalogue as this device last saw it, plus the shared state.
///
/// Kept as a plain JSON snapshot rather than a SwiftData graph: the PC owns this data and
/// replaces it wholesale on every sync, so there is nothing to merge, migrate or reconcile —
/// a persistent store would only add ceremony around a file that gets overwritten.
public struct LibrarySnapshot: Codable, Sendable {
    public var catalog: Catalog
    public var etag: String?
    public var syncedAt: Date?

    public init(catalog: Catalog = Catalog(), etag: String? = nil, syncedAt: Date? = nil) {
        self.catalog = catalog
        self.etag = etag
        self.syncedAt = syncedAt
    }
}

public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case failed(String)
}

@MainActor
@Observable
public final class LibraryStore {
    public private(set) var albums: [Album] = []
    public private(set) var artists: [Artist] = []
    public private(set) var tracks: [Track] = []
    public private(set) var status: SyncStatus = .idle
    public private(set) var syncedAt: Date?

    // Shared state
    public private(set) var favoriteTracks: Set<String> = []
    public private(set) var favoriteAlbums: Set<String> = []
    public private(set) var playlists: [Playlist] = []
    public private(set) var plays: [String: PlayStat] = [:]
    public private(set) var remoteProgress: PlaybackProgress?

    private var tracksByAlbum: [String: [Track]] = [:]
    private var trackById: [String: Track] = [:]
    private var albumById: [String: Album] = [:]
    private var etag: String?
    private var stateRev: Int64 = 0

    private let api: APIClient
    private let cacheURL: URL
    private let deviceId: String
    private let deviceName: String

    public init(
        api: APIClient = APIClient(),
        cacheDirectory: URL? = nil,
        deviceId: String = ServerIdentity.deviceId,
        deviceName: String = ServerIdentity.deviceName
    ) {
        self.api = api
        self.deviceId = deviceId
        self.deviceName = deviceName
        let directory = cacheDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("DebridMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.cacheURL = directory.appendingPathComponent("library.json")
        loadCache()
    }

    // ── Reading ──────────────────────────────────────────────────────────────

    public func tracks(ofAlbum albumId: String) -> [Track] {
        (tracksByAlbum[albumId] ?? []).sorted {
            ($0.discNo, $0.trackNo, $0.title) < ($1.discNo, $1.trackNo, $1.title)
        }
    }

    public func track(_ id: String) -> Track? { trackById[id] }
    public func album(_ id: String) -> Album? { albumById[id] }

    public func albums(ofArtist artistId: String) -> [Album] {
        albums.filter { $0.artistId == artistId }
            .sorted { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }
    }

    /// Newest first — the "recently added" row.
    public var recentlyAdded: [Album] {
        albums.sorted { $0.addedMs > $1.addedMs }
    }

    public var recentlyPlayed: [Track] {
        plays.sorted { $0.value.lastPlayedMs > $1.value.lastPlayedMs }
            .compactMap { trackById[$0.key] }
    }

    /// Local, instant search. The PC has `/api/search` too, but the whole catalogue is already
    /// here — a round trip per keystroke would be slower and would stop working offline.
    public func search(_ query: String) -> SearchResult {
        let needle = Self.searchKey(query)
        guard !needle.isEmpty else { return SearchResult() }
        func matches(_ value: String) -> Bool { Self.searchKey(value).contains(needle) }
        return SearchResult(
            artists: artists.filter { matches($0.name) },
            albums: albums.filter { matches($0.title) || matches($0.artistName) },
            tracks: tracks.filter { matches($0.title) || matches($0.artistName) }.prefix(60).map { $0 }
        )
    }

    /// Pure text folding — nonisolated so it can be used off the main actor (and tested without
    /// hopping to it).
    nonisolated static func searchKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    // ── Syncing ──────────────────────────────────────────────────────────────

    public func sync(from endpoint: ServerEndpoint) async {
        status = .syncing
        do {
            if let result = try await api.catalog(from: endpoint, etag: etag) {
                apply(result.catalog)
                etag = result.etag
                syncedAt = Date()
                saveCache()
            } else {
                // 304 — what we already have is current.
                syncedAt = Date()
            }
            await syncState(from: endpoint)
            status = .idle
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    public func syncState(from endpoint: ServerEndpoint) async {
        guard let state = try? await api.state(from: endpoint, since: stateRev) else { return }
        stateRev = state.rev
        remoteProgress = state.progress
        // `unchanged` means only the position moved; the rest is not in the payload and must not
        // be read as "everything was cleared".
        guard state.unchanged != true else { return }
        favoriteTracks = Set(state.favoriteTracks)
        favoriteAlbums = Set(state.favoriteAlbums)
        playlists = state.activePlaylists
        plays = state.plays
    }

    // ── Writing (goes to the PC, which is the single source of truth) ─────────

    public func isFavorite(track id: String) -> Bool { favoriteTracks.contains(id) }
    public func isFavorite(album id: String) -> Bool { favoriteAlbums.contains(id) }

    public func toggleFavorite(track id: String, on endpoint: ServerEndpoint?) async {
        let turningOn = !favoriteTracks.contains(id)
        // Move the UI first: a heart that waits for a network round trip feels broken.
        if turningOn { favoriteTracks.insert(id) } else { favoriteTracks.remove(id) }
        await push([.favorite(track: id, on: turningOn)], to: endpoint)
    }

    public func toggleFavorite(album id: String, on endpoint: ServerEndpoint?) async {
        let turningOn = !favoriteAlbums.contains(id)
        if turningOn { favoriteAlbums.insert(id) } else { favoriteAlbums.remove(id) }
        await push([.favorite(album: id, on: turningOn)], to: endpoint)
    }

    public func createPlaylist(named name: String, trackIds: [String] = [], on endpoint: ServerEndpoint?) async {
        let id = UUID().uuidString
        let now = StateOp.now
        playlists.append(Playlist(id: id, name: name, trackIds: trackIds, updatedAt: now, deletedAt: nil))
        await push([.createPlaylist(id: id, name: name, trackIds: trackIds, at: now)], to: endpoint)
    }

    public func addToPlaylist(_ playlistId: String, trackIds: [String], on endpoint: ServerEndpoint?) async {
        let now = StateOp.now
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            let existing = playlists[index]
            playlists[index] = Playlist(
                id: existing.id, name: existing.name,
                trackIds: existing.trackIds + trackIds, updatedAt: now, deletedAt: nil
            )
        }
        await push([.addToPlaylist(id: playlistId, trackIds: trackIds, at: now)], to: endpoint)
    }

    public func deletePlaylist(_ playlistId: String, on endpoint: ServerEndpoint?) async {
        playlists.removeAll { $0.id == playlistId }
        await push([.deletePlaylist(id: playlistId)], to: endpoint)
    }

    public func reportPlayed(_ trackId: String, to endpoint: ServerEndpoint?) async {
        await push([.played(trackId: trackId)], to: endpoint)
    }

    public func reportProgress(
        trackId: String, positionMs: Int64, playing: Bool,
        queue: [String], index: Int, to endpoint: ServerEndpoint?
    ) async {
        await push([.progress(
            trackId: trackId, positionMs: positionMs, playing: playing, queue: queue, index: index
        )], to: endpoint)
    }

    private func push(_ ops: [StateOp], to endpoint: ServerEndpoint?) async {
        guard let endpoint else { return }
        // Best-effort. A lost favourite is a nuisance; an error dialog over it is worse, and the
        // next full sync brings the PC's version back anyway.
        _ = try? await api.pushOps(ops, deviceId: deviceId, deviceName: deviceName, to: endpoint)
    }

    // ── Cache ────────────────────────────────────────────────────────────────

    private func apply(_ catalog: Catalog) {
        albums = catalog.albums.sorted { $0.title.lowercased() < $1.title.lowercased() }
        artists = catalog.artists
        tracks = catalog.tracks
        albumById = Dictionary(catalog.albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        trackById = Dictionary(catalog.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        tracksByAlbum = Dictionary(grouping: catalog.tracks, by: \.albumId)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) else { return }
        apply(snapshot.catalog)
        etag = snapshot.etag
        syncedAt = snapshot.syncedAt
    }

    private func saveCache() {
        let snapshot = LibrarySnapshot(
            catalog: Catalog(artists: artists, albums: albums, tracks: tracks, generatedAt: 0),
            etag: etag,
            syncedAt: syncedAt
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case APIError.unauthorized: return "Niet meer gekoppeld — koppel opnieuw met je pc."
        case APIError.http(let code): return "De pc antwoordde met \(code)."
        default: return "Geen verbinding met je pc."
        }
    }
}

/// Who this device says it is, when it writes to the shared state.
public enum ServerIdentity {
    public static let deviceId: String = {
        let key = "debridmusic.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    public static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return ProcessInfo.processInfo.hostName.components(separatedBy: ".").first ?? "iPad"
        #endif
    }
}
