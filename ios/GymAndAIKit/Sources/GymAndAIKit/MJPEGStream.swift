import Foundation

public enum MJPEGStream {
    /// Parse away from the main actor and keep only the newest pending preview frame.
    public static func frames(from url: URL) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let worker = Task.detached {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 10
                    request.setValue("multipart/x-mixed-replace", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                          response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("multipart/x-mixed-replace") == true else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    var decoder = MJPEGFrameDecoder()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if let frame = decoder.append(byte) { continuation.yield(frame) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
