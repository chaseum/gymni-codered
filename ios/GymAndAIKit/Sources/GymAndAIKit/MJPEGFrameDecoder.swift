import Foundation

/// Extracts bounded JPEG frames from a multipart stream without buffering the whole response.
public struct MJPEGFrameDecoder: Sendable {
    private var frame: [UInt8] = []
    private var previous: UInt8 = 0
    private let maximumFrameBytes: Int

    public init(maximumFrameBytes: Int = 2_000_000) {
        self.maximumFrameBytes = maximumFrameBytes
    }

    public mutating func append(_ byte: UInt8) -> Data? {
        defer { previous = byte }
        if frame.isEmpty {
            if previous == 0xff, byte == 0xd8 { frame = [0xff, 0xd8] }
            return nil
        }
        frame.append(byte)
        if frame.count > maximumFrameBytes {
            frame.removeAll(keepingCapacity: false)
            return nil
        }
        if previous == 0xff, byte == 0xd9 {
            let data = Data(frame)
            frame.removeAll(keepingCapacity: true)
            return data
        }
        return nil
    }
}
