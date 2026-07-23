import Foundation

/// Somewhere the music can go that isn't this device.
public struct CastDevice: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let model: String
    public let manufacturer: String
    /// "sonos", "upnp" or "shield".
    public let kind: String
    /// Highest sample rate this device accepts; 0 when it has no known ceiling.
    public let maxSampleRate: Int

    public var isShield: Bool { kind == "shield" }

    public var icon: String {
        switch kind {
        case "shield": "tv"
        case "sonos": "hifispeaker"
        default: "hifispeaker.and.homepod"
        }
    }

    /// What to say under the name — the reason a track might not sound as good as it could.
    public func caveat(for track: Track?) -> String? {
        guard let track, let rate = track.sampleRate, maxSampleRate > 0, rate > maxSampleRate else {
            return nil
        }
        return "wordt omgezet naar \(maxSampleRate / 1000) kHz"
    }
}

/// Tells the PC to send music somewhere else.
///
/// Only ever a message to the PC — the audio never passes through this device. That is what makes
/// it lossless: the file goes straight from the machine holding it to the speaker.
public struct CastClient: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func devices(from endpoint: ServerEndpoint) async throws -> [CastDevice] {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/cast/devices"))
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        // Discovery is an SSDP sweep plus a scan of the subnet for the Shield; it takes a few
        // seconds on a quiet network and the default timeout would give up first.
        request.timeoutInterval = 20
        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
        return try JSONDecoder().decode([CastDevice].self, from: data)
    }

    public func play(
        trackIds: [String],
        startingAt index: Int,
        on device: CastDevice,
        endpoint: ServerEndpoint
    ) async throws {
        try await post(
            "api/cast/play",
            body: ["deviceId": device.id, "trackIds": trackIds, "index": index],
            endpoint: endpoint
        )
    }

    public func control(
        _ action: String,
        value: Int? = nil,
        on device: CastDevice,
        endpoint: ServerEndpoint
    ) async throws {
        var body: [String: Any] = ["deviceId": device.id, "action": action]
        if let value { body["value"] = value }
        try await post("api/cast/control", body: body, endpoint: endpoint)
    }

    private func post(_ path: String, body: [String: Any], endpoint: ServerEndpoint) async throws {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            // The PC says why in plain language — a speaker that went off the network, a track
            // that isn't there any more. Pass it through rather than replacing it with a code.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["error"] as? String {
                throw APIError.malformed(message)
            }
            throw APIError.http(response.statusCode)
        }
    }
}
