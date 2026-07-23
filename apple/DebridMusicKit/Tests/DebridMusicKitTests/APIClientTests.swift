import Foundation
import Testing
@testable import DebridMusicKit

/// Answers canned responses, so the client can be exercised without a PC on the network.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    var handler: (URLRequest) throws -> (Data, HTTPURLResponse)
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try handler(request)
    }

    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "http://pc")!, statusCode: status,
            httpVersion: nil, headerFields: headers
        )!
        return (Data(body.utf8), response)
    }
}

private let pc = URL(string: "http://192.168.0.216:47820")!

@Suite("API client")
struct APIClientTests {

    @Test("the catalogue decodes into the shape the UI uses")
    func decodesCatalog() async throws {
        let body = """
        {"artists":[{"id":"a1","name":"Portishead","artworkRef":"artist-a1","albumCount":1}],
         "albums":[{"id":"al1","artistId":"a1","artistName":"Portishead","title":"Dummy",
                    "year":1994,"artworkRef":"al1","trackCount":2,"edition":null,
                    "isSingle":false,"addedMs":1}],
         "tracks":[{"id":"t1","albumId":"al1","artistId":"a1","title":"Mysterons",
                    "artistName":"Portishead","albumTitle":"Dummy","trackNo":1,"discNo":1,
                    "durationMs":305000,"bitrate":900,"sampleRate":44100,"bitsPerSample":16,
                    "lossless":true,"sizeBytes":1,"year":1994,"genre":"Trip Hop",
                    "mime":"audio/flac","streamPath":"/stream/t1.flac","artworkRef":"al1",
                    "ext":"flac","addedMs":1}],
         "generatedAt":42}
        """
        let transport = StubTransport { _ in StubTransport.json(body, headers: ["ETag": "\"1-abc\""]) }
        let client = APIClient(transport: transport)

        let result = try #require(try await client.catalog(from: ServerEndpoint(baseURL: pc, token: "t")))
        #expect(result.catalog.albums.first?.title == "Dummy")
        #expect(result.catalog.tracks.first?.sampleRate == 44100)
        #expect(result.etag == "\"1-abc\"")
    }

    @Test("a 304 means keep what we have, not throw it away")
    func notModified() async throws {
        let transport = StubTransport { _ in StubTransport.json("", status: 304) }
        let client = APIClient(transport: transport)
        let result = try await client.catalog(from: ServerEndpoint(baseURL: pc, token: "t"), etag: "\"1-abc\"")
        #expect(result == nil)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "\"1-abc\"")
    }

    @Test("the token travels as a bearer header on API calls")
    func sendsBearer() async throws {
        let transport = StubTransport { _ in StubTransport.json(#"{"artists":[],"albums":[],"tracks":[],"generatedAt":0}"#) }
        let client = APIClient(transport: transport)
        _ = try await client.catalog(from: ServerEndpoint(baseURL: pc, token: "secret"))
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test("a wrong pairing code is refused, distinctly from other failures")
    func pairingRefused() async {
        let transport = StubTransport { _ in StubTransport.json("", status: 403) }
        let client = APIClient(transport: transport)
        await #expect(throws: APIError.pairingRefused) {
            _ = try await client.pair(at: pc, code: "000000", deviceName: "iPad")
        }
    }

    @Test("pairing hands back the token")
    func pairingSucceeds() async throws {
        let transport = StubTransport { _ in
            StubTransport.json(#"{"token":"abc123","name":"pc-van-saber","trackCount":9}"#)
        }
        let client = APIClient(transport: transport)
        let response = try await client.pair(at: pc, code: "531610", deviceName: "iPad")
        #expect(response.token == "abc123")
        #expect(response.name == "pc-van-saber")
    }

    @Test("an expired token reads as unauthorised, not as a generic failure")
    func unauthorized() async {
        let transport = StubTransport { _ in StubTransport.json("", status: 401) }
        let client = APIClient(transport: transport)
        await #expect(throws: APIError.unauthorized) {
            _ = try await client.catalog(from: ServerEndpoint(baseURL: pc, token: "stale"))
        }
    }

    @Test("the stream URL carries the token in the query")
    func streamURLCarriesToken() throws {
        // In the query, not a header: a Sonos or a KEF fetches this URL itself and has nowhere to
        // put a header. Using the same form here means what plays on the iPad plays on a speaker.
        let track = Self.sampleTrack(streamPath: "/stream/t1.flac")
        let url = try #require(APIClient.streamURL(for: track, endpoint: ServerEndpoint(baseURL: pc, token: "s3cret")))
        #expect(url.absoluteString == "http://192.168.0.216:47820/stream/t1.flac?token=s3cret")
    }

    @Test("the stream URL keeps the file extension")
    func streamURLKeepsExtension() throws {
        // AVFoundation types an asset from the path; a URL with no extension gets refused.
        let url = try #require(APIClient.streamURL(
            for: Self.sampleTrack(streamPath: "/stream/abc.flac"),
            endpoint: ServerEndpoint(baseURL: pc, token: "t")
        ))
        #expect(url.path.hasSuffix(".flac"))
    }

