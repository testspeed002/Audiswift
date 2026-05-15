import SwiftUI

/// Popover listing the upcoming Audius queue. Drag-reorder + per-row remove.
struct UpNextPopover: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                Spacer()
                if !playerManager.upNext.isEmpty {
                    Button("Clear") {
                        playerManager.clearUpNext()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if let current = playerManager.currentTrack {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(themeManager.currentTheme.accentColor)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(current.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if let artist = current.user?.name {
                            Text(artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("Now Playing")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.currentTheme.accentColor.opacity(0.08))
                        .padding(.horizontal, 6)
                )

                Divider()
            }

            if playerManager.upNext.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Nothing queued")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Tracks coming up will appear here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(playerManager.upNext.enumerated()), id: \.element.id) { (offset, track) in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.callout)
                                    .lineLimit(1)
                                if let artist = track.user?.name {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(track.formattedDuration)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            Button {
                                playerManager.removeUpNext(at: offset)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from queue")
                        }
                        .contentShape(Rectangle())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        playerManager.moveUpNext(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(themeManager.currentTheme.backgroundColor)
    }
}
