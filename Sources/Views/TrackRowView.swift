import SwiftUI

// MARK: - Animated Now Playing Indicator

struct NowPlayingIndicator: View {
    let isAnimating: Bool
    var color: Color = .accentColor
    
    @State private var amplitudes: [CGFloat] = [0.4, 0.7, 0.5]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: isAnimating ? amplitudes[i] * 14 : 4)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.4 + Double(i) * 0.15)
                                .repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.3),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 14, height: 14)
        .onAppear {
            if isAnimating {
                amplitudes = [0.9, 0.5, 0.75]
            }
        }
        .onChange(of: isAnimating) { _, playing in
            amplitudes = playing ? [0.9, 0.5, 0.75] : [0.4, 0.4, 0.4]
        }
    }
}

// MARK: - Track Row View

struct TrackRowView: View {
    let track: Track
    var index: Int? = nil
    /// Full list this track belongs to — passed to the player for queue context
    var context: [Track]? = nil
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isHovered = false
    @State private var showingDetails = false

    private var isCurrentTrack: Bool {
        playerManager.currentTrack?.id == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            // Track number or now-playing indicator
            if isCurrentTrack {
                NowPlayingIndicator(
                    isAnimating: playerManager.isPlaying,
                    color: themeManager.currentTheme.accentColor
                )
                .frame(width: 24)
            } else if let index {
                Text("\(index)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }

            CachedAsyncImage(artwork: track.artwork, size: .small) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
            }
            .frame(width: 48, height: 48)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundColor(isCurrentTrack ? themeManager.currentTheme.accentColor : .primary)
                    .lineLimit(1)
                if let user = track.user {
                    NavigationLink(value: user) {
                        Text(user.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if let genre = track.genre {
                Text(genre)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            if track.isAiAttributed {
                Text("AI")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(colors: [Color.purple, Color.indigo],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(4)
            }

            if let plays = track.formattedPlayCount {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                    Text(plays)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            }

            Text(track.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isCurrentTrack
                        ? themeManager.currentTheme.accentColor.opacity(0.1)
                        : (isHovered ? themeManager.currentTheme.hoverColor : Color.clear)
                )
        )
        // Active track left accent bar (classic iTunes style)
        .overlay(alignment: .leading) {
            if isCurrentTrack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(themeManager.currentTheme.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            playerManager.play(track: track, context: context)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button("Play") { playerManager.play(track: track, context: context) }
            Button("Play Next") { playerManager.insertNext(track: track) }
            Button("Copy Track Link") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("https://audius.co/tracks/\(track.id)", forType: .string)
            }
            Button("View Track Details") { showingDetails = true }
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                TrackDetailView(track: track, onClose: { showingDetails = false })
                    .navigationDestination(for: User.self)     { user     in UserProfileView(user: user) }
                    .navigationDestination(for: Playlist.self) { playlist in PlaylistDetailView(playlist: playlist) }
                    .navigationDestination(for: Track.self)    { track    in TrackDetailView(track: track) }
            }
            .frame(width: 600, height: 500)
            .environmentObject(playerManager)
            .environmentObject(themeManager)
            .presentationBackground(themeManager.currentTheme.backgroundColor)
        }
    }
}
