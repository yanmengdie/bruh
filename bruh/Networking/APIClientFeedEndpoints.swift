import Foundation

extension APIClient {
    func fetchFeed(since: Date? = nil, limit: Int = 20) async throws -> [PostDTO] {
        var components = URLComponents(string: "\(baseURL)/feed")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "_ts", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        if let since {
            let iso = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "since", value: iso.string(from: since)))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        APIContract.applyRequestHeaders(to: &request, contract: .feedV1)

        return try await performDecodableRequest(
            request,
            as: [PostDTO].self,
            retryProfile: .feedRead,
            contract: .feedV1
        )
    }
}
