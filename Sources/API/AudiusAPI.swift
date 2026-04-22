import Foundation

struct AudiusAPI {
    static let baseURL = "https://api.audius.co/v1"
    static var apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "AudiusAPIKey") as? String

    private static func makeURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents(string: baseURL + path)
        if let queryItems = queryItems {
            components?.queryItems = queryItems
        }
        return components?.url
    }

    private static func headers() -> [String: String] {
        var headers = ["Content-Type": "application/json"]
        if let token = AudiusAuth.shared.getAccessToken() {
            headers["Authorization"] = "Bearer \(token)"
        } else if let apiKey = apiKey {
            headers["x-api-key"] = apiKey
        }
        return headers
    }

    static func request<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        guard let url = makeURL(path: path, queryItems: queryItems) else {
            throw AudiusError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        headers().forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AudiusError.invalidResponse
        }

        // 401: token expired — clear and retry once without auth
        if httpResponse.statusCode == 401 {
            Keychain.delete(forKey: AudiusAuth.KeychainKey.accessToken)
            await MainActor.run {
                AudiusAuth.shared.isSignedIn = false
                AudiusAuth.shared.currentUser = nil
            }
            // Retry without Bearer token (falls back to API key)
            var retryRequest = URLRequest(url: url)
            retryRequest.httpMethod = "GET"
            retryRequest.timeoutInterval = 15
            if let apiKey = apiKey {
                retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                retryRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
            guard let retryHttp = retryResponse as? HTTPURLResponse,
                  (200...299).contains(retryHttp.statusCode) else {
                throw AudiusError.httpError(statusCode: (retryResponse as? HTTPURLResponse)?.statusCode ?? 401)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: retryData)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AudiusError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    static func getTrending(time: String = "week", genre: String? = nil) async throws -> [Track] {
        var queryItems = [URLQueryItem(name: "time", value: time)]
        if let genre { queryItems.append(URLQueryItem(name: "genre", value: genre)) }
        let response = try await request(TrackListResponse.self, path: "/tracks/trending", queryItems: queryItems)
        return response.data
    }

    static func getFeaturedTracks() async throws -> [Track] {
        // Uses the "month" window to surface a different set from the weekly trending list
        let response = try await request(TrackListResponse.self, path: "/tracks/trending",
                                        queryItems: [URLQueryItem(name: "time", value: "month")])
        return Array(response.data.prefix(10))
    }

    static func searchTracks(query: String) async throws -> [Track] {
        let response = try await request(TrackListResponse.self, path: "/tracks/search", queryItems: [URLQueryItem(name: "query", value: query)])
        return response.data
    }

    static func getTrack(trackId: String) async throws -> Track {
        let response = try await request(TrackResponse.self, path: "/tracks/\(trackId.urlSafe)")
        return response.data
    }

    static func getMe() async throws -> User {
        let response = try await request(UserResponse.self, path: "/me")
        return response.data
    }

    static func getUser(userId: String) async throws -> User {
        let response = try await request(UserResponse.self, path: "/users/\(userId.urlSafe)")
        return response.data
    }

    static func getUserByHandle(handle: String) async throws -> User {
        let response = try await request(UserResponse.self, path: "/users/handle/\(handle.urlSafe)")
        return response.data
    }

    static func getPlaylist(playlistId: String) async throws -> Playlist {
        let response = try await request(PlaylistResponse.self, path: "/playlists/\(playlistId.urlSafe)")
        return response.data
    }

    static func getUserTracks(userId: String) async throws -> [Track] {
        let response = try await request(TrackListResponse.self, path: "/users/\(userId.urlSafe)/tracks")
        return response.data
    }

    static func getUserPlaylists(userId: String) async throws -> [Playlist] {
        let response = try await request(PlaylistListResponse.self, path: "/users/\(userId.urlSafe)/playlists")
        return response.data
    }

    static func getPlaylistTracks(playlistId: String) async throws -> [Track] {
        let response = try await request(TrackListResponse.self, path: "/playlists/\(playlistId.urlSafe)/tracks")
        return response.data
    }

    /// Returns tracks the authenticated user has liked.
    static func getUserFavorites(userId: String) async throws -> [Track] {
        // Step 1: Fetch ALL liked track IDs because the API returns them oldest-first
        // and doesn't support descending sort natively. We paginate until completion.
        var allTrackIds = [Int]()
        var offset = 0
        let limit = 100
        let maxFavoritesToScan = 3000 // reasonable cap (30 pages)
        
        while offset < maxFavoritesToScan {
            let favResponse = try await request(FavoriteActivityResponse.self,
                                                path: "/users/\(userId.urlSafe)/favorites",
                                                queryItems: [
                                                    URLQueryItem(name: "limit", value: "\(limit)"),
                                                    URLQueryItem(name: "offset", value: "\(offset)")
                                                ])
            let pageIds = favResponse.data
                .filter { $0.favoriteType == "SaveType.track" }
                .compactMap { $0.favoriteItemId }
            
            allTrackIds.append(contentsOf: pageIds)
            
            if favResponse.data.count < limit { break }
            offset += limit
        }
        
        guard !allTrackIds.isEmpty else { return [] }
        
        // Take the up to 100 NEWEST (which are at the END of the list)
        let idsToFetch = Array(allTrackIds.suffix(100).reversed())
        
        // Step 2: Batch fetch the track details using numeric IDs
        let queryItems = idsToFetch.map { URLQueryItem(name: "id", value: String($0)) }
        let tracksResponse = try await request(TrackListResponse.self, path: "/tracks", queryItems: queryItems)
        
        // The API returns duplicate Track objects for the same track (likely a discovery node mirror quirk).
        // If we don't deduplicate here, SwiftUI's ForEach skips the duplicate IDs, creating rendering gaps.
        var uniqueTracks = [Track]()
        var seenIds = Set<String>()
        
        for track in tracksResponse.data {
            if !seenIds.contains(track.id) {
                seenIds.insert(track.id)
                uniqueTracks.append(track)
            }
        }
        
        return uniqueTracks
    }

    static func getTrackStreamURL(trackId: String) -> URL? {
        return URL(string: "\(baseURL)/tracks/\(trackId.urlSafe)/stream?app_name=Audiswift")
    }
}

enum AudiusError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
}

extension AudiusError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

private extension String {
    var urlSafe: String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
