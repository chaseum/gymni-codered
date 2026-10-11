import Foundation

public enum MeasurementValue: Codable, Sendable {
    case number(Double), text(String), null
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else { self = .text(try value.decode(String.self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .number(let number): try value.encode(number)
        case .text(let text): try value.encode(text)
        case .null: try value.encodeNil()
        }
    }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
}
