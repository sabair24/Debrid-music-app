import DebridMusicKit
import SwiftUI

@main
struct DebridMusicApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                #if os(macOS)
                .frame(minWidth: 940, minHeight: 620)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Synchroniseer met pc") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}

/// Everything the screens share: the connection, the library, and the player.
///
/// One object rather than three environment values — they are only ever useful together, and
/// wiring the player's callbacks to the library needs a place that owns both.
@MainActor
@Observable
final class AppModel {
    let connection = ServerConnection()
    let library = LibraryStore()
    let playback = PlaybackController()
    let browser = ServerBrowser()

    /// Sending music elsewhere in the house. The PC does the actual work — this only asks it to.
    let cast = CastClient()

    /// Albums kept on this device, for when there is no network at all.
    let downloads = DownloadManager()

    var isPairing = false
    var showingSpeakers = false
    var showingSettings = false

    var isPaired: Bool { connection.settings.isPaired }

    init() {
        // A saved copy always wins over the stream — that is what "offline" means, and it also
        // makes a downloaded album start instantly at home.
        playback.setLocalFileProvider { [downloads] track in downloads.localURL(for: track) }
        playback.onProgress = { [weak self] track, position, playing in
            guard let self else { return }
            Task { @MainActor in
                await self.library.reportProgress(
                    trackId: track.id,
                    positionMs: Int64(position * 1000),
                    playing: playing,
                    queue: self.playback.queue.map(\.id),
                    index: self.playback.index,
                    to: self.connection.endpoint
                )
            }
        }
        playback.onTrackStarted = { [weak self] track in
            guard let self else { return }
            Task { @MainActor in
                await self.library.reportPlayed(track.id, to: self.connection.endpoint)
            }
        }
    }

    func start() async {
        let endpoint = await connection.connect()
        playback.setEndpoint(endpoint ?? connection.endpoint)
        if let endpoint {
            await library.sync(from: endpoint)
        }
    }

    func refresh() async {
        guard let endpoint = await connection.connect() else { return }
        playback.setEndpoint(endpoint)
        await library.sync(from: endpoint)
    }

    /// Play an album from a given track — the normal way anything starts here.
    func play(album: Album, from track: Track? = nil) {
        let tracks = library.tracks(ofAlbum: album.id)
        let start = track.flatMap { t in tracks.firstIndex(where: { $0.id == t.id }) } ?? 0
        playback.play(tracks, startingAt: start)
    }

    func play(tracks: [Track], from index: Int = 0) {
        playback.play(tracks, startingAt: index)
    }

    /// Pick up where another device left off.
    func resumeRemote() {
        guard let progress = library.remoteProgress, !progress.trackId.isEmpty else { return }
        let queue = progress.queue.compactMap { library.track($0) }
        let tracks = queue.isEmpty ? [library.track(progress.trackId)].compactMap { $0 } : queue
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex { $0.id == progress.trackId } ?? progress.index
        playback.play(tracks, startingAt: index, at: Double(progress.positionMs) / 1000)
    }

    /// Keep an album on this device.
    func saveOffline(album: Album) {
        guard let endpoint = connection.endpoint else { return }
        downloads.save(library.tracks(ofAlbum: album.id), from: endpoint)
    }

    func removeOffline(album: Album) {
        downloads.remove(library.tracks(ofAlbum: album.id).map(\.id))
    }

    func artworkURL(_ ref: String?) -> URL? {
        guard let ref, let endpoint = connection.endpoint else { return nil }
        return APIClient.artworkURL(ref: ref, endpoint: endpoint)
    }
}
