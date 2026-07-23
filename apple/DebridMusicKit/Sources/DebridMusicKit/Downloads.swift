import Foundation

public enum DownloadState: Equatable, Sendable {
    case absent
    case queued
    case downloading(fraction: Double)
    case saved(bytes: Int64)
    case failed(String)

    public var isSaved: Bool { if case .saved = self { return true }; return false }
    public var isBusy: Bool {
        switch self {
        case .queued, .downloading: true
        default: false
        }
    }
}

/// One track kept on this device.
struct OfflineEntry: Codable, Sendable {
    let trackId: String
    let fileName: String
    let bytes: Int64
    let savedAt: Date
}

/// Keeps chosen albums on the device, so they play with no network at all.
///
/// One at a time, on purpose. A FLAC album is a few hundred megabytes and saturating the link
/// with ten parallel transfers only makes every one of them slower — and makes whatever else you
/// were streaming stutter.
@MainActor
@Observable
public final class DownloadManager {
    public private(set) var states: [String: DownloadState] = [:]
    public private(set) var usedBytes: Int64 = 0
    /// How many are still to go, for a progress line in the UI.
    public private(set) var pending: Int = 0

    private var entries: [String: OfflineEntry] = [:]
    private let directory: URL
    private let registryURL: URL
    private let session: URLSession

    private var queue: [(Track, ServerEndpoint)] = []
    private var running = false

    public init(directory: URL? = nil, session: URLSession = .shared) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("DebridMusic/Offline", isDirectory: true)
        self.directory = base
        self.registryURL = base.appendingPathComponent("registry.json")
        self.session = session
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    // ── Reading ──────────────────────────────────────────────────────────────

    public func state(of trackId: String) -> DownloadState {
        states[trackId] ?? .absent
    }

    /// The file on disk, if this track was saved. Handed to the player, which prefers it over
    /// the stream — that is the whole point of saving it.
    public func localURL(for track: Track) -> URL? {
        guard let entry = entries[track.id] else { return nil }
        let url = directory.appendingPathComponent(entry.fileName)
        // Verify rather than trust the registry: a file can be removed by the system when
        // storage runs low, and playing a URL that no longer exists just fails silently.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public func isSaved(_ trackId: String) -> Bool { entries[trackId] != nil }

    /// Is every track of this album on the device?
    public func isSaved(album trackIds: [String]) -> Bool {
        !trackIds.isEmpty && trackIds.allSatisfy { entries[$0] != nil }
    }

    // ── Saving ───────────────────────────────────────────────────────────────

    public func save(_ tracks: [Track], from endpoint: ServerEndpoint) {
        for track in tracks where entries[track.id] == nil && !state(of: track.id).isBusy {
            states[track.id] = .queued
            queue.append((track, endpoint))
        }
        pending = queue.count
        Task { await drain() }
    }

    private func drain() async {
        guard !running else { return }
        running = true
        defer { running = false }

        while !queue.isEmpty {
            let (track, endpoint) = queue.removeFirst()
            pending = queue.count
            await fetch(track, from: endpoint)
        }
        pending = 0
    }

    private func fetch(_ track: Track, from endpoint: ServerEndpoint) async {
        guard let url = APIClient.streamURL(for: track, endpoint: endpoint) else {
            states[track.id] = .failed("Geen adres voor dit nummer.")
            return
        }
        states[track.id] = .downloading(fraction: 0)
        do {
            let (temporary, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                states[track.id] = .failed("De pc gaf dit nummer niet vrij.")
                try? FileManager.default.removeItem(at: temporary)
                return
            }
            let fileName = "\(track.id).\(track.ext)"
            let destination = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)

            // Keep it off iCloud and out of the backup: this is a copy of something the PC still
            // has, and a 40 GB library has no business in someone's iCloud backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = destination
            try? mutable.setResourceValues(values)

            let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? track.sizeBytes
            entries[track.id] = OfflineEntry(
                trackId: track.id, fileName: fileName,
                bytes: bytes ?? track.sizeBytes, savedAt: Date()
            )
            states[track.id] = .saved(bytes: bytes ?? track.sizeBytes)
            recount()
            persist()
        } catch {
            states[track.id] = .failed("Downloaden mislukt.")
        }
    }

    // ── Removing ─────────────────────────────────────────────────────────────

    public func remove(_ trackIds: [String]) {
        for id in trackIds {
            if let entry = entries.removeValue(forKey: id) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.fileName))
            }
            states[id] = .absent
        }
        recount()
        persist()
    }

    public func removeAll() {
        remove(Array(entries.keys))
        // Sweep anything the registry lost track of — an interrupted save can leave a file
        // behind that nothing would ever clean up.
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in contents where file.lastPathComponent != registryURL.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
        recount()
    }

    public var savedCount: Int { entries.count }

    public var usedDescription: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }

    /// Record a file that is already on disk, without going over the network.
    ///
    /// Only for tests: it lets the registry, the storage accounting and the "is this album
    /// complete?" logic be exercised without a server, which is where the interesting mistakes
    /// live anyway.
    func registerForTest(trackId: String, fileName: String, bytes: Int64) {
        entries[trackId] = OfflineEntry(
            trackId: trackId, fileName: fileName, bytes: bytes, savedAt: Date()
        )
        states[trackId] = .saved(bytes: bytes)
        recount()
        persist()
    }

    // ── Registry ─────────────────────────────────────────────────────────────

    private func recount() {
        usedBytes = entries.values.reduce(0) { $0 + $1.bytes }
    }

    private func load() {
        guard let data = try? Data(contentsOf: registryURL),
              let stored = try? JSONDecoder().decode([OfflineEntry].self, from: data) else { return }
        // Drop entries whose file is gone, so the storage figure matches what is actually there.
        entries = Dictionary(uniqueKeysWithValues: stored.compactMap { entry in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.fileName).path)
                ? (entry.trackId, entry) : nil
        })
        states = entries.mapValues { .saved(bytes: $0.bytes) }
        recount()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }
}
