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
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 4)
                            .cornerRadius(2)

                        // Buffered progress (if available)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: geometry.size.width * bufferedProgress, height: 4)
                            .cornerRadius(2)

                        // Current progress
                        Rectangle()
                            .fill(themeManager.currentTheme.accentColor)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .cornerRadius(2)

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
            HStack(spacing: 20) {
                // Track info with accessibility (left column - equal flexible width)
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
                                .frame(width: 44, height: 44)
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    if let user = track.user {
                                        Text(user.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(track.title) by \(track.user?.name ?? "unknown artist")")
                        
                        Button {
                            showingTrackDetail = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(isInfoHovered ? themeManager.currentTheme.accentColor : .secondary)
                                .frame(width: 28, height: 28)
                                .background(isInfoHovered ? themeManager.currentTheme.accentColor.opacity(0.15) : Color.clear)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isInfoHovered = hovering
                            }
                        }
                        .help("View Track Details")
                        .sheet(isPresented: $showingTrackDetail) {
                            NavigationStack {
                                TrackDetailView(track: track, onClose: { showingTrackDetail = false })
                                    .navigationDestination(for: User.self)     { user     in UserProfileView(user: user) }
                                    .navigationDestination(for: Playlist.self) { playlist in PlaylistDetailView(playlist: playlist) }
                                    .navigationDestination(for: Track.self)    { track    in TrackDetailView(track: track) }
                            }
                            .frame(width: 600, height: 500)
                            .environmentObject(playerManager)
                            .environmentObject(themeManager)
                            .presentationBackground(themeManager.currentTheme.backgroundColor)
                        }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .cornerRadius(6)
                        Text("Not Playing")
                            .foregroundColor(.secondary)
                            .frame(width: 160, alignment: .leading)
                            .accessibilityLabel("No track currently playing")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Transport controls with accessibility (center column - natural width)
                HStack(spacing: 20) {
                    // Shuffle
                    Button { playerManager.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.caption)
                            .foregroundColor(playerManager.shuffleEnabled ? themeManager.currentTheme.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle")
                    .accessibilityValue(playerManager.shuffleEnabled ? "On" : "Off")
                    .help("Toggle shuffle")

                    // Previous
                    Button { playerManager.playPrevious() } label: {
                        Image(systemName: "backward.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .accessibilityLabel("Previous track")
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .help("Previous track (⌘←)")

                    // Play / Pause with buffering ring
                    Button { playerManager.togglePlayPause() } label: {
                        ZStack {
                            if playerManager.isBuffering {
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(themeManager.currentTheme.accentColor, lineWidth: 2)
                                    .frame(width: 38, height: 38)
                                    .rotationEffect(Angle(degrees: isBufferingSpin ? 360 : 0))
                                    .onAppear {
                                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                            isBufferingSpin = true
                                        }
                                    }
                            }
                            Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .opacity(playerManager.isBuffering ? 0.4 : 1.0)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .accessibilityLabel(playerManager.isPlaying ? "Pause" : "Play")
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Play/Pause (Space)")

                    // Next
                    Button { playerManager.playNext() } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .accessibilityLabel("Next track")
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .help("Next track (⌘→)")

                    // Repeat
                    Button { playerManager.cycleRepeat() } label: {
                        Image(systemName: repeatIcon)
                            .font(.caption)
                            .foregroundColor(playerManager.repeatMode == .off ? .secondary : themeManager.currentTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repeat")
                    .accessibilityValue(repeatModeDescription)
                    .help("Cycle repeat mode: \(repeatModeDescription)")
                }

                // Volume with accessibility (right column - equal flexible width)
                HStack(spacing: 8) {
                    Image(systemName: volumeIcon)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    Slider(value: Binding(
                        get: { Double(playerManager.volume) },
                        set: { playerManager.volume = Float($0) }
                    ), in: 0...1)
                    .frame(width: 90)
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(Int(playerManager.volume * 100)) percent")
                    .help("Volume (⌘↑ / ⌘↓)")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(height: 96)
        .background(
            ZStack {
                // Base warm-tinted glass
                Rectangle()
                    .fill(themeManager.currentTheme.panelColor.opacity(0.85))
                
                // Frosted glass material
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                
                // Subtle gradient tint from accent
                LinearGradient(
                    colors: [
                        themeManager.currentTheme.accentColor.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(alignment: .top) {
            // Top separator with accent glow
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            themeManager.currentTheme.accentColor.opacity(0.3),
                            themeManager.currentTheme.glassEdgeColor
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
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
        // Guard against invalid values
        guard time.isFinite else { return "0:00" }
        let m = max(0, Int(time) / 60)
        let s = max(0, Int(time) % 60)
        return String(format: "%d:%02d", m, s)
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
