import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case httpError(Int, String?, String?)
    case decodingError(String)
    case noData
    case incompatibleContract(expected: String, actual: String)

    var httpStatusCode: Int? {
        guard case .httpError(let statusCode, _, _) = self else { return nil }
        return statusCode
    }

    var errorCategory: String? {
        guard case .httpError(_, _, let category) = self else { return nil }
        return category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code, let message, let category):
            let prefix = category.map { "HTTP error \(code) [\($0)]" } ?? "HTTP error \(code)"
            if let message, !message.isEmpty {
                return "\(prefix): \(message)"
            }
            return prefix
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .noData: return "No data received"
        case .incompatibleContract(let expected, let actual):
            return "Incompatible API contract: expected \(expected), got \(actual)"
        }
    }
}
