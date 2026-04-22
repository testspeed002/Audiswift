import Foundation
import AVFoundation
import Combine
import AppKit
import MediaPlayer

@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    // MARK: - Published state

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 { didSet { player?.volume = volume; saveVolumeToDefaults() } }
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    enum RepeatMode: String, CaseIterable {
        case off = "off"
        case one = "one"
        case all = "all"

        var icon: String {
            switch self {
            case .off: return "repeat"
            case .one: return "repeat.1"
            case .all: return "repeat"
            }
        }
    }

    // MARK: - Private state

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    private var nowPlayingArtwork: NSImage?
    private var nowPlayingArtworkTrackID: String?

    /// Full context list that was active when playback started (used for next/prev)
    private var playContext: [Track] = []
    /// Shuffled order indices into playContext
    private var shuffledOrder: [Int] = []
    /// Current position inside playContext (or shuffledOrder)
    private var currentContextIndex: Int = -1

    // MARK: - Persistence keys
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let lastTrackID = "lastTrackID"
        static let lastPlaybackTime = "lastPlaybackTime"
        static let lastContextIDs = "lastContextIDs"
        static let volume = "playerVolume"
        static let shuffleEnabled = "shuffleEnabled"
        static let repeatMode = "repeatMode"
    }

    // MARK: - Init

    private init() {
        setupRemoteCommandCenter()
        setupAudioSessionNotifications()
        restoreVolumeFromDefaults()
    }

    // MARK: - Audio Session Notifications

    private func setupAudioSessionNotifications() {
        // Save state before sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.savePlaybackState()
            }
        }
    }

    // MARK: - Volume Persistence

    private func saveVolumeToDefaults() {
        defaults.set(volume, forKey: Keys.volume)
    }

    private func restoreVolumeFromDefaults() {
        defaults.register(defaults: [Keys.volume: 1.0])
        volume = defaults.float(forKey: Keys.volume)
    }

    // MARK: - Playback State Persistence

    func savePlaybackState() {
        guard let track = currentTrack else {
            defaults.removeObject(forKey: Keys.lastTrackID)
            defaults.removeObject(forKey: Keys.lastPlaybackTime)
            return
        }

        defaults.set(track.id, forKey: Keys.lastTrackID)
        defaults.set(currentTime, forKey: Keys.lastPlaybackTime)
        defaults.set(playContext.map(\.id), forKey: Keys.lastContextIDs)
        defaults.set(currentContextIndex, forKey: "lastContextIndex")
        defaults.set(shuffleEnabled, forKey: Keys.shuffleEnabled)
        defaults.set(repeatMode.rawValue, forKey: Keys.repeatMode)
    }

    func restorePlaybackState() async {
        guard let trackID = defaults.string(forKey: Keys.lastTrackID),
              let lastTime = defaults.object(forKey: Keys.lastPlaybackTime) as? TimeInterval else {
            return
        }

        do {
            // Fetch the track
            let track = try await AudiusAPI.getTrack(trackId: trackID)
            
            // Don't auto-resume if too much time has passed (e.g., > 5 seconds from end)
            guard lastTime < Double(track.duration) - 5 else { return }

            // Restore context if available
            if let contextIDs = defaults.stringArray(forKey: Keys.lastContextIDs) {
                // Fetch all tracks in context
                var restoredContext: [Track] = []
                for id in contextIDs {
                    if let ctxTrack = try? await AudiusAPI.getTrack(trackId: id) {
                        restoredContext.append(ctxTrack)
                    }
                }
                playContext = restoredContext
            }

            // Restore shuffle and repeat
            shuffleEnabled = defaults.bool(forKey: Keys.shuffleEnabled)
            if let repeatRaw = defaults.string(forKey: Keys.repeatMode),
               let restoredRepeat = RepeatMode(rawValue: repeatRaw) {
                repeatMode = restoredRepeat
            }

            // Find current position in context
            currentContextIndex = playContext.firstIndex(where: { $0.id == trackID }) ?? -1

            // Start playback at saved position
            play(track: track, context: playContext.isEmpty ? nil : playContext)
            seek(to: lastTime)

            // Don't auto-play, just restore position
            player?.pause()
            isPlaying = false

        } catch {
#if DEBUG
            print("[Player] Failed to restore playback state: \(error)")
#endif
        }
    }

    // MARK: - Playback

    func play(track: Track, context: [Track]? = nil) {
        guard let streamURL = AudiusAPI.getTrackStreamURL(trackId: track.id) else {
#if DEBUG
            print("[Player] Invalid stream URL for track: \(track.id)")
#endif
            return
        }

        if currentTrack?.id == track.id {
            player?.play()
            isPlaying = true
            Task { await updateNowPlayingInfo() }
            return
        }

        // Update queue context
        if let context {
            playContext = context
            if shuffleEnabled {
                buildShuffledOrder(startingAt: context.firstIndex(where: { $0.id == track.id }) ?? 0)
            } else {
                currentContextIndex = context.firstIndex(where: { $0.id == track.id }) ?? -1
            }
        }

        stopInternal()

        playerItem = AVPlayerItem(url: streamURL)
        if let item = playerItem {
            FFTAnalyzer.shared.attachTap(to: item)
        }
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        currentTrack = track
        duration = TimeInterval(track.duration) // pre-load from model

        setupTimeObserver()
        setupItemObservers()

        player?.play()
        isPlaying = true
        isBuffering = true

        Task {
            await updateNowPlayingInfo()
            // Add to history
            PlaybackHistory.shared.add(track)
        }
    }

    func togglePlayPause() {
        guard player != nil else { return }
        if isPlaying { 
            player?.pause()
            FFTAnalyzer.shared.reset() 
        } else { 
            player?.play() 
        }
        isPlaying.toggle()
        Task { await updateNowPlayingInfo() }
    }

    func playNext() {
        guard !playContext.isEmpty else { return }
        let next = nextTrack()
        if let next { play(track: next) }
        else if repeatMode == .all, let first = playContext.first { play(track: first) }
    }

    func insertNext(track: Track) {
        if playContext.isEmpty {
            play(track: track)
            return
        }
        
        if !playContext.contains(where: { $0.id == track.id }) {
            playContext.append(track)
        }
        guard let trackIndex = playContext.firstIndex(where: { $0.id == track.id }) else { return }
        
        if shuffleEnabled {
            guard let currentPos = shuffledOrder.firstIndex(of: currentContextIndex) else { return }
            shuffledOrder.removeAll { $0 == trackIndex }
            shuffledOrder.insert(trackIndex, at: currentPos + 1)
        } else {
            playContext.removeAll { $0.id == track.id }
            let insertIndex = min(currentContextIndex + 1, playContext.count)
            playContext.insert(track, at: insertIndex)
        }
    }

    func playPrevious() {
        // If more than 3 s in, restart; otherwise go to previous
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let prev = previousTrack() else { return }
        play(track: prev)
    }

    func stop() {
        stopInternal()
        currentTrack = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Seeking

    func seek(to time: TimeInterval) {
        let cmt = CMTime(seconds: time, preferredTimescale: 60000)
        player?.seek(to: cmt, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        Task { await updateNowPlayingInfo() }
    }

    func seekForward(_ seconds: TimeInterval = 15) { seek(to: min(currentTime + seconds, duration)) }
    func seekBackward(_ seconds: TimeInterval = 15) { seek(to: max(currentTime - seconds, 0)) }

    // MARK: - Shuffle & Repeat

    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled {
            buildShuffledOrder(startingAt: currentContextIndex)
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Internal helpers

    private func stopInternal() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        cancellables.removeAll()
        player?.pause()
        player = nil
        playerItem = nil
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        FFTAnalyzer.shared.reset()
    }

    private func nextTrack() -> Track? {
        guard !playContext.isEmpty else { return nil }
        if repeatMode == .one { return currentTrack }
        if shuffleEnabled {
            guard let pos = shuffledOrder.firstIndex(of: currentContextIndex) else { return nil }
            let nextPos = pos + 1
            guard nextPos < shuffledOrder.count else { return nil }
            currentContextIndex = shuffledOrder[nextPos]
        } else {
            let nextIdx = currentContextIndex + 1
            guard nextIdx < playContext.count else { return nil }
            currentContextIndex = nextIdx
        }
        return playContext[safe: currentContextIndex]
    }

    private func previousTrack() -> Track? {
        guard !playContext.isEmpty else { return nil }
        if shuffleEnabled {
            guard let pos = shuffledOrder.firstIndex(of: currentContextIndex), pos > 0 else { return nil }
            currentContextIndex = shuffledOrder[pos - 1]
        } else {
            let prevIdx = currentContextIndex - 1
            guard prevIdx >= 0 else { return nil }
            currentContextIndex = prevIdx
        }
        return playContext[safe: currentContextIndex]
    }

    private func buildShuffledOrder(startingAt index: Int) {
        var indices = Array(0..<playContext.count)
        indices.removeAll { $0 == index }
        indices.shuffle()
        shuffledOrder = [index] + indices
        currentContextIndex = index
    }

    // MARK: - Observers

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 60000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard let item = self.playerItem else { return }
                self.currentTime = time.seconds
                let d = item.duration.seconds
                if d.isFinite && !d.isNaN && d > 0 { self.duration = d }
                // Update elapsed in Now Playing
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.seconds
            }
        }
    }

    private func setupItemObservers() {
        playerItem?.publisher(for: \.status)
            .sink { [weak self] status in
                if status == .failed {
#if DEBUG
                    print("[Player] Item failed: \(String(describing: self?.playerItem?.error))")
#endif
                }
            }
            .store(in: &cancellables)

        playerItem?.publisher(for: \.duration)
            .sink { [weak self] cmDuration in
                guard let self else { return }
                let secs = cmDuration.seconds
                if secs.isFinite && !secs.isNaN && secs > 0 { self.duration = secs }
            }
            .store(in: &cancellables)

        // Buffering state
        playerItem?.publisher(for: \.isPlaybackBufferEmpty)
            .sink { [weak self] isEmpty in
                self?.isBuffering = isEmpty
            }
            .store(in: &cancellables)

        playerItem?.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] isLikelyToKeepUp in
                if isLikelyToKeepUp {
                    self?.isBuffering = false
                }
            }
            .store(in: &cancellables)

        // Auto-advance when item finishes
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    switch self.repeatMode {
                    case .one:
                        self.seek(to: 0)
                        self.player?.play()
                    case .all, .off:
                        self.playNext()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - MPRemoteCommandCenter

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, !self.isPlaying else { return .commandFailed }
            self.togglePlayPause(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.togglePlayPause(); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious(); return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime); return .success
        }
    }

    private func updateNowPlayingInfo() async {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                        track.title,
            MPMediaItemPropertyArtist:                      track.user?.name ?? "",
            MPMediaItemPropertyPlaybackDuration:            duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime:    currentTime,
            MPNowPlayingInfoPropertyPlaybackRate:           isPlaying ? 1.0 : 0.0
        ]
        // Artwork caching
        if track.id != nowPlayingArtworkTrackID {
            nowPlayingArtwork = nil
            if let artURLString = track.artwork?.url(size: .medium),
               let artURL = URL(string: artURLString),
               let (data, _) = try? await URLSession.shared.data(from: artURL) {
                nowPlayingArtwork = NSImage(data: data)
                nowPlayingArtworkTrackID = track.id
            }
        }
        
        if let nsImage = nowPlayingArtwork {
            let size = CGSize(width: 480, height: 480)
            let artwork = MPMediaItemArtwork(boundsSize: size) { _ in nsImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Lifecycle

    deinit {
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(nil)
        if let observer = timeObserver { player?.removeTimeObserver(observer) }

        // Remove workspace observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

// MARK: - Safe subscript


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
