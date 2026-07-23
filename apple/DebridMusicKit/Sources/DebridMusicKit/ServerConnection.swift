import Foundation
import Network

/// A DebridMusic PC that answered on the network.
public struct DiscoveredServer: Identifiable, Hashable, Sendable {
    public let name: String
    public let host: String
    public let port: Int

    public var id: String { "\(host):\(port)" }
    public var baseURL: URL? { URL(string: "http://\(host):\(port)") }

    public init(name: String, host: String, port: Int) {
        self.name = name
        self.host = host
        self.port = port
    }
}

/// Where the PC is, at home and from outside.
///
/// Two addresses rather than one. At home the LAN address is direct and fast; away from home the
/// same library is reachable over Tailscale. Storing both and picking per launch means you never
/// have to change a setting when you walk out of the door.
public struct ServerSettings: Codable, Sendable, Equatable {
    public var homeURL: URL?
    public var remoteURL: URL?
    public var token: String
    public var serverName: String

    public init(homeURL: URL? = nil, remoteURL: URL? = nil, token: String = "", serverName: String = "") {
        self.homeURL = homeURL
        self.remoteURL = remoteURL
        self.token = token
        self.serverName = serverName
    }

    public var isPaired: Bool { !token.isEmpty && (homeURL != nil || remoteURL != nil) }
}

/// Finds the PC, keeps the pairing, and works out which address to use right now.
@MainActor
@Observable
public final class ServerConnection {
    public private(set) var settings: ServerSettings
    public private(set) var endpoint: ServerEndpoint?
    public private(set) var reachable = false
    public private(set) var serverName = ""

    private let api: APIClient
    private let defaults: UserDefaults
    private static let storageKey = "debridmusic.server"

    public init(api: APIClient = APIClient(), defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(ServerSettings.self, from: data) {
            self.settings = stored
        } else {
            self.settings = ServerSettings()
        }
        self.serverName = settings.serverName
    }

    /// Set the stored pairing directly. Tests only — the real path is [pair].
    func applySettingsForTest(_ settings: ServerSettings) {
        self.settings = settings
        save()
    }

    /// Pick the address that answers, home first.
    ///
    /// Sequential with a short timeout rather than racing: at home the LAN address answers in a
    /// few milliseconds, and going straight to it avoids waking a VPN for nothing.
    @discardableResult
    public func connect() async -> ServerEndpoint? {
        guard settings.isPaired else {
            endpoint = nil
            reachable = false
            return nil
        }
        for candidate in [settings.homeURL, settings.remoteURL].compactMap({ $0 }) {
            let attempt = ServerEndpoint(baseURL: candidate, token: settings.token)
            if let health = try? await api.health(at: candidate, timeout: 2) {
                endpoint = attempt
                reachable = true
                serverName = health.deviceName ?? health.name
                return attempt
            }
        }
        // Keep the endpoint so cached content still plays; only the flag says we're offline.
        endpoint = settings.homeURL.map { ServerEndpoint(baseURL: $0, token: settings.token) }
        reachable = false
        return nil
    }

    /// Trade the six digits on the PC's screen for a token, and remember the pairing.
    public func pair(with server: DiscoveredServer, code: String, deviceName: String) async throws {
        guard let url = server.baseURL else { throw APIError.malformed("bad server address") }
        try await pair(with: url, code: code, deviceName: deviceName)
    }

    public func pair(with url: URL, code: String, deviceName: String) async throws {
        let response = try await api.pair(at: url, code: code, deviceName: deviceName)
        guard !response.token.isEmpty else { throw APIError.pairingRefused }
        settings.homeURL = url
        settings.token = response.token
        settings.serverName = response.name ?? url.host ?? "pc"
        save()
        serverName = settings.serverName
        endpoint = ServerEndpoint(baseURL: url, token: response.token)
        reachable = true
    }

    /// The address to use when away from home — a Tailscale name, typically.
    public func setRemoteURL(_ url: URL?) {
        settings.remoteURL = url
        save()
    }

    public func forget() {
        settings = ServerSettings()
        endpoint = nil
        reachable = false
        serverName = ""
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// Bonjour browsing for the PC.
///
/// Bonjour rather than a UDP broadcast, deliberately: on iOS anything that multicasts or
/// broadcasts needs the `com.apple.developer.networking.multicast` entitlement, which has to be
/// requested from Apple. `NWBrowser` goes through the system's own resolver and needs only the
/// ordinary local-network permission, which the first browse prompts for.
@MainActor
@Observable
public final class ServerBrowser {
    public private(set) var servers: [DiscoveredServer] = []
    public private(set) var isSearching = false

    private var browser: NWBrowser?
    private var pending: [String: NWEndpoint] = [:]
    private let api: APIClient

    public init(api: APIClient = APIClient()) {
        self.api = api
    }

    public func start() {
        guard browser == nil else { return }
        isSearching = true
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjour(type: "_debridmusic._tcp", domain: nil),
            using: parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed = state { self?.isSearching = false }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let key = "\(name).\(type)\(domain)"
            guard pending[key] == nil else { continue }
            pending[key] = result.endpoint
            resolve(result.endpoint, name: name)
        }
    }

    /// A browse result carries a service name, not an address. Opening a connection is what makes
    /// the system resolve it — there is no separate lookup call in Network.framework.
    private func resolve(_ endpoint: NWEndpoint, name: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            guard let inner = connection.currentPath?.remoteEndpoint,
                  case let .hostPort(host, port) = inner else {
                connection.cancel()
                return
            }
            let address: String
            switch host {
            case let .ipv4(v4): address = "\(v4)".components(separatedBy: "%").first ?? "\(v4)"
            case let .ipv6(v6): address = "\(v6)".components(separatedBy: "%").first ?? "\(v6)"
            case let .name(hostname, _): address = hostname
            @unknown default: address = ""
            }
            connection.cancel()
            guard !address.isEmpty else { return }
            let found = DiscoveredServer(name: name, host: address, port: Int(port.rawValue))
            Task { @MainActor [weak self] in
                guard let self, !self.servers.contains(where: { $0.id == found.id }) else { return }
                // Confirm it actually answers before offering it. A PC with more than one
                // network interface — a VPN, a virtual switch, Hyper-V — advertises on all of
                // them, and Bonjour hands back whichever resolved first. Listing an address the
                // device cannot reach makes pairing fail for no visible reason.
                guard let url = found.baseURL, (try? await self.api.health(at: url, timeout: 2)) != nil else { return }
                guard !self.servers.contains(where: { $0.id == found.id }) else { return }
                self.servers.append(found)
            }
        }
        connection.start(queue: .main)
    }
}
