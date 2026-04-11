import Foundation

enum NetworkRetryProfile {
    case feedRead
    case starterPrefetch
    case messageSend
    case interactionGeneration

    var maxAttempts: Int {
        switch self {
        case .feedRead, .starterPrefetch:
            return 3
        case .messageSend, .interactionGeneration:
            return 2
        }
    }

    var baseDelayNanoseconds: UInt64 {
        switch self {
        case .feedRead:
            return 250_000_000
        case .starterPrefetch:
            return 350_000_000
        case .messageSend:
            return 450_000_000
        case .interactionGeneration:
            return 300_000_000
        }
    }
}

enum NetworkRetryPolicy {
    private static let retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    private static let retryableCategories: Set<String> = ["network", "timeout", "provider", "unknown"]
    private static let terminalCategories: Set<String> = ["validation", "config", "database", "auth"]
    private static let retryableTransportCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .resourceUnavailable,
        .cannotLoadFromNetwork,
        .internationalRoamingOff,
        .callIsActive,
        .dataNotAllowed,
    ]

    static func shouldRetry(_ error: Error, attempt: Int, profile: NetworkRetryProfile) -> Bool {
        guard attempt < profile.maxAttempts else { return false }
        guard !(error is CancellationError) else { return false }

        if let networkError = error as? NetworkError {
            return shouldRetry(networkError)
        }

        if let urlError = error as? URLError {
            return retryableTransportCodes.contains(urlError.code)
        }

        return false
    }

    static func delayNanoseconds(forAttempt attempt: Int, profile: NetworkRetryProfile) -> UInt64 {
        profile.baseDelayNanoseconds * UInt64(max(1, attempt))
    }

    private static func shouldRetry(_ error: NetworkError) -> Bool {
        switch error {
        case .invalidURL, .decodingError, .incompatibleContract:
            return false
        case .noData:
            return true
        case .httpError(let statusCode, _, _):
            if let category = error.errorCategory {
                if terminalCategories.contains(category) {
                    return false
                }
                if retryableCategories.contains(category) {
                    return true
                }
            }

            return retryableStatusCodes.contains(statusCode)
        }
    }
}
