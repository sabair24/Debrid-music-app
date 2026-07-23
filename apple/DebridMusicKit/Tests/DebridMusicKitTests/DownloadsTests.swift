import Foundation
import Testing
@testable import DebridMusicKit

private func track(_ id: String, ext: String = "flac", bytes: Int64 = 1000) -> Track {
    APIClientTests.sampleTrack(streamPath: "/stream/\(id).\(ext)")
}

@MainActor
@Suite("Offline downloads")
struct DownloadsTests {

    private func makeManager() -> (DownloadManager, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dmtest-\(UUID().uuidString)", isDirectory: true)
        return (DownloadManager(directory: directory), directory)
    }

    @Test("a fresh device has nothing saved")
    func empty() {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(manager.savedCount == 0)
        #expect(manager.usedBytes == 0)
        #expect(manager.state(of: "anything") == .absent)
        #expect(manager.localURL(for: track("t1")) == nil)
    }

    @Test("a saved track is remembered across a restart")
    func survivesRestart() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Stand in for a finished download.
        let file = directory.appendingPathComponent("t1.flac")
        try Data(repeating: 7, count: 2048).write(to: file)
        manager.registerForTest(trackId: "t1", fileName: "t1.flac", bytes: 2048)

        let reopened = DownloadManager(directory: directory)
        #expect(reopened.savedCount == 1)
        #expect(reopened.usedBytes == 2048)
        #expect(reopened.isSaved("t1"))
    }

    @Test("a registry entry whose file vanished is not counted")
    func forgetsMissingFiles() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("t1.flac")
        try Data(repeating: 7, count: 2048).write(to: file)
        manager.registerForTest(trackId: "t1", fileName: "t1.flac", bytes: 2048)

        // iOS reclaims files when storage runs low. Trusting the registry would mean handing the
        // player a URL that no longer exists, which fails as silence rather than as an error.
        try FileManager.default.removeItem(at: file)

        let reopened = DownloadManager(directory: directory)
        #expect(reopened.savedCount == 0)
        #expect(reopened.usedBytes == 0)
        #expect(reopened.localURL(for: track("t1")) == nil)
    }

    @Test("the player is handed the local file once a track is saved")
    func prefersLocalFile() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(manager.localURL(for: track("t1")) == nil)
        try Data(repeating: 1, count: 10).write(to: directory.appendingPathComponent("t1.flac"))
        manager.registerForTest(trackId: "t1", fileName: "t1.flac", bytes: 10)
        #expect(manager.localURL(for: track("t1"))?.lastPathComponent == "t1.flac")
    }

    @Test("an album counts as saved only when every track is")
    func albumCompleteness() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 1, count: 10).write(to: directory.appendingPathComponent("t1.flac"))
        manager.registerForTest(trackId: "t1", fileName: "t1.flac", bytes: 10)

        #expect(manager.isSaved(album: ["t1"]))
        // Half an album offline is not an album you can listen to on a plane.
        #expect(!manager.isSaved(album: ["t1", "t2"]))
        #expect(!manager.isSaved(album: []))
    }

    @Test("removing gives the space back")
    func removing() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 1, count: 512).write(to: directory.appendingPathComponent("t1.flac"))
        try Data(repeating: 1, count: 256).write(to: directory.appendingPathComponent("t2.flac"))
        manager.registerForTest(trackId: "t1", fileName: "t1.flac", bytes: 512)
        manager.registerForTest(trackId: "t2", fileName: "t2.flac", bytes: 256)
        #expect(manager.usedBytes == 768)

        manager.remove(["t1"])
        #expect(manager.usedBytes == 256)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("t1.flac").path))

        manager.removeAll()
        #expect(manager.savedCount == 0)
        #expect(manager.usedBytes == 0)
    }

    @Test("clearing sweeps files the registry lost track of")
    func sweepsOrphans() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        // What an interrupted save leaves behind: a file nothing has a record of, which would
        // otherwise sit there taking up space forever.
        let orphan = directory.appendingPathComponent("half-written.flac")
        try Data(repeating: 9, count: 4096).write(to: orphan)

        manager.removeAll()
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test("used space reads as something a person recognises")
    func humanSize() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 10).write(to: directory.appendingPathComponent("t1.flac"))
        manager.registerForTest(trackId: "t1", fileName: "t1.flac", bytes: 5_400_000)
        #expect(manager.usedDescription.contains("MB"))
    }
}
