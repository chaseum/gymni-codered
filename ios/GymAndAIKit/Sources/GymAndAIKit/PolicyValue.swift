import Foundation

enum PolicyValue: Decodable, Sendable {
    case number(Double), text(String)
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Double.self) { self = .number(number) }
        else { self = .text(try value.decode(String.self)) }
    }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var text: String? { if case .text(let value) = self { value } else { nil } }
}
