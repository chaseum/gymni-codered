import Foundation
import Network

/// Lets a camera device POST observations to the phone exactly as it would to the laptop backend:
/// `fitness-ml run --post http://<phone-ip>:8000 --session phone`. Serves one request per connection
/// (fitness-ml's urllib never reuses them). Any session id in the path is accepted: the phone runs one session.
public final class HubServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 8000
    public typealias Handler = @Sendable (CameraObservation) async -> IngestAck

    private let listener: NWListener
    private let queue = DispatchQueue(label: "gymni.hub-server")
    private let handler: Handler

    // ponytail: no auth, like the backend without GYMAI_TOKEN; add a bearer check if the hub leaves trusted Wi-Fi.
    public init(port: UInt16 = HubServer.defaultPort, handler: @escaping Handler) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NWError.posix(.EINVAL) }
        listener = try NWListener(using: .tcp, on: nwPort)
        self.handler = handler
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

    private func route(_ request: HTTPRequest) async -> (String, Data) {
        let parts = request.path.split(separator: "/")
        switch (request.method, parts.count) {
        case ("GET", _) where request.path == "/health":
            return ("200 OK", Data(#"{"ok":true,"schema_version":1}"#.utf8))
        case ("POST", 4) where parts[0] == "api" && parts[1] == "sessions" && parts[3] == "observations":
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
        guard body.count >= length else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1].split(separator: "?", maxSplits: 1)[0])
        self.body = Data(body.prefix(length))
    }
}