    static func sampleTrack(streamPath: String, sampleRate: Int? = 44100, bits: Int? = 16) -> Track {
        Track(
            id: "t1", albumId: "al1", artistId: "a1", title: "Mysterons",
            artistName: "Portishead", albumTitle: "Dummy", trackNo: 1, discNo: 1,
            durationMs: 305_000, bitrate: 900, sampleRate: sampleRate, bitsPerSample: bits,
            lossless: true, sizeBytes: 1, year: 1994, genre: nil, mime: "audio/flac",
            streamPath: streamPath, artworkRef: "al1", ext: "flac", addedMs: 0
        )
    }
}

extension Track {
    init(
        id: String, albumId: String, artistId: String, title: String, artistName: String,
        albumTitle: String, trackNo: Int, discNo: Int, durationMs: Int64, bitrate: Int?,
        sampleRate: Int?, bitsPerSample: Int?, lossless: Bool, sizeBytes: Int64, year: Int?,
        genre: String?, mime: String?, streamPath: String, artworkRef: String?, ext: String,
        addedMs: Int64
    ) {
        let json = """
        {"id":"\(id)","albumId":"\(albumId)","artistId":"\(artistId)","title":"\(title)",
         "artistName":"\(artistName)","albumTitle":"\(albumTitle)","trackNo":\(trackNo),
         "discNo":\(discNo),"durationMs":\(durationMs),
         "bitrate":\(bitrate.map(String.init) ?? "null"),
         "sampleRate":\(sampleRate.map(String.init) ?? "null"),
         "bitsPerSample":\(bitsPerSample.map(String.init) ?? "null"),
         "lossless":\(lossless),"sizeBytes":\(sizeBytes),
         "year":\(year.map(String.init) ?? "null"),
         "genre":\(genre.map { "\"\($0)\"" } ?? "null"),
         "mime":\(mime.map { "\"\($0)\"" } ?? "null"),
         "streamPath":"\(streamPath)",
         "artworkRef":\(artworkRef.map { "\"\($0)\"" } ?? "null"),
         "ext":"\(ext)","addedMs":\(addedMs)}
        """
        self = try! JSONDecoder().decode(Track.self, from: Data(json.utf8))
    }
}

@Suite("Track presentation")
struct TrackTests {

    @Test("the quality badge reads the way a listener expects")
    func qualityLabel() {
        #expect(APIClientTests.sampleTrack(streamPath: "/s", sampleRate: 44100, bits: 16).qualityLabel == "FLAC 16/44.1")
        #expect(APIClientTests.sampleTrack(streamPath: "/s", sampleRate: 96000, bits: 24).qualityLabel == "FLAC 24/96")
        #expect(APIClientTests.sampleTrack(streamPath: "/s", sampleRate: nil, bits: nil).qualityLabel == "FLAC")
    }

    @Test("hi-res is flagged as beyond what Sonos takes")
    func sonosLimit() {
        // Sonos plays FLAC to 24 bit but only to 48 kHz, and SKIPS anything above rather than
        // downsampling — so the app has to know before it offers a speaker as a destination.
        #expect(APIClientTests.sampleTrack(streamPath: "/s", sampleRate: 44100).exceedsSonosLimit == false)
        #expect(APIClientTests.sampleTrack(streamPath: "/s", sampleRate: 48000).exceedsSonosLimit == false)
        #expect(APIClientTests.sampleTrack(streamPath: "/s", sampleRate: 96000).exceedsSonosLimit == true)
        #expect(APIClientTests.sampleTrack(streamPath: "/s", sampleRate: 192_000).exceedsSonosLimit == true)
    }
}

@Suite("Search")
struct SearchKeyTests {

    @Test("accents and case do not hide a record")
    func folding() {
        #expect(LibraryStore.searchKey("Beyoncé") == LibraryStore.searchKey("beyonce"))
        #expect(LibraryStore.searchKey("Sigur Rós") == LibraryStore.searchKey("sigur ros"))
    }

    @Test("punctuation is ignored, so a curly apostrophe still matches")
    func punctuation() {
        #expect(LibraryStore.searchKey("Backstreet's Back") == LibraryStore.searchKey("Backstreets Back"))
        #expect(LibraryStore.searchKey("Backstreet\u{2019}s Back") == LibraryStore.searchKey("backstreets back"))
    }
}
