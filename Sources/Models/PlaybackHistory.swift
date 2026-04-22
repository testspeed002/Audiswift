import Foundation
import Combine

/// Manages the history of recently played tracks with persistence
@MainActor
class PlaybackHistory: ObservableObject {
    static let shared = PlaybackHistory()

    @Published var recentlyPlayed: [Track] = []
    @Published var isLoading: Bool = false

    private let maxHistorySize = 50
    private let defaults = UserDefaults.standard
    private let historyKey = "playbackHistory"
    private var saveTask: Task<Void, Never>?

    private init() {
        Task {
            await loadHistory()
        }
    }

    /// Add a track to the history
    func add(_ track: Track) {
        // Remove if already exists to move to front
        recentlyPlayed.removeAll { $0.id == track.id }
        recentlyPlayed.insert(track, at: 0)

        // Trim to max size
        if recentlyPlayed.count > maxHistorySize {
            recentlyPlayed = Array(recentlyPlayed.prefix(maxHistorySize))
        }

        // Debounce save
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            if !Task.isCancelled {
                await saveHistory()
            }
        }
    }

    /// Remove a specific track from history
    func remove(_ track: Track) {
        recentlyPlayed.removeAll { $0.id == track.id }
        Task { await saveHistory() }
    }

    /// Clear all history
    func clear() {
        recentlyPlayed.removeAll()
        defaults.removeObject(forKey: historyKey)
    }

    /// Get the most recent tracks, optionally limited
    func getRecent(limit: Int = 20) -> [Track] {
        return Array(recentlyPlayed.prefix(limit))
    }

    /// Check if a track is in history
    func contains(track: Track) -> Bool {
        return recentlyPlayed.contains { $0.id == track.id }
    }

    // MARK: - Persistence

    private func saveHistory() async {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(recentlyPlayed)
            defaults.set(data, forKey: historyKey)
        } catch {
#if DEBUG
            print("[PlaybackHistory] Failed to save history: \(error)")
#endif
        }
    }

    private func loadHistory() async {
        guard let data = defaults.data(forKey: historyKey) else {
            recentlyPlayed = []
            return
        }

        do {
            let decoder = JSONDecoder()
            recentlyPlayed = try decoder.decode([Track].self, from: data)
        } catch {
#if DEBUG
            print("[PlaybackHistory] Failed to load history: \(error)")
#endif
            recentlyPlayed = []
        }
    }
}
