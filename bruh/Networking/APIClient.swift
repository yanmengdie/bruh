import Foundation

actor APIClient {
    let baseURL: String
    let anonKey: String
    let session: URLSession

    init(
        configuration: APIClientConfiguration = .current
    ) {
        self.baseURL = configuration.functionsBaseURL
        self.anonKey = configuration.anonKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    init(baseURL: String, anonKey: String) {
        self.init(configuration: APIClientConfiguration(functionsBaseURL: baseURL, anonKey: anonKey))
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            let snippet = String(decoding: data.prefix(240), as: UTF8.self)
            throw NetworkError.decodingError(snippet.isEmpty ? error.localizedDescription : snippet)
        }
    }

    func httpError(statusCode: Int, data: Data) -> NetworkError {
        let payload = try? decoder.decode(APIErrorResponseDTO.self, from: data)
        let message = payload?.error
            ?? {
                let snippet = String(decoding: data.prefix(240), as: UTF8.self)
                return snippet.isEmpty ? nil : snippet
            }()
        return .httpError(statusCode, message, payload?.errorCategory)
    }

    func performDecodableRequest<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        retryProfile: NetworkRetryProfile,
        contract: APIContractName
    ) async throws -> T {
        var lastError: Error = NetworkError.noData

        for attempt in 1...retryProfile.maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw NetworkError.noData }
                guard (200...299).contains(http.statusCode) else {
                    throw httpError(statusCode: http.statusCode, data: data)
                }
                try APIContract.validateResponse(http, expectedContract: contract)

                return try decode(type, from: data)
            } catch {
                lastError = error
                guard NetworkRetryPolicy.shouldRetry(error, attempt: attempt, profile: retryProfile) else {
                    throw error
                }

                try await Task.sleep(
                    nanoseconds: NetworkRetryPolicy.delayNanoseconds(forAttempt: attempt, profile: retryProfile)
                )
            }
        }

        throw lastError
    }
}
