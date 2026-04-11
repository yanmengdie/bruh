import Foundation

extension KeyedDecodingContainer {
    func decodeFirst<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) throws -> T {
        if let value = try decodeFirstIfPresent(type, forKeys: keys) {
            return value
        }

        let context = DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Missing value for keys: \(keys.map(\.stringValue).joined(separator: ", "))"
        )
        throw DecodingError.keyNotFound(keys[0], context)
    }

    func decodeFirstIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) throws -> T? {
        for key in keys {
            if let value = try decodeIfPresent(type, forKey: key) {
                return value
            }
        }
        return nil
    }
}

struct APIErrorResponseDTO: Decodable {
    let error: String
    let errorCategory: String?
}
