import Foundation

enum APIContractName: String {
    case feedV1 = "feed.v1"
    case generateMessageV1 = "generate-message.v1"
    case messageStartersV1 = "message-starters.v1"
    case generatePostInteractionsV1 = "generate-post-interactions.v1"
}

enum APIContract {
    static let clientVersion = "ios-2026-04-12"
    static let clientVersionHeader = "X-Bruh-Client-Version"
    static let acceptContractHeader = "X-Bruh-Accept-Contract"
    static let serverVersionHeader = "X-Bruh-Server-Version"
    static let contractHeader = "X-Bruh-Contract"
    static let compatibilityModeHeader = "X-Bruh-Compat-Mode"

    static func applyRequestHeaders(to request: inout URLRequest, contract: APIContractName) {
        request.setValue(clientVersion, forHTTPHeaderField: clientVersionHeader)
        request.setValue(contract.rawValue, forHTTPHeaderField: acceptContractHeader)
    }

    static func validateResponse(_ response: HTTPURLResponse, expectedContract: APIContractName) throws {
        guard let actualContract = response.value(forHTTPHeaderField: contractHeader)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !actualContract.isEmpty else {
            return
        }

        guard actualContract.caseInsensitiveCompare(expectedContract.rawValue) == .orderedSame else {
            throw NetworkError.incompatibleContract(expected: expectedContract.rawValue, actual: actualContract)
        }
    }
}
