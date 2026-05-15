import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingTrackDetail = false
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isInfoHovered = false
    @State private var isBufferingSpin = false
    @State private var showingUpNext = false
    @State private var showingSleepTimer = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Enhanced Progress scrubber with hover preview + inline time labels ─
            HStack(spacing: 8) {
                Text(formatTime(playerManager.currentTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityLabel("Current time \(formatTime(playerManager.currentTime))")

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Spacer that fills the GeometryReader so child rectangles can vertically center
                        Color.clear

                        // Background track
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)

                        // Buffered progress (if available)
                        Capsule()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: geometry.size.width * bufferedProgress, height: 4)

                        // Current progress
                        Capsule()
                            .fill(themeManager.currentTheme.accentColor)
                            .frame(width: geometry.size.width * progress, height: 4)

                        // Draggable thumb (only visible when playing or hovering)
                        Circle()
                            .fill(themeManager.currentTheme.accentColor)
                            .frame(width: isHovering || playerManager.isPlaying ? 12 : 0, height: isHovering || playerManager.isPlaying ? 12 : 0)
                            .position(x: geometry.size.width * progress, y: geometry.size.height / 2)
                            .shadow(radius: 2)
                            .animation(.easeInOut(duration: 0.1), value: isHovering)
                    }
                    // Invisible tall layer for a generous hit area
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let p = max(0, min(1, value.location.x / geometry.size.width))
                                playerManager.seek(to: p * playerManager.duration)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            isHovering = true
                            hoverLocation = location.x
                        case .ended:
                            isHovering = false
                            hoverLocation = 0
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    containerWidth = geo.size.width
                                }
                                .onChange(of: geo.size.width) {
                                    containerWidth = geo.size.width
                                }
                        }
                    )
                    // Hover time tooltip
                    .overlay(
                        hoverTimePreview
                            .opacity(isHovering ? 1 : 0)
                            .animation(.easeInOut(duration: 0.15), value: isHovering),
                        alignment: .top
                    )
                }
                .frame(height: 20)

                Text(formatTime(playerManager.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
                    .accessibilityLabel("Duration \(formatTime(playerManager.duration))")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // ── Main controls row ──────────────────────────────────────
            HStack(spacing: 0) {
                // Track info (Left)
                HStack(spacing: 12) {
                    if let track = playerManager.currentTrack {
                        Button {
                            viewModel.selectedTab = .nowPlaying
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(artwork: track.artwork, size: .small) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(Color.gray.opacity(0.2))
                                }
                                .frame(width: 48, height: 48)
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let user = track.user {
                                        Text(user.name)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 200, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(track.title)
                        
                        Button {
                            showingTrackDetail = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(isInfoHovered ? themeManager.currentTheme.accentColor : .secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .onHover { isInfoHovered = $0 }
                        .help("Track Details")
                        .popover(isPresented: $showingTrackDetail) {
                            TrackDetailPopover(track: track)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 48, height: 48)
                                .cornerRadius(6)
                            Text("Not Playing")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 220, alignment: .leading)
                    }
                }
                .frame(width: 280, alignment: .leading)

                Spacer()

                // Transport controls (Center)
                VStack(spacing: 4) {
                    HStack(spacing: 24) {
                        Button { playerManager.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14))
                                .foregroundColor(playerManager.shuffleEnabled ? themeManager.currentTheme.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Shuffle")

                        Button { playerManager.playPrevious() } label: {
                            Image(systemName: "backward.fill").font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Previous")

                        Button { playerManager.togglePlayPause() } label: {
                            ZStack {
                                if playerManager.isBuffering {
                                    Circle()
                                        .trim(from: 0, to: 0.7)
                                        .stroke(themeManager.currentTheme.accentColor, lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                        .rotationEffect(Angle(degrees: isBufferingSpin ? 360 : 0))
                                        .onAppear {
                                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                                isBufferingSpin = true
                                            }
                                        }
                                }
                                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 44))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(themeManager.currentTheme.accentColor)
                                    .opacity(playerManager.isBuffering ? 0.4 : 1.0)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Play/Pause")

                        Button { playerManager.playNext() } label: {
                            Image(systemName: "forward.fill").font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Next")

                        Button { playerManager.cycleRepeat() } label: {
                            Image(systemName: playerManager.repeatMode.icon)
                                .font(.system(size: 14))
                                .foregroundColor(playerManager.repeatMode == .off ? .secondary : themeManager.currentTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Repeat")
                    }
                }
                .frame(width: 320)

                Spacer()

                // Volume & Extra Features (Right)
                HStack(spacing: 16) {
                    // Sleep Timer Chip
                    if playerManager.sleepTimerEndsAt != nil || playerManager.sleepAfterCurrentTrack {
                        Button {
                            showingSleepTimer = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.system(size: 10, weight: .bold))
                                if let endsAt = playerManager.sleepTimerEndsAt {
                                    Text(endsAt, style: .timer)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                } else {
                                    Text("Track")
                                        .font(.system(size: 8, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(themeManager.currentTheme.accentColor.opacity(0.15))
                            .foregroundColor(themeManager.currentTheme.accentColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingSleepTimer) {
                            SleepTimerPopover()
                        }
                    } else {
                        Button {
                            showingSleepTimer = true
                        } label: {
                            Image(systemName: "timer")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingSleepTimer) {
                            SleepTimerPopover()
                        }
                    }

                    // Up Next Button
                    Button {
                        showingUpNext.toggle()
                    } label: {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 14))
                            .foregroundColor(showingUpNext ? themeManager.currentTheme.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Up Next")
                    .popover(isPresented: $showingUpNext, arrowEdge: .top) {
                        UpNextPopover()
                            .frame(width: 320, height: 400)
                    }

                    // Volume
                    HStack(spacing: 8) {
                        Image(systemName: volumeIcon)
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        
                        Slider(value: Binding(
                            get: { Double(playerManager.volume) },
                            set: { playerManager.volume = Float($0) }
                        ), in: 0...1)
                        .frame(width: 80)
                        .tint(themeManager.currentTheme.accentColor) // Use tint for modern SwiftUI
                        .accentColor(themeManager.currentTheme.accentColor)
                    }
                }
                .frame(width: 280, alignment: .trailing)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 12)
        }
        .frame(height: 100)
        // The frosted chrome now lives full-width at the window level
        // (ContentView.playerBarChrome) so it spans past this view's
        // maxWidth-1100 cap — no bare flanks beside the controls. Matches the
        // LMA pattern.
    }

    // MARK: - Hover Time Preview

    private var hoverTimePreview: some View {
        GeometryReader { geometry in
            // Guard against zero containerWidth to prevent division by zero
            let previewTime: TimeInterval = containerWidth > 0
                ? Double(hoverLocation / containerWidth) * playerManager.duration
                : 0
            Text(formatTime(previewTime))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                )
                .position(
                    x: containerWidth > 0 ? min(max(hoverLocation, 30), containerWidth - 30) : 30,
                    y: -15
                )
        }
    }

    // MARK: - Helpers

    private var progress: Double {
        guard playerManager.duration > 0 else { return 0 }
        return playerManager.currentTime / playerManager.duration
    }

    private var bufferedProgress: Double {
        // Estimate buffer as 10 seconds ahead or 20% of duration
        guard playerManager.duration > 0 else { return 0 }
        let bufferSeconds: Double = 10
        let bufferedTime = playerManager.currentTime + bufferSeconds
        return min(bufferedTime / playerManager.duration, 1.0)
    }

    private var volumeIcon: String {
        switch playerManager.volume {
        case 0:         return "speaker.slash.fill"
        case ..<0.33:   return "speaker.wave.1.fill"
        case ..<0.66:   return "speaker.wave.2.fill"
        default:        return "speaker.wave.3.fill"
        }
    }

    private var repeatIcon: String {
        playerManager.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatModeDescription: String {
        switch playerManager.repeatMode {
        case .off: return "Off"
        case .one: return "Repeat one"
        case .all: return "Repeat all"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Subviews

struct SleepTimerPopover: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Sleep Timer")
                .font(.headline)
                .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 4) {
                    timerButton(label: "Off", minutes: nil)
                    timerButton(label: "End of Track", minutes: 0)
                    Divider().padding(.vertical, 4)
                    timerButton(label: "5 Minutes", minutes: 5)
                    timerButton(label: "10 Minutes", minutes: 10)
                    timerButton(label: "15 Minutes", minutes: 15)
                    timerButton(label: "30 Minutes", minutes: 30)
                    timerButton(label: "45 Minutes", minutes: 45)
                    timerButton(label: "1 Hour", minutes: 60)
                }
                .padding(8)
            }
        }
        .frame(width: 200, height: 320)
    }

    private func timerButton(label: String, minutes: Int?) -> some View {
        Button {
            if let mins = minutes {
                if mins == 0 {
                    playerManager.setSleepAfterCurrentTrack(true)
                } else {
                    playerManager.setSleepTimer(minutes: mins)
                }
            } else {
                playerManager.setSleepTimer(minutes: nil)
            }
            dismiss()
        } label: {
            HStack {
                Text(label)
                Spacer()
                if let mins = minutes {
                    if mins == 0 && playerManager.sleepAfterCurrentTrack {
                        Image(systemName: "checkmark").font(.caption)
                    } else if mins > 0 && playerManager.sleepTimerEndsAt != nil {
                        // Check if this specific minute choice is active (rough check)
                        // In practice, we just show a check if ANY timer is active.
                    }
                } else if playerManager.sleepTimerEndsAt == nil && !playerManager.sleepAfterCurrentTrack {
                    Image(systemName: "checkmark").font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct TrackDetailPopover: View {
    let track: Track
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Header: larger artwork tile, full-name title, artist link
            HStack(spacing: 14) {
                CachedAsyncImage(artwork: track.artwork, size: .medium) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.headline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let user = track.user {
                        HStack(spacing: 4) {
                            Text(user.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if user.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, themeManager.currentTheme.accentColor)
                                    .font(.caption)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            // ── Metadata grid
            VStack(alignment: .leading, spacing: 8) {
                if let genre = track.genre, !genre.isEmpty {
                    detailRow(label: "Genre", value: genre)
                }
                if let mood = track.mood, !mood.isEmpty {
                    detailRow(label: "Mood", value: mood)
                }
                detailRow(label: "Duration", value: track.formattedDuration)
                if let plays = track.formattedPlayCount {
                    detailRow(label: "Plays", value: plays)
                }
                if let released = track.releaseDate, !released.isEmpty {
                    detailRow(label: "Released", value: String(released.prefix(10)))
                }
            }

            if let tags = track.tags, !tags.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(tags)
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Keyboard Shortcut Support Extension

extension PlayerBarView {
    func setupKeyboardShortcuts() {
        // Register for local keyboard events
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 49: // Space
                playerManager.togglePlayPause()
                return nil // Event handled
            case 123: // Left arrow
                if event.modifierFlags.contains(.command) {
                    playerManager.playPrevious()
                } else {
                    playerManager.seekBackward(10)
                }
                return nil
            case 124: // Right arrow
                if event.modifierFlags.contains(.command) {
                    playerManager.playNext()
                } else {
                    playerManager.seekForward(10)
                }
                return nil
            case 126: // Up arrow
                if event.modifierFlags.contains(.command) {
                    let newVolume = min(playerManager.volume + 0.1, 1.0)
                    playerManager.volume = Float(newVolume)
                    return nil
                }
            case 125: // Down arrow
                if event.modifierFlags.contains(.command) {
                    let newVolume = max(playerManager.volume - 0.1, 0.0)
                    playerManager.volume = Float(newVolume)
                    return nil
                }
            default:
                break
            }
            return event
        }
    }
}
