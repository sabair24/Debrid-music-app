import Foundation

/// One change to the shared state, on its way to the PC.
///
/// A typed value rather than a dictionary: `[String: Any]` is not Sendable, so it cannot cross to
/// the networking task without the compiler objecting — and rightly, since these are built on the
/// main actor while playing. Typing them also means a misspelled key is a build error instead of
/// an op the PC silently skips.
///
/// The field names and the `type` strings must match `applyOps` in
/// `desktop/lib/lan/state_store.dart`; unknown ops there are skipped, so a typo would be silent.
public struct StateOp: Codable, Sendable, Equatable {
    public let type: String
    public var id: String?
    public var kind: String?
    public var on: Bool?
    public var name: String?
    public var trackId: String?
    public var trackIds: [String]?
    public var positionMs: Int64?
    public var queue: [String]?
    public var index: Int?
    public var playing: Bool?
    public var at: Int64

    private init(
        type: String, id: String? = nil, kind: String? = nil, on: Bool? = nil,
        name: String? = nil, trackId: String? = nil, trackIds: [String]? = nil,
        positionMs: Int64? = nil, queue: [String]? = nil, index: Int? = nil,
        playing: Bool? = nil, at: Int64 = StateOp.now
    ) {
        self.type = type
        self.id = id
        self.kind = kind
        self.on = on
        self.name = name
        self.trackId = trackId
        self.trackIds = trackIds
        self.positionMs = positionMs
        self.queue = queue
        self.index = index
        self.playing = playing
        self.at = at
    }

    public static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    public static func favorite(track id: String, on: Bool, at: Int64 = now) -> StateOp {
        StateOp(type: "favorite", id: id, kind: "track", on: on, at: at)
    }

    public static func favorite(album id: String, on: Bool, at: Int64 = now) -> StateOp {
        StateOp(type: "favorite", id: id, kind: "album", on: on, at: at)
    }

    public static func createPlaylist(id: String, name: String, trackIds: [String], at: Int64 = now) -> StateOp {
        StateOp(type: "playlist.create", id: id, name: name, trackIds: trackIds, at: at)
    }

    public static func renamePlaylist(id: String, name: String, at: Int64 = now) -> StateOp {
        StateOp(type: "playlist.rename", id: id, name: name, at: at)
    }

    public static func addToPlaylist(id: String, trackIds: [String], at: Int64 = now) -> StateOp {
        StateOp(type: "playlist.add", id: id, trackIds: trackIds, at: at)
    }

    public static func removeFromPlaylist(id: String, trackIds: [String], at: Int64 = now) -> StateOp {
        StateOp(type: "playlist.remove", id: id, trackIds: trackIds, at: at)
    }

    public static func deletePlaylist(id: String, at: Int64 = now) -> StateOp {
        StateOp(type: "playlist.delete", id: id, at: at)
    }

    public static func played(trackId: String, at: Int64 = now) -> StateOp {
        StateOp(type: "played", trackId: trackId, at: at)
    }

    public static func progress(
        trackId: String, positionMs: Int64, playing: Bool,
        queue: [String], index: Int, at: Int64 = now
    ) -> StateOp {
        StateOp(
            type: "progress", trackId: trackId, positionMs: positionMs,
            queue: queue, index: index, playing: playing, at: at
        )
    }
}

/// The body of a `POST /api/state/ops`.
struct StateOpsRequest: Codable, Sendable {
    let deviceId: String
    let deviceName: String
    let ops: [StateOp]
}

struct StateOpsResponse: Codable, Sendable {
    let rev: Int64
    let progressRev: Int64
}
