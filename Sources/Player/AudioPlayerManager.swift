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
    /// Last user-facing playback error. Set when a stream fails to load.
    /// Views can observe and present a toast; clearing is the consumer's job.
    @Published var lastErrorMessage: String?
    
    /// When non-nil, playback will pause at this wall-clock instant. The player
    /// bar shows a countdown chip and a cancel affordance.
    @Published var sleepTimerEndsAt: Date?
    /// When true, playback will pause when the current track finishes
    /// (mutually exclusive with `sleepTimerEndsAt`).
    @Published var sleepAfterCurrentTrack: Bool = false

    /// Throttle MPNowPlayingInfoCenter updates to ~1 Hz. The system menu bar
    /// doesn't need sub-second precision, and firing at display refresh rate
    /// (60–120 Hz) wastes CPU on dictionary copies and IPC.
    private var lastNowPlayingUpdate: TimeInterval = 0

    /// Upcoming tracks after the currently-playing one. Recomputed on every
    /// queue mutation so the Up Next popover reflects the live state.
    @Published private(set) var upNext: [Track] = []
    private var sleepTimer: Timer?

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
        defaults.register(defaults: ["rememberPlaybackState": true])
        let shouldRemember = defaults.bool(forKey: "rememberPlaybackState")
        
        // Always restore shuffle/repeat — these don't depend on the track.
        shuffleEnabled = defaults.bool(forKey: Keys.shuffleEnabled)
        if let repeatRaw = defaults.string(forKey: Keys.repeatMode),
           let restoredRepeat = RepeatMode(rawValue: repeatRaw) {
            repeatMode = restoredRepeat
        }

        if !shouldRemember { return }

        guard let trackID = defaults.string(forKey: Keys.lastTrackID) else { return }
        let lastTime = defaults.double(forKey: Keys.lastPlaybackTime)

        do {
            // Fetch the track
            let track = try await AudiusAPI.getTrack(trackId: trackID)
            
            // Rebuild the queue context if we saved one.
            let savedContextIDs = defaults.array(forKey: Keys.lastContextIDs) as? [String] ?? []
            var restoredContext: [Track] = []
            if !savedContextIDs.isEmpty {
                for id in savedContextIDs {
                    if let ctxTrack = try? await AudiusAPI.getTrack(trackId: id) {
                        restoredContext.append(ctxTrack)
                    }
                }
            }

            // Cue the track up but DON'T auto-play.
            cueTrack(track, context: restoredContext, at: lastTime)

        } catch {
#if DEBUG
            print("[Player] Failed to restore playback state: \(error)")
#endif
        }
    }

    /// Load a track without starting playback. Used by restorePlaybackState()
    /// to bring the previous session back without surprising the user.
    private func cueTrack(_ track: Track, context: [Track], at startTime: TimeInterval) {
        guard let streamURL = AudiusAPI.getTrackStreamURL(trackId: track.id) else { return }

        playContext = context
        if shuffleEnabled {
            buildShuffledOrder(startingAt: context.firstIndex(where: { $0.id == track.id }) ?? 0)
        } else {
            currentContextIndex = context.firstIndex(where: { $0.id == track.id }) ?? -1
        }

        stopInternal()

        playerItem = AVPlayerItem(url: streamURL)
        if let item = playerItem {
            FFTAnalyzer.shared.attachTap(to: item)
        }
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        currentTrack = track
        duration = TimeInterval(track.duration)

        setupTimeObserver()
        setupItemObservers()

        // Seek to last position without playing.
        if startTime > 1, startTime < duration - 1 {
            let cmTime = CMTime(seconds: startTime, preferredTimescale: 600)
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = startTime
        }

        isPlaying = false
        isBuffering = false

        Task { await updateNowPlayingInfo() }
        recomputeUpNext()
    }

    // MARK: - Playback

    func play(track: Track, context: [Track]? = nil) {
        guard let streamURL = AudiusAPI.getTrackStreamURL(trackId: track.id) else {
#if DEBUG
            print("[Player] Invalid stream URL for track: \(track.id)")
#endif
            lastErrorMessage = "Track unavailable: \(track.title)"
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
        recomputeUpNext()
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
        else {
            // End of queue with no repeat: AVPlayer has stopped on its own but
            // the published isPlaying flag would otherwise stay true, leaving
            // the player bar stuck on the pause icon. Reset state so the UI
            // reflects reality.
            player?.pause()
            isPlaying = false
        }
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
        recomputeUpNext()
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
        recomputeUpNext()
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
        // Tie the periodic time observer to the main display's refresh
        // rate (60 Hz on standard panels, 120 Hz on ProMotion) so the
        // scrubber updates as fast as the screen can show them. Floors at
        // 60 Hz so we always sample at least that often regardless of how
        // the display reports.
        let displayHz = max(60, NSScreen.main?.maximumFramesPerSecond ?? 60)
        let interval = CMTime(seconds: 1.0 / Double(displayHz), preferredTimescale: 60000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard let item = self.playerItem else { return }
                self.currentTime = time.seconds
                let d = item.duration.seconds
                if d.isFinite && !d.isNaN && d > 0 { self.duration = d }
                // Rate-limit MPNowPlayingInfoCenter to ~1 Hz. The system menu
                // bar doesn't need 60+ updates per second.
                let now = CACurrentMediaTime()
                if now - self.lastNowPlayingUpdate >= 1.0 {
                    self.lastNowPlayingUpdate = now
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.seconds
                }
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
                    let title = self?.currentTrack?.title ?? "track"
                    self?.lastErrorMessage = "Playback failed: \(title)"
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
                    // Sleep timer: "after current track" — honor here before advancing.
                    if self.sleepAfterCurrentTrack {
                        self.sleepAfterCurrentTrack = false
                        self.player?.pause()
                        self.isPlaying = false
                        return
                    }
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

    // MARK: - Sleep Timer

    /// Schedule a pause N minutes from now. Pass `nil` to cancel any active
    /// timer. Replaces any existing wall-clock sleep timer or "after current
    /// track" mode.
    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepAfterCurrentTrack = false
        guard let minutes = minutes, minutes > 0 else {
            sleepTimerEndsAt = nil
            return
        }
        let interval = TimeInterval(minutes * 60)
        sleepTimerEndsAt = Date().addingTimeInterval(interval)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.sleepTimerEndsAt = nil
                self?.sleepTimer = nil
                self?.player?.pause()
                self?.isPlaying = false
            }
        }
    }

    /// Toggle "stop after current track" mode. Mutually exclusive with the
    /// wall-clock timer.
    func setSleepAfterCurrentTrack(_ enabled: Bool) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil
        sleepAfterCurrentTrack = enabled
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

    // MARK: - Up Next queue

    /// Indices into `playContext` for the upcoming tracks (in play order),
    /// excluding the currently playing one.
    private func upNextIndices() -> [Int] {
        guard !playContext.isEmpty else { return [] }
        if shuffleEnabled {
            guard let pos = shuffledOrder.firstIndex(of: currentContextIndex) else { return [] }
            return Array(shuffledOrder[(pos + 1)...])
        } else {
            guard currentContextIndex >= 0 else { return [] }
            let start = currentContextIndex + 1
            guard start < playContext.count else { return [] }
            return Array(start..<playContext.count)
        }
    }

    /// Rebuild the published `upNext` array from current queue state.
    func recomputeUpNext() {
        let idxs = upNextIndices()
        upNext = idxs.compactMap { playContext[safe: $0] }
    }

    /// Remove the upcoming track at the given offset (0 = next track).
    func removeUpNext(at offset: Int) {
        let idxs = upNextIndices()
        guard idxs.indices.contains(offset) else { return }
        let trackIndex = idxs[offset]
        if shuffleEnabled {
            shuffledOrder.removeAll { $0 == trackIndex }
            // Reindex playContext to preserve currentContextIndex after deletion.
            playContext.remove(at: trackIndex)
            shuffledOrder = shuffledOrder.map { $0 > trackIndex ? $0 - 1 : $0 }
            if currentContextIndex > trackIndex { currentContextIndex -= 1 }
        } else {
            playContext.remove(at: trackIndex)
        }
        recomputeUpNext()
    }

    /// Move an upcoming track from one offset to another within the Up Next list.
    func moveUpNext(from source: IndexSet, to destination: Int) {
        var idxs = upNextIndices()
        let movedTracks = source.sorted().compactMap { idxs.indices.contains($0) ? playContext[safe: idxs[$0]] : nil }
        guard !movedTracks.isEmpty else { return }

        // Remove from playContext (highest first to keep indices stable).
        let sortedSourceIdxs = source.sorted(by: >).compactMap { idxs.indices.contains($0) ? idxs[$0] : nil }
        for ci in sortedSourceIdxs {
            if shuffleEnabled {
                shuffledOrder.removeAll { $0 == ci }
                playContext.remove(at: ci)
                shuffledOrder = shuffledOrder.map { $0 > ci ? $0 - 1 : $0 }
                if currentContextIndex > ci { currentContextIndex -= 1 }
            } else {
                playContext.remove(at: ci)
            }
        }

        // Recompute insertion point in the (now-shrunk) up-next list.
        idxs = upNextIndices()
        let clampedDest = max(0, min(destination - source.filter { $0 < destination }.count, idxs.count))
        let insertContextIndex: Int = {
            if clampedDest >= idxs.count {
                return playContext.count
            } else {
                return idxs[clampedDest]
            }
        }()

        if shuffleEnabled {
            for (k, t) in movedTracks.enumerated() {
                playContext.insert(t, at: insertContextIndex + k)
            }
            // Rebuild shuffledOrder positions for the inserted ones inline.
            let bumpFrom = insertContextIndex
            shuffledOrder = shuffledOrder.map { $0 >= bumpFrom ? $0 + movedTracks.count : $0 }
            if currentContextIndex >= bumpFrom { currentContextIndex += movedTracks.count }
            if let currentPos = shuffledOrder.firstIndex(of: currentContextIndex) {
                let newIdxs = (0..<movedTracks.count).map { bumpFrom + $0 }
                shuffledOrder.insert(contentsOf: newIdxs, at: currentPos + 1 + clampedDest)
            }
        } else {
            for (k, t) in movedTracks.enumerated() {
                playContext.insert(t, at: insertContextIndex + k)
            }
        }
        recomputeUpNext()
    }

    /// Clear all upcoming tracks (keep current one playing).
    func clearUpNext() {
        let idxs = upNextIndices().sorted(by: >)
        for ci in idxs {
            if shuffleEnabled {
                shuffledOrder.removeAll { $0 == ci }
            }
            playContext.remove(at: ci)
        }
        recomputeUpNext()
    }
}

// MARK: - Safe subscript


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
