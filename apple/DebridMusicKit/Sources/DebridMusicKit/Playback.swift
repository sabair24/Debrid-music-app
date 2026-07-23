import AVFoundation
import Foundation
import MediaPlayer

/// Plays the library, locally.
///
/// AVFoundation decodes FLAC itself (iOS 11 / macOS 10.13 and later), so a lossless library
/// streams straight from the PC with nothing bundled and nothing transcoded.
@MainActor
@Observable
public final class PlaybackController {
    public private(set) var queue: [Track] = []
    public private(set) var index: Int = 0
    public private(set) var isPlaying = false
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0

    public var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    /// Called every few seconds while playing, and on every pause or track change — the hook the
    /// app uses to keep the shared position up to date.
    public var onProgress: ((Track, TimeInterval, Bool) -> Void)?
    public var onTrackStarted: ((Track) -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var endpoint: ServerEndpoint?
    private var localFileProvider: ((Track) -> URL?)?
    private var lastReport: Date = .distantPast

    public init(localFileProvider: ((Track) -> URL?)? = nil) {
        self.localFileProvider = localFileProvider
        configureAudioSession()
        configureRemoteCommands()
    }

    public func setEndpoint(_ endpoint: ServerEndpoint?) {
        self.endpoint = endpoint
    }

    public func setLocalFileProvider(_ provider: @escaping (Track) -> URL?) {
        localFileProvider = provider
    }

    // ── Transport ────────────────────────────────────────────────────────────

    public func play(_ tracks: [Track], startingAt start: Int = 0, at position: TimeInterval = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        index = max(0, min(start, tracks.count - 1))
        openCurrent(seekTo: position)
    }

    public func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            report(force: true)
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    public func next() {
        guard index + 1 < queue.count else { return }
        index += 1
        openCurrent()
    }

    public func previous() {
        // Restart the track first, like every other music player — only jump back when you're
        // already near the beginning.
        if position > 4, let player {
            player.seek(to: .zero)
            return
        }
        guard index > 0 else { return }
        index -= 1
        openCurrent()
    }

    public func seek(to seconds: TimeInterval) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
        report(force: true)
    }

    public func stop() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        isPlaying = false
        queue = []
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // ── Opening a track ──────────────────────────────────────────────────────

    private func openCurrent(seekTo seconds: TimeInterval = 0) {
        guard let track = current else { return }
        guard let asset = makeAsset(for: track) else { return }

        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }

        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        // Nothing else is mixing here; letting AVPlayer manage volume separately just adds a
        // second place for the level to be wrong.
        player.volume = 1
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.tick(time) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }

        if seconds > 0 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        position = seconds
        duration = track.duration
        onTrackStarted?(track)
        report(force: true)
        updateNowPlaying()
    }

    /// Build the asset for a track — the local copy if one was downloaded, else the stream.
    private func makeAsset(for track: Track) -> AVURLAsset? {
        if let local = localFileProvider?(track), FileManager.default.fileExists(atPath: local.path) {
            return AVURLAsset(url: local)
        }
        guard let endpoint, let url = APIClient.streamURL(for: track, endpoint: endpoint) else {
            return nil
        }
        return AVURLAsset(url: url, options: [
            // Without this the duration of a streamed FLAC is wrong and seeking lands in the
            // wrong place — AVFoundation otherwise estimates from the container instead of
            // reading it properly. Costs a little time on open; the alternative is a seek bar
            // that lies.
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
            // And this: AVFoundation types an asset from the response, and a stream it cannot
            // place is simply refused. The PC sends the right Content-Type, but saying it here
            // too means a proxy that rewrites headers can't break playback.
            "AVURLAssetOutOfBandMIMETypeKey": track.mime ?? "audio/flac",
        ])
    }

    private func tick(_ time: CMTime) {
        position = time.seconds
        if let itemDuration = player?.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        report()
        updateNowPlayingTime()
    }

    private func report(force: Bool = false) {
        guard let track = current else { return }
        // Throttled: the position moves continuously, and telling the PC about every frame of it
        // would put the whole house into a re-sync loop.
        if !force, Date().timeIntervalSince(lastReport) < 5 { return }
        lastReport = Date()
        onProgress?(track, position, isPlaying)
    }

    // ── Lock screen / Now Playing ────────────────────────────────────────────

    private func configureAudioSession() {
        #if os(iOS)
        // Playback category: keeps playing with the screen locked and when the iPad is put down,
        // which is the normal way anyone listens to an album.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayPause() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.togglePlayPause() } }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
