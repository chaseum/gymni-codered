import Foundation
import Network

/// Advertises the phone to the tripod and receives its local model observations.
public final class HubServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 8000
    public typealias Handler = @Sendable (CameraObservation) async -> IngestAck
    public typealias ConfigurationHandler = @Sendable () async -> CameraConfiguration?

    private let listener: NWListener
    private let queue = DispatchQueue(label: "gymni.hub-server")
    private let handler: Handler
    private let configuration: ConfigurationHandler?
    private let cameraConnected: @Sendable (String) async -> Void

    // ponytail: no auth, like the backend without GYMAI_TOKEN; add a bearer check if the hub leaves trusted Wi-Fi.
    public init(port: UInt16 = HubServer.defaultPort, advertises: Bool = true, configuration: ConfigurationHandler? = nil,
                cameraConnected: @escaping @Sendable (String) async -> Void = { _ in }, handler: @escaping Handler) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NWError.posix(.EINVAL) }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true  // the next workout can rebind 8000 right after the last one
        listener = try NWListener(using: parameters, on: nwPort)
        self.handler = handler
        self.configuration = configuration
        self.cameraConnected = cameraConnected
        if advertises { listener.service = NWListener.Service(name: "Gym&I", type: "_gymni._tcp") }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    public func stop() { listener.cancel() }

    /// This phone's Wi-Fi IPv4 address, for the camera device's `--post` URL.
    public static func wifiAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard String(cString: interface.ifa_name) == "en0", let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                Task {
                    if request.isTripod, let host = Self.urlHost(connection.endpoint) {
                        await self.cameraConnected(host)
                    }
                    let (status, body) = await self.route(request)
                    let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if isComplete || error != nil || buffer.count > 1_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    /// The camera's address as a URL host: IPv4 when possible (also for IPv4-mapped IPv6), else bracketed IPv6.
    static func urlHost(_ endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return "\(address)".split(separator: "%").first.map(String.init)
        case .ipv6(let address):
            if let v4 = address.asIPv4 { return "\(v4)" }
            return "[\("\(address)".split(separator: "%").first ?? "")]"
        case .name(let name, _): return name
        @unknown default: return nil
        }
    }

    func route(_ request: HTTPRequest) async -> (String, Data) {
        let parts = request.path.split(separator: "/")
        switch (request.method, parts.count) {
        case ("GET", _) where request.path == "/health":
            return ("200 OK", Data(#"{"ok":true,"schema_version":1}"#.utf8))
        case ("GET", _) where request.path == "/api/camera/configuration":
            guard let config = await configuration?() else {
                return ("503 Service Unavailable", Data(#"{"error":"no workout"}"#.utf8))
            }
            return ("200 OK", (try? Contracts.encoder.encode(config)) ?? Data("{}".utf8))
        case ("POST", 4) where parts[0] == "api" && parts[1] == "sessions" && parts[3] == "observations":
            if let workoutId = request.query["workout_id"] {
                guard let config = await configuration?(), config.workoutId == workoutId,
                      request.query["revision"] == String(config.revision) else {
                    return ("409 Conflict", Data(#"{"error":"stale camera controls"}"#.utf8))
                }
            }
            guard let observation = try? Contracts.decoder.decode(CameraObservation.self, from: request.body) else {
                return ("422 Unprocessable Entity", Data(#"{"error":"invalid observation"}"#.utf8))
            }
            let ack = await handler(observation)
            return ("200 OK", (try? Contracts.encoder.encode(ack)) ?? Data("{}".utf8))
        default:
            return ("404 Not Found", Data(#"{"error":"not found"}"#.utf8))
        }
    }
}

/// Just enough HTTP/1.1 parsing for small JSON POSTs.
struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
    let query: [String: String]
    let isTripod: Bool

    /// nil until the headers and the whole Content-Length body have arrived.
    init?(_ data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        let length = lines.dropFirst().lazy.compactMap { line -> Int? in
            let field = line.split(separator: ":", maxSplits: 1)
            guard field.count == 2, field[0].lowercased() == "content-length" else { return nil }
            return Int(field[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        let body = data[headerEnd.upperBound...]
        guard length >= 0, body.count >= length else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1].split(separator: "?", maxSplits: 1)[0])
        let items = URLComponents(string: String(requestLine[1]))?.queryItems ?? []
        query = items.reduce(into: [:]) { result, item in result[item.name] = item.value }
        isTripod = lines.contains { $0.lowercased() == "x-gymni-camera: tripod" }
        self.body = Data(body.prefix(length))
    }
}
