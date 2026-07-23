import Foundation
import Testing
@testable import DebridMusicKit

private let home = URL(string: "http://192.168.0.216:47820")!
private let remote = URL(string: "http://pc-van-saber.tail1234.ts.net:47820")!

private func health(_ name: String) -> String {
    #"{"status":"ok","name":"debridmusic-desktop","version":"1","deviceName":"\#(name)"}"#
}

@MainActor
@Suite("Choosing an address")
struct ConnectionTests {

    /// A fresh defaults domain per test, so one doesn't inherit another's pairing.
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return suite
    }

    private func connection(
        reachable: Set<URL>,
        defaults: UserDefaults
    ) -> (ServerConnection, () -> [URL]) {
        var tried: [URL] = []
        let transport = StubTransport { request in
            let url = request.url!
            let base = URL(string: "\(url.scheme!)://\(url.host!):\(url.port!)")!
            tried.append(base)
            guard reachable.contains(base) else {
                throw URLError(.cannotConnectToHost)
            }
            return StubTransport.json(health(base.host!))
        }
        return (ServerConnection(api: APIClient(transport: transport), defaults: defaults), { tried })
    }

    @Test("at home, the home address is used and the remote one is never touched")
    func prefersHome() async {
        let defaults = makeDefaults()
        let (connection, tried) = connection(reachable: [home, remote], defaults: defaults)
        connection.applySettingsForTest(ServerSettings(homeURL: home, remoteURL: remote, token: "t"))

        let endpoint = await connection.connect()
        #expect(endpoint?.baseURL == home)
        #expect(connection.reachable)
        // Not just "home won" — the remote address must not be probed at all, or every launch
        // at home would wake a VPN for nothing.
        #expect(tried() == [home])
    }

    @Test("away from home, it falls back to the remote address")
    func fallsBackToRemote() async {
        let defaults = makeDefaults()
        let (connection, tried) = connection(reachable: [remote], defaults: defaults)
        connection.applySettingsForTest(ServerSettings(homeURL: home, remoteURL: remote, token: "t"))

        let endpoint = await connection.connect()
        #expect(endpoint?.baseURL == remote)
        #expect(connection.reachable)
        #expect(tried() == [home, remote])
    }

    @Test("with neither reachable, the library still opens offline")
    func offline() async {
        let defaults = makeDefaults()
        let (connection, _) = connection(reachable: [], defaults: defaults)
        connection.applySettingsForTest(ServerSettings(homeURL: home, remoteURL: remote, token: "t"))

        let endpoint = await connection.connect()
        #expect(!connection.reachable)
        // An endpoint is still handed back: downloaded tracks play from disk, and the app should
        // open its cached library rather than the pairing screen.
        #expect(endpoint == nil)
        #expect(connection.endpoint?.baseURL == home)
    }

    @Test("no remote address configured means only home is tried")
    func homeOnly() async {
        let defaults = makeDefaults()
        let (connection, tried) = connection(reachable: [], defaults: defaults)
        connection.applySettingsForTest(ServerSettings(homeURL: home, token: "t"))

        _ = await connection.connect()
        #expect(tried() == [home])
    }

    @Test("an unpaired app asks for a code instead of probing anything")
    func unpaired() async {
        let defaults = makeDefaults()
        let (connection, tried) = connection(reachable: [home], defaults: defaults)
        let endpoint = await connection.connect()
        #expect(endpoint == nil)
        #expect(tried().isEmpty)
    }
}
