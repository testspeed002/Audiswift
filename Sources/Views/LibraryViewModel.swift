import Foundation
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    static let shared = LibraryViewModel()

    @Published var trendingTracks: [Track] = []
    @Published var featuredTracks: [Track] = []
    @Published var searchResults: [Track] = []
    @Published var searchQuery: String = ""
    @Published var selectedTab: Tab = .home
    @Published var isLoading: Bool = false
    @Published var isSearching: Bool = false
    @Published var error: String?
    @Published var viewMode: ViewMode = .list

    // Trending filters
    @Published var trendingTimeFilter: String = "week"
    @Published var trendingGenreFilter: String? = nil

    private var searchTask: Task<Void, Never>?

    enum Tab: String, CaseIterable {
        case home = "Home"
        case search = "Search"
        case library = "Library"
        case trending = "Trending"
        case nowPlaying = "Now Playing"
    }

    enum ViewMode: String, CaseIterable {
        case list = "List"
        case grid = "Grid"
    }

    private init() {}

    func loadTrending() async {
        isLoading = true
        error = nil

        do {
            trendingTracks = try await AudiusAPI.getTrending(
                time: trendingTimeFilter,
                genre: trendingGenreFilter
            )
        } catch {
            if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    func loadFeatured() async {
        do {
            featuredTracks = try await AudiusAPI.getFeaturedTracks()
        } catch {
            // Non-critical — Home falls back to showing trendingTracks if empty
        }
    }

    func applyTrendingFilters() async {
        trendingTracks = []
        await loadTrending()
    }

    func search(query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            do {
                searchResults = try await AudiusAPI.searchTracks(query: query)
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                }
            }
            isSearching = false
        }
    }

    func selectTab(_ tab: Tab) {
        selectedTab = tab
        if tab == .trending && trendingTracks.isEmpty {
            Task { await loadTrending() }
        }
    }
}
