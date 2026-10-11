import Foundation

public enum MJPEGStream {
    /// Parse away from the main actor and keep only the newest pending preview frame.
    public static func frames(from url: URL) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let delegate = MJPEGDataDelegate(continuation: continuation)
            let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: queue)
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("multipart/x-mixed-replace", forHTTPHeaderField: "Accept")
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }
}

/// Mutable decoding state is accessed only by the session's serial delegate queue.
private final class MJPEGDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var decoder = MJPEGFrameDecoder()
    private var acceptedResponse = false

    init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        // Foundation can deliver another response for each part of a multipart stream.
        if !acceptedResponse {
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("multipart/x-mixed-replace") == true else {
                completionHandler(.cancel)
                continuation.finish(throwing: URLError(.cannotDecodeContentData))
                return
            }
            acceptedResponse = true
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        for byte in data {
            if let frame = decoder.append(byte) { continuation.yield(frame) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { continuation.finish(throwing: error) }
        else { continuation.finish() }
    }
}
