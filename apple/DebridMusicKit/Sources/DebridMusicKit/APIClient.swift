import Foundation

/// Where the library lives, and how to prove we're allowed in.
public struct ServerEndpoint: Codable, Hashable, Sendable {
    public let baseURL: URL
    public let token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}

public enum APIError: Error, Sendable, Equatable {
    case notConfigured
    case unauthorized
    case pairingRefused
    case http(Int)
    case malformed(String)
}

/// The HTTP layer, injectable so the client can be tested without a live PC.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.malformed("not an HTTP response")
        }
        return (data, http)
    }
}

/// Talks to the PC.
///
/// Every call is explicit about the endpoint rather than reading shared state, so the pairing
/// flow — which happens before there IS an endpoint — uses the same client as everything else.
public struct APIClient: Sendable {
    private let transport: HTTPTransport
    private let decoder: JSONDecoder

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
        self.decoder = JSONDecoder()
    }

    // ── Unauthenticated ──────────────────────────────────────────────────────

    /// Is a DebridMusic PC answering here? Used to pick between the home address and the one
    /// from outside, and to confirm a discovered device before showing it.
    public func health(at baseURL: URL, timeout: TimeInterval = 3) async throws -> ServerHealth {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = timeout
        let (data, response) = try await transport.send(request)
        try Self.check(response)
        return try decode(ServerHealth.self, from: data)
    }

    /// Trade the six digits shown on the PC for the access token.
    public func pair(at baseURL: URL, code: String, deviceName: String) async throws -> PairResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["code": code.trimmingCharacters(in: .whitespaces), "device": deviceName]
        )
        let (data, response) = try await transport.send(request)
        // 403 is the only interesting failure: wrong code, expired, or pairing not open — the PC
        // deliberately answers the same way for all three.
        if response.statusCode == 403 { throw APIError.pairingRefused }
        try Self.check(response)
        return try decode(PairResponse.self, from: data)
    }

    // ── Library ──────────────────────────────────────────────────────────────

    /// The whole catalogue, or nil when the PC says nothing has changed.
    ///
    /// The ETag is what keeps this cheap: with tens of thousands of tracks a re-sync is several
    /// megabytes, and four devices waking up all day would pull it constantly for no reason.
    public func catalog(
        from endpoint: ServerEndpoint,
        etag: String? = nil
    ) async throws -> (catalog: Catalog, etag: String?)? {
        var request = authorized(endpoint, path: "api/catalog")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await transport.send(request)
        if response.statusCode == 304 { return nil }
        try Self.check(response)
        let catalog = try decode(Catalog.self, from: data)
        return (catalog, response.value(forHTTPHeaderField: "ETag"))
    }

    public func search(_ query: String, on endpoint: ServerEndpoint) async throws -> SearchResult {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent("api/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw APIError.malformed("bad search URL") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        try Self.check(response)
        return try decode(SearchResult.self, from: data)
    }

    public func artwork(ref: String, from endpoint: ServerEndpoint) async throws -> Data {
        let request = authorized(endpoint, path: "art/\(ref)")
        let (data, response) = try await transport.send(request)
        try Self.check(response)
        return data
    }

    // ── Shared state ─────────────────────────────────────────────────────────

    public func state(from endpoint: ServerEndpoint, since: Int64? = nil) async throws -> SharedState {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent("api/state"),
            resolvingAgainstBaseURL: false
        )
        if let since { components?.queryItems = [URLQueryItem(name: "since", value: String(since))] }
        guard let url = components?.url else { throw APIError.malformed("bad state URL") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        try Self.check(response)
        return try decode(SharedState.self, from: data)
    }

    @discardableResult
    public func pushOps(
        _ ops: [StateOp],
        deviceId: String,
        deviceName: String,
        to endpoint: ServerEndpoint
    ) async throws -> (rev: Int64, progressRev: Int64) {
        var request = authorized(endpoint, path: "api/state/ops")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            StateOpsRequest(deviceId: deviceId, deviceName: deviceName, ops: ops)
        )
        let (data, response) = try await transport.send(request)
        try Self.check(response)
        let result = try decode(StateOpsResponse.self, from: data)
        return (result.rev, result.progressRev)
    }

    // ── URLs handed to the player ────────────────────────────────────────────

    /// The URL AVPlayer streams from.
    ///
    /// The token rides in the query, not a header, because the renderers on the other end of the
    /// cast path fetch the URL themselves and have nowhere to put a header — and using one form
    /// everywhere means the URL that plays here is the URL that plays on a Sonos.
    public static func streamURL(for track: Track, endpoint: ServerEndpoint) -> URL? {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent(track.streamPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "token", value: endpoint.token)]
        return components?.url
    }

    public static func artworkURL(ref: String, endpoint: ServerEndpoint) -> URL? {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent("art/\(ref)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "token", value: endpoint.token)]
        return components?.url
    }

    // ── plumbing ─────────────────────────────────────────────────────────────

    private func authorized(_ endpoint: ServerEndpoint, path: String) -> URLRequest {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.malformed("\(type): \(error)")
        }
    }

    private static func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401, 403: throw APIError.unauthorized
        default: throw APIError.http(response.statusCode)
        }
    }
}
