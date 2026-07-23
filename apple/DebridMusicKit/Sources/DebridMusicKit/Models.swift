import Foundation

/// The library as the PC serves it.
///
/// These mirror `desktop/lib/lan/dtos.dart` field for field, which in turn mirrors the Kotlin
/// server's `Dtos.kt`. One shape, three clients — so a change to the wire format is a change in
/// one place and a compile error in the others, rather than a silent mismatch at runtime.
public struct Artist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let artworkRef: String?
    public let albumCount: Int

    public init(id: String, name: String, artworkRef: String? = nil, albumCount: Int = 0) {
        self.id = id
        self.name = name
        self.artworkRef = artworkRef
        self.albumCount = albumCount
    }
}

public struct Album: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let artistId: String
    public let artistName: String
    public let title: String
    public let year: Int?
    public let artworkRef: String?
    public let trackCount: Int
    /// Which pressing, when the library holds more than one of the same record.
    public let edition: String?
    public let isSingle: Bool
    public let addedMs: Int64

    public init(
        id: String, artistId: String, artistName: String, title: String,
        year: Int? = nil, artworkRef: String? = nil, trackCount: Int = 0,
        edition: String? = nil, isSingle: Bool = false, addedMs: Int64 = 0
    ) {
        self.id = id
        self.artistId = artistId
        self.artistName = artistName
        self.title = title
        self.year = year
        self.artworkRef = artworkRef
        self.trackCount = trackCount
        self.edition = edition
        self.isSingle = isSingle
        self.addedMs = addedMs
    }

    /// "Dummy" or "Dummy · 16 nummers" — the edition only shows when there is one to tell apart.
    public var displayTitle: String {
        guard let edition, !edition.isEmpty else { return title }
        return "\(title) · \(edition)"
    }
}

public struct Track: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let albumId: String
    public let artistId: String
    public let title: String
    public let artistName: String
    public let albumTitle: String
    public let trackNo: Int
    public let discNo: Int
    public let durationMs: Int64
    public let bitrate: Int?
    public let sampleRate: Int?
    public let bitsPerSample: Int?
    public let lossless: Bool
    public let sizeBytes: Int64
    public let year: Int?
    public let genre: String?
    public let mime: String?
    public let streamPath: String
    public let artworkRef: String?
    public let ext: String
    public let addedMs: Int64

    public var duration: TimeInterval { Double(durationMs) / 1000 }

    /// "FLAC 24/96" — what the badge shows. Nil when the file didn't say.
    public var qualityLabel: String? {
        guard lossless else { return ext.uppercased() }
        let format = ext.uppercased()
        guard let rate = sampleRate else { return format }
        let khz = Double(rate) / 1000
        let khzText = khz == khz.rounded() ? String(Int(khz)) : String(format: "%.1f", khz)
        guard let bits = bitsPerSample else { return "\(format) \(khzText) kHz" }
        return "\(format) \(bits)/\(khzText)"
    }

    /// True when this is beyond what Sonos accepts — it plays FLAC to 24 bit but only to 48 kHz,
    /// and *skips* anything above rather than downsampling it.
    public var exceedsSonosLimit: Bool { (sampleRate ?? 0) > 48_000 }
}

public struct Catalog: Codable, Sendable {
    public let artists: [Artist]
    public let albums: [Album]
    public let tracks: [Track]
    public let generatedAt: Int64

    public init(artists: [Artist] = [], albums: [Album] = [], tracks: [Track] = [], generatedAt: Int64 = 0) {
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
        self.generatedAt = generatedAt
    }
}

public struct SearchResult: Codable, Sendable {
    public let artists: [Artist]
    public let albums: [Album]
    public let tracks: [Track]

    public init(artists: [Artist] = [], albums: [Album] = [], tracks: [Track] = []) {
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
    }
}

public struct ServerHealth: Codable, Sendable {
    public let status: String
    public let name: String
    public let version: String
    public let deviceName: String?
    public let trackCount: Int?
    public let albumCount: Int?
}

public struct PairResponse: Codable, Sendable {
    public let token: String
    public let name: String?
    public let trackCount: Int?
}

// ── Shared state ─────────────────────────────────────────────────────────────

public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let trackIds: [String]
    public let updatedAt: Int64
    /// Non-nil means it was deleted elsewhere. A tombstone, not a playlist — never shown.
    public let deletedAt: Int64?

    public var isDeleted: Bool { deletedAt != nil }
}

public struct PlayStat: Codable, Hashable, Sendable {
    public let count: Int
    public let lastPlayedMs: Int64
}

public struct PlaybackProgress: Codable, Hashable, Sendable {
    public let trackId: String
    public let positionMs: Int64
    public let queue: [String]
    public let index: Int
    public let playing: Bool
    public let updatedAt: Int64
    public let deviceId: String
    public let deviceName: String
}

public struct SharedState: Codable, Sendable {
    public let rev: Int64
    public let progressRev: Int64
    public let unchanged: Bool?
    public let favoriteTracks: [String]
    public let favoriteAlbums: [String]
    public let playlists: [Playlist]
    public let plays: [String: PlayStat]
    public let progress: PlaybackProgress?

    /// Only the live ones — tombstones exist so a delete propagates, not to be listed.
    public var activePlaylists: [Playlist] { playlists.filter { !$0.isDeleted } }
}
